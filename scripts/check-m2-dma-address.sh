#!/usr/bin/env bash
set -euo pipefail

# M2 / #84: bounded guest virtual -> physical DMA-address witness.
#
# This deliberately proves only the address/mapping prerequisite for #82.
# It does not configure a virtqueue and it does not expose raw DMA addresses
# as SENS/WSM values or as CML runtime imports.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/wsm-m2-dma.XXXXXX)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$ROOT_DIR/target/m2-dma-address"

as --64 "$ROOT_DIR/artifacts/m2-dma-address-probe.s" -o "$work/probe.o"

cat >"$work/positive.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=1 status=ok
EOF

bash "$ROOT_DIR/scripts/build-uefi-image.sh"   "$work/probe.o" "$work/positive.img" >/dev/null

positive="$(
  WSM_QEMU_TRANSCRIPT="$work/positive.expected"   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/positive.img"
)"
printf '%s\n' "$positive" >"$ROOT_DIR/target/m2-dma-address/positive-transcript.txt"

cat >"$work/no-map.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=0 status=ok
EOF

WSM_OS_FORCE_NO_PHYS_MAP=1   bash "$ROOT_DIR/scripts/build-uefi-image.sh"     "$work/probe.o" "$work/no-map.img" >/dev/null

negative="$(
  WSM_QEMU_TRANSCRIPT="$work/no-map.expected"   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/no-map.img"
)"
printf '%s\n' "$negative" >"$ROOT_DIR/target/m2-dma-address/no-phys-map-transcript.txt"

runtime_sha="$(sha256sum "$ROOT_DIR/src/runtime.s" | awk '{print $1}')"
cat >"$ROOT_DIR/target/m2-dma-address/witness.json" <<EOF
{
  "schema": "wsm-os-m2-dma-address/v1",
  "issue": 84,
  "status": "PASS",
  "arena_bytes": 4096,
  "required_alignment": 4096,
  "mapping_source": "active-x86_64-page-tables-via-cr3-and-boot-physical-memory-direct-map",
  "positive_guest_observation": 1,
  "negative_no_phys_map_observation": 0,
  "raw_address_scope": "target-mechanism-only-not-language-observer",
  "runtime_source_sha256": "$runtime_sha"
}
EOF

echo "M2-DMA-ADDRESS: PASS"
echo "positive=proved-nonzero-aligned-contiguous-page negative=no-phys-map-fails-closed"
