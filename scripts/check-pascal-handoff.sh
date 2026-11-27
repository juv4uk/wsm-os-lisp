#!/usr/bin/env bash
# ADR-006 P1 remainder: Pascal owns the handoff boundary.
#
# Four cells, one per way the bootloader record can arrive:
#   valid        tag = Some, value present   -> Pascal validates, agrees with
#                                               the asm reading, allocates
#   missing      no BootInfo pointer at all  -> ABI 0x48414E01
#   badtag       Optional tag is neither 0 nor 1 -> ABI 0x48414E02
#   zerooffset   tag = Some but value is 0   -> ABI 0x48414E03
#
# The three negatives are injected by test-only `as --defsym` mutations in
# src/entry.s and are never present in a production build.
#
# Fail closed on: compiler drift, any undefined symbol in the final kernel,
# transcript mismatch.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

out_dir="${WSM_HANDOFF_OUT_DIR:-target/pascal-handoff}"
expected_version="${WSM_FPC_VERSION:-3.2.2}"

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
[[ "$("$ppc" -iV | tr -d '\r')" == "$expected_version" ]] \
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
mkdir -p "$out_dir"

"$ppc" -Tlinux -O- -Xs- -CX -Cn \
  -Fu"$units_dir/rtl" -Fu"$units_dir/rtl-objpas" \
  -FE"$out_dir" -FU"$out_dir" src/pascal_handoff.pas >/dev/null \
  || fail "FPC compile failed"



run_cell() {  # $1 = cell, $2 = transcript, $3 = extra env assignment (may be empty)
  local cell="$1" transcript="$2" extra="$3"
  local img="$out_dir/${cell}.img" log="$out_dir/${cell}.log"

  # shellcheck disable=SC2086
  env WSM_OS_LINK_GC_SECTIONS=1 $extra bash scripts/build-uefi-image.sh "$out_dir/pascal_handoff.o" "$img" >/dev/null \
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

echo "PASCAL-HANDOFF-PASS: 4/4 - Pascal reads BootInfo, agrees with asm, and fails closed on missing or malformed records"
