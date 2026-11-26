#!/usr/bin/env bash
# GC safepoint capture gate (#71, GC-ENTRY-CAPTURE-1).
#
# Proves that every allocator captures its entry state before clobbering the
# certified registers, and classifies it against a registered root map keyed by
# (final_pc, allocator_kind). No collector runs here.
#
#   certified     cons site and closure site both classify CERTIFIED
#   absent        no map registered -> NOT-A-SAFEPOINT, allocation unchanged
#   kind-mismatch map names the site but the wrong allocator kind -> ABI
#   closure-rsi   closure record claims %rsi as a root -> ABI
#
# Scope: MECHANISM evidence. No mark, no sweep, no free list, no semantic
# authority. Fixtures are hand-written target assembly.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

out_dir="${WSM_GC_SAFEPOINT_OUT_DIR:-target/gc-safepoint-capture}"

fail() {
  printf 'GC-SAFEPOINT-CAPTURE-FAIL: %s\n' "$1" >&2
  exit 1
}

rm -rf "$out_dir"
mkdir -p "$out_dir"

for name in certified absent kind-mismatch closure-rsi; do
  fixture="artifacts/nucleus-witness-gc-safepoint-${name}-fixture"
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

echo "GC-SAFEPOINT-CAPTURE-PASS: 4/4 witnesses (certified, absent, kind-mismatch, closure-rsi)"
