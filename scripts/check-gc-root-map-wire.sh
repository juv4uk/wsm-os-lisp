#!/usr/bin/env bash
# GC root-map wire consumption gate (#64, GC-ROOT-MAP-CONSUME-1).
#
# Proves that the allocator can consume a CML_GC_ROOT_MAP_V1 record at the real
# call boundary, with label -> final_pc resolution and fail-closed validation
# performed before any allocation can consult the map.
#
#   certified      two sites certified; register roots and one stack root
#   empty          explicit empty certificate, distinct from NOT-A-SAFEPOINT
#   unknown-label  wire label with no binding row -> ABI 0x47430005
#   bad-stack      stack offset outside the certified frame -> ABI 0x47430004
#   dup-label      two binding rows for one label -> ABI 0x47430003
#
# No collector runs: no mark, no sweep, no free list, no stack scan.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

out_dir="${WSM_GC_WIRE_OUT_DIR:-target/gc-root-map-wire}"

fail() {
  printf 'GC-ROOT-MAP-WIRE-FAIL: %s\n' "$1" >&2
  exit 1
}

rm -rf "$out_dir"
mkdir -p "$out_dir"

for name in certified empty unknown-label bad-stack dup-label; do
  fixture="artifacts/nucleus-witness-gc-wire-${name}-fixture"
  transcript="${fixture}-qemu-serial-transcript.txt"

  [[ -s "${fixture}.s" ]] || fail "missing ${fixture}.s"
  [[ -s "$transcript" ]] || fail "missing $transcript"

  as --64 "${fixture}.s" -o "${out_dir}/${name}.o" \
    || fail "assemble ${name}"

  bash scripts/build-uefi-image.sh "${out_dir}/${name}.o" "${out_dir}/${name}.img" \
    >/dev/null || fail "image ${name}"

  WSM_QEMU_TRANSCRIPT="$transcript" \
  WSM_QEMU_RAW_SERIAL_COPY="${out_dir}/${name}-serial.log" \
    bash scripts/run-qemu-uefi.sh "${out_dir}/${name}.img" >/dev/null \
    || fail "qemu ${name}"

  printf 'PASS %-14s %s\n' "$name" \
    "$(tr -d '\r' < "${out_dir}/${name}-serial.log" | grep '^WSM-OS ' | tail -1)"
done

echo "GC-ROOT-MAP-WIRE-PASS: 5/5 witnesses (certified, empty, unknown-label, bad-stack, dup-label)"
