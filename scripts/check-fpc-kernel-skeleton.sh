#!/usr/bin/env bash
# ADR-006 P1 gate: Pascal code runs on the target.
#
# Proves four things, each separately observable:
#   1. the pinned FPC compiles src/pascal_probe.pas with -Cn (no host link);
#   2. the object links with src/linker.ld and src/rtl_min.s into a kernel with
#      ZERO undefined symbols (nm -u is empty);
#   3. the UEFI/QEMU boot reaches the unchanged BOOT line;
#   4. the RESULT line is byte-identical to the hand-written assembly fixture,
#      so Pascal and asm agree on the ABI rather than merely both running.
#
# Fail closed on: missing compiler, version drift, any undefined symbol.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

out_dir="${WSM_FPC_OUT_DIR:-target/fpc-kernel-skeleton}"
expected_version="${WSM_FPC_VERSION:-3.2.2}"
transcript="artifacts/nucleus-witness-pascal-entry-qemu-serial-transcript.txt"

fail() {
  printf 'FPC-KERNEL-SKELETON-FAIL: %s\n' "$1" >&2
  exit 1
}

# --- compiler discovery and pin -------------------------------------------
ppc="${FPC_PPCX64:-}"
if [[ -z "$ppc" ]]; then
  ppc="$(command -v ppcx64 || true)"
fi
if [[ -z "$ppc" ]]; then
  for candidate in /usr/lib/x86_64-linux-gnu/fpc/*/ppcx64 /usr/lib/fpc/*/ppcx64; do
    if [[ -x "$candidate" ]]; then
      ppc="$candidate"
      break
    fi
  done
fi
[[ -n "$ppc" && -x "$ppc" ]] || fail "ppcx64 not found; install fp-compiler or set FPC_PPCX64"

got_version="$("$ppc" -iV 2>/dev/null | tr -d '\r')"
[[ "$got_version" == "$expected_version" ]] \
  || fail "FPC version drift: expected $expected_version, got ${got_version:-none}"

units_dir="${FPC_UNITS_DIR:-}"
if [[ -z "$units_dir" ]]; then
  for candidate in /usr/lib/x86_64-linux-gnu/fpc/*/units/x86_64-linux \
                   /usr/lib/fpc/*/units/x86_64-linux; do
    if [[ -d "$candidate/rtl" ]]; then
      units_dir="$candidate"
      break
    fi
  done
fi
[[ -n "$units_dir" && -d "$units_dir/rtl" ]] || fail "FPC rtl units not found; set FPC_UNITS_DIR"

rm -rf "$out_dir"
mkdir -p "$out_dir"

# --- 1. compile without the host link stage -------------------------------
"$ppc" -Tlinux -O- -Xs- -CX -Cn \
  -Fu"$units_dir/rtl" -Fu"$units_dir/rtl-objpas" \
  -FE"$out_dir" -FU"$out_dir" \
  src/pascal_probe.pas >/dev/null || fail "FPC compile failed"
[[ -s "$out_dir/pascal_probe.o" ]] || fail "FPC produced no object"

# --- 2. link with our linker script and our minimal RTL -------------------
as --64 src/rtl_min.s -o "$out_dir/rtl_min.o" || fail "rtl_min.s assemble failed"
ld -r "$out_dir/pascal_probe.o" "$out_dir/rtl_min.o" -o "$out_dir/pascal_fixture.o" \
  || fail "relocatable merge failed"

bash scripts/build-uefi-image.sh "$out_dir/pascal_fixture.o" "$out_dir/pascal.img" >/dev/null \
  || fail "image build failed"

# build-uefi-image.sh writes target/kernel-x86_64
kernel="target/kernel-x86_64"
[[ -s "$kernel" ]] || fail "linked kernel not found at $kernel"
undefined="$(nm -u "$kernel" | tr -d '\r')"
[[ -z "$undefined" ]] || fail "undefined symbols in the linked kernel: $undefined"

# --- 3/4. boot and compare the transcript ---------------------------------
WSM_QEMU_TRANSCRIPT="$transcript" \
WSM_QEMU_RAW_SERIAL_COPY="$out_dir/pascal-serial.log" \
  bash scripts/run-qemu-uefi.sh "$out_dir/pascal.img" >/dev/null \
  || fail "qemu witness failed"

printf 'PASS pascal-entry  %s\n' \
  "$(tr -d '\r' < "$out_dir/pascal-serial.log" | grep '^WSM-OS ' | tail -1)"
printf 'PASS undefined     none (nm -u on %s is empty)\n' "$kernel"
echo "FPC-KERNEL-SKELETON-PASS: FPC $got_version, freestanding link, transcript parity with the asm fixture"
