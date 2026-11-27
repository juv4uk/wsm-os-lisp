#!/usr/bin/env bash
# ADR-006 P1 control: a freestanding Pascal UNIT runs on the target.
# This is the stable FPC 3.2.2 Linux-target control, not the embedded probe.
# No Pascal PROGRAM startup hooks and no no-op RTL stubs are linked.
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

ppc="${FPC_PPCX64:-}"
if [[ -z "$ppc" ]]; then ppc="$(command -v ppcx64 || true)"; fi
if [[ -z "$ppc" ]]; then
  for candidate in /usr/lib/x86_64-linux-gnu/fpc/*/ppcx64 /usr/lib/fpc/*/ppcx64; do
    [[ -x "$candidate" ]] && ppc="$candidate" && break
  done
fi
[[ -n "$ppc" && -x "$ppc" ]] || fail "ppcx64 not found"
got_version="$("$ppc" -iV 2>/dev/null | tr -d '\r')"
[[ "$got_version" == "$expected_version" ]] || fail "FPC version drift: expected $expected_version, got $got_version"

units_dir="${FPC_UNITS_DIR:-}"
if [[ -z "$units_dir" ]]; then
  for candidate in /usr/lib/x86_64-linux-gnu/fpc/*/units/x86_64-linux /usr/lib/fpc/*/units/x86_64-linux; do
    [[ -d "$candidate/rtl" ]] && units_dir="$candidate" && break
  done
fi
[[ -n "$units_dir" && -d "$units_dir/rtl" ]] || fail "FPC RTL units not found"

rm -rf "$out_dir"
mkdir -p "$out_dir"
"$ppc" -Tlinux -O- -Xs- -CX -Cn \
  -Fu"$units_dir/rtl" -Fu"$units_dir/rtl-objpas" \
  -FE"$out_dir" -FU"$out_dir" src/pascal_probe.pas > "$out_dir/compile.txt" 2>&1 \
  || fail "FPC unit compile failed"
[[ -s "$out_dir/pascal_probe.o" ]] || fail "FPC produced no unit object"
nm -u "$out_dir/pascal_probe.o" > "$out_dir/object-undefined-symbols.txt" 2>&1 || true
undefined="$(awk '{print $2}' "$out_dir/object-undefined-symbols.txt" | tr '\n' ' ')"
[[ "$undefined" == "wsm_cons " ]] || {
  cat "$out_dir/object-undefined-symbols.txt" >&2
  fail "expected only Assembly wsm_cons import; no FPC startup hooks"
}

bash scripts/build-uefi-image.sh "$out_dir/pascal_probe.o" "$out_dir/pascal.img" > "$out_dir/image-build.txt" \
  || fail "image build failed"
kernel="target/kernel-x86_64"
[[ -s "$kernel" ]] || fail "linked kernel missing"
nm -u "$kernel" > "$out_dir/kernel-undefined-symbols.txt" 2>&1 || true
[[ ! -s "$out_dir/kernel-undefined-symbols.txt" ]] || fail "undefined symbols in final kernel"

asm_fixture="artifacts/qemu-serial-transcript.txt"
[[ -s "$asm_fixture" ]] || fail "ASM fixture transcript missing"
WSM_QEMU_TRANSCRIPT="$transcript" \
WSM_QEMU_RAW_SERIAL_COPY="$out_dir/pascal-serial.log" \
  bash scripts/run-qemu-uefi.sh "$out_dir/pascal.img" > "$out_dir/qemu.stdout" 2> "$out_dir/qemu.stderr" \
  || fail "QEMU witness failed"
observed="$(tr -d '\r' < "$out_dir/pascal-serial.log" | grep '^WSM-OS RESULT' || true)"
expected="$(tr -d '\r' < "$asm_fixture" | grep '^WSM-OS RESULT' | head -1)"
[[ -n "$observed" && "$observed" == "$expected" ]] || fail "parity broken: Pascal RESULT differs from ASM baseline"

printf 'PASS pascal-unit  %s\n' "$observed"
echo "FPC-KERNEL-SKELETON-PASS: FPC $got_version, unit-only, no RTL stubs, byte-identical RESULT"
