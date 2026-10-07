#!/usr/bin/env bash
set -euo pipefail

# M2 / #84: bounded guest virtual -> physical DMA-address witness.
#
# Production semantics observe only the boolean-shaped target probe result.
# Exact raw virtual/physical addresses are emitted only by a test-only
# WSM-M2 serial record and captured as mechanism evidence.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/wsm-m2-dma.XXXXXX)"
trap 'rm -rf "$work"' EXIT
out="$ROOT_DIR/target/m2-dma-address"
mkdir -p "$out"

as --64 "$ROOT_DIR/artifacts/m2-dma-address-probe.s" -o "$work/probe.o"

cat >"$work/positive.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=1 status=ok
EOF
cat >"$work/negative.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=0 status=ok
EOF

# Positive: real active page tables must prove one nonzero aligned contiguous
# physical page. Test-only serial evidence records exact addresses separately
# from the WSM-OS semantic result line.
WSM_DMA_EVIDENCE_SERIAL=1   bash "$ROOT_DIR/scripts/build-uefi-image.sh"     "$work/probe.o" "$work/positive.img" >/dev/null

positive="$(
  WSM_QEMU_TRANSCRIPT="$work/positive.expected"   WSM_QEMU_RAW_SERIAL_COPY="$out/positive-raw-serial.txt"   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/positive.img"
)"
printf '%s\n' "$positive" >"$out/positive-transcript.txt"

run_negative() {
  local name=$1
  local flag=$2
  local image="$work/$name.img"

  env "$flag=1" bash "$ROOT_DIR/scripts/build-uefi-image.sh"     "$work/probe.o" "$image" >/dev/null

  local observed
  observed="$(
    WSM_QEMU_TRANSCRIPT="$work/negative.expected"     bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$image"
  )"
  printf '%s\n' "$observed" >"$out/$name-transcript.txt"
}

# Independent fail-closed mutations.
run_negative no-phys-map WSM_OS_FORCE_NO_PHYS_MAP
run_negative translation-fail WSM_FORCE_DMA_TRANSLATION_FAIL
run_negative misaligned-arena WSM_FORCE_DMA_MISALIGN
run_negative zero-physical WSM_FORCE_DMA_ZERO_PHYS
run_negative noncontiguous-page WSM_FORCE_DMA_NONCONTIGUOUS

runtime_sha="$(sha256sum "$ROOT_DIR/src/runtime.s" | awk '{print $1}')"
dma_line="$(tr -d '\r' <"$out/positive-raw-serial.txt" | grep '^WSM-M2 DMA ' | tail -n1)"

python3 - "$dma_line" "$out/witness.json" "$runtime_sha" <<'PY'
import json
import re
import sys

line, output, runtime_sha = sys.argv[1:]
m = re.fullmatch(
    r"WSM-M2 DMA schema=1 virtual=(\d+) physical=(\d+) "
    r"length=4096 pages=1 status=(\d+)",
    line,
)
if not m:
    raise SystemExit(f"invalid DMA evidence line: {line!r}")

virt, phys, status = map(int, m.groups())
if status != 1:
    raise SystemExit(f"DMA arena was not proved: status={status}")
if virt % 4096 != 0:
    raise SystemExit(f"virtual arena is not 4096-aligned: {virt}")
if phys == 0 or phys % 4096 != 0:
    raise SystemExit(f"physical arena is zero/misaligned: {phys}")

# With a u64 4096-aligned start, adding 4095 cannot overflow: the greatest
# possible aligned start is 2^64-4096, whose inclusive end is 2^64-1.
u64_max = (1 << 64) - 1
assert ((1 << 64) - 4096) + 4095 == u64_max

record = {
    "schema": "wsm-os-m2-dma-address/v2",
    "issue": 84,
    "status": "PASS",
    "arena_virtual_start": str(virt),
    "arena_virtual_end": str(virt + 4095),
    "arena_physical_start": str(phys),
    "arena_physical_end": str(phys + 4095),
    "arena_length": 4096,
    "page_count": 1,
    "required_alignment": 4096,
    "mapping_source": "active-x86_64-page-tables-via-cr3-and-boot-physical-memory-direct-map",
    "raw_address_scope": "test-only-target-mechanism-evidence",
    "semantic_observer_exposes_raw_address": False,
    "negative_controls": {
        "no_physical_map": "PASS",
        "forced_translation_failure": "PASS",
        "forced_misalignment": "PASS",
        "forced_zero_physical": "PASS",
        "forced_noncontiguous_end": "PASS",
        "partial_page_crossing": "eliminated-by-p2align12-and-exact-4096-byte-arena",
        "u64_start_plus_4095_overflow": "eliminated-by-4096-alignment-invariant",
    },
    "runtime_source_sha256": runtime_sha,
}
with open(output, "w", encoding="utf-8") as fh:
    json.dump(record, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

echo "M2-DMA-ADDRESS-V2: PASS"
echo "positive=exact-address-recorded negatives=no-map,translation,misalign,zero-phys,noncontiguous"
