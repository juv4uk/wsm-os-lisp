#!/usr/bin/env bash
# ADR-006 P1 remainder: Pascal owns the handoff boundary.
# The record decoder is a separately reusable FPC unit with hosted unit tests.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

out_dir="${WSM_HANDOFF_OUT_DIR:-target/pascal-handoff}"
expected_version="${WSM_FPC_VERSION:-3.2.2}"
fixture_obj="$out_dir/pascal-handoff-fixture.o"

fail() {
  printf 'PASCAL-HANDOFF-FAIL: %s\n' "$1" >&2
  exit 1
}

ppc="${FPC_PPCX64:-}"
[[ -z "$ppc" ]] && ppc="$(command -v ppcx64 || true)"
if [[ -z "$ppc" ]]; then
  for candidate in /usr/lib/x86_64-linux-gnu/fpc/*/ppcx64 /usr/lib/fpc/*/ppcx64; do
    [[ -x "$candidate" ]] && ppc="$candidate" && break
  done
fi
[[ -n "$ppc" && -x "$ppc" ]] || fail "ppcx64 not found; install fp-compiler or set FPC_PPCX64"
[[ "$($ppc -iV | tr -d '\r')" == "$expected_version" ]] \
  || fail "FPC version drift: expected $expected_version"

units_dir="${FPC_UNITS_DIR:-}"
if [[ -z "$units_dir" ]]; then
  for candidate in /usr/lib/x86_64-linux-gnu/fpc/*/units/x86_64-linux \
                   /usr/lib/fpc/*/units/x86_64-linux; do
    [[ -d "$candidate/rtl" ]] && units_dir="$candidate" && break
  done
fi
[[ -n "$units_dir" && -d "$units_dir/rtl" ]] || fail "FPC rtl units not found"

rm -rf "$out_dir"
mkdir -p "$out_dir/bootinfo-tests/bin" "$out_dir/bootinfo-tests/units"

"$ppc" -Tlinux -O- -Xs- -CX \
  -Fu"$ROOT_DIR/src" -Fu"$units_dir/rtl" -Fu"$units_dir/rtl-objpas" \
  -FE"$out_dir/bootinfo-tests/bin" -FU"$out_dir/bootinfo-tests/units" \
  tests/fpc/test_wsm_bootinfo.lpr > "$out_dir/bootinfo-tests/compile.txt" 2>&1 \
  || { cat "$out_dir/bootinfo-tests/compile.txt" >&2; fail "hosted BootInfo unit tests did not compile"; }
"$out_dir/bootinfo-tests/bin/test_wsm_bootinfo" \
  > "$out_dir/bootinfo-tests/test.txt" 2>&1 \
  || { cat "$out_dir/bootinfo-tests/test.txt" >&2; fail "hosted BootInfo unit tests failed"; }
grep -Fxq 'WSM-BOOTINFO-TESTS-PASS: 5/5' "$out_dir/bootinfo-tests/test.txt" \
  || { cat "$out_dir/bootinfo-tests/test.txt" >&2; fail "hosted BootInfo test count/result mismatch"; }
echo "HOSTED_BOOTINFO_UNIT_TESTS=PASS: 5/5"

"$ppc" -Tlinux -O- -Xs- -CX -Cn \
  -Fu"$ROOT_DIR/src" -Fu"$out_dir" \
  -Fu"$units_dir/rtl" -Fu"$units_dir/rtl-objpas" \
  -FE"$out_dir" -FU"$out_dir" src/pascal_handoff.pas > "$out_dir/compile.txt" 2>&1 \
  || { cat "$out_dir/compile.txt" >&2; fail "Pascal handoff unit compile failed"; }

[[ -s "$out_dir/wsm.bootinfo.o" ]] || fail "reusable wsm.bootinfo object missing"
[[ -s "$out_dir/pascal_handoff.o" ]] || fail "pascal_handoff object missing"
ld -r "$out_dir/wsm.bootinfo.o" "$out_dir/pascal_handoff.o" -o "$fixture_obj" \
  || fail "could not combine the Pascal units into the handoff fixture"

run_cell() {  # $1 = cell, $2 = transcript, $3 = extra env assignment (may be empty)
  local cell="$1" transcript="$2" extra="$3"
  local img="$out_dir?${cell}.img" log="$out_dir?${cell}.log"

  # shellcheck disable=SC2086
  env WSM_OS_LINK_GC_SECTIONS=1 $extra bash scripts/build-uefi-image.sh "$fixture_obj" "$img" >/dev/null \
    || fail "image ${cell}"

  [[ -z "$(nm -u target/kernel-x86_64)" ]] || fail "undefined symbols in ${cell}"

  WSM_QEMU_TRANSCRIPT="$transcript" \
  WSM_QEMU_RAW_SERIAL_COPY="$log" \
    bash scripts/run-qemu-uefi.sh "$img" >/dev/null || fail "qemu ${cell}"

  printf 'PASS %-11s %s\n' "$cell" \
    "$(tr -d '\r' < "$log" | grep '^WSM-OS ' | tail -1)"
}

run_cell valid      artifacts/nucleus-witness-pascal-handoff-fixture-qemu-serial-transcript.txt ""
run_cell missing    artifacts/nucleus-witness-pascal-handoff-missing-fixture-qemu-serial-transcript.txt \
  "WSM_FORCE_NO_BOOT_INFO=1"
run_cell badtag     artifacts/nucleus-witness-pascal-handoff-badtag-fixture-qemu-serial-transcript.txt \
  "WSM_FORCE_BAD_BOOT_INFO_TAG=1"
run_cell zerooffset artifacts/nucleus-witness-pascal-handoff-zerooffset-fixture-qemu-serial-transcript.txt \
  "WSM_FORCE_ZERO_BOOT_INFO_OFFSET=1"

echo "PASCAL-HANDOFF-PASS: 4/4 - reusable wsm.bootinfo unit agrees with ASM and fails closed on malformed records"
