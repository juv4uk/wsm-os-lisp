#!/usr/bin/env bash
set -euo pipefail

# #82 real data-I/O vertical:
# fresh IN sector0 -> OUT deterministic 512B -> FLUSH -> IN sector0.
# The guest validates request status/completion and final bytes. The host then
# hashes the raw sector to prove bytes crossed the device boundary.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/wsm-m2-sector.XXXXXX)"
trap 'rm -rf "$work"' EXIT
out="$ROOT_DIR/target/m2-sector-roundtrip"
mkdir -p "$out"

as --64 "$ROOT_DIR/artifacts/m2-sector-roundtrip-probe.s" -o "$work/probe.o"
bash "$ROOT_DIR/scripts/build-uefi-image.sh"   "$work/probe.o" "$work/sector.img" >/dev/null

cat >"$work/positive.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=1 status=ok
EOF
cat >"$work/negative.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=0 status=ok
EOF

truncate -s 1M "$work/data.raw"
initial_sha="$(dd if="$work/data.raw" bs=512 count=1 status=none | sha256sum | awk '{print $1}')"

positive="$(
  WSM_QEMU_TRANSCRIPT="$work/positive.expected"   WSM_QEMU_DATA_DISK="$work/data.raw"   WSM_QEMU_VIRTIO_ADDR=5   WSM_QEMU_VIRTIO_DISABLE_LEGACY=1   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/sector.img"
)"
printf '%s\n' "$positive" >"$out/positive-transcript.txt"

expected_sha="$(
python3 - <<'PY'
import hashlib
payload = b"SENSM2V1" * 64
assert len(payload) == 512
print(hashlib.sha256(payload).hexdigest())
PY
)"
actual_sha="$(dd if="$work/data.raw" bs=512 count=1 status=none | sha256sum | awk '{print $1}')"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "sector0 host digest mismatch expected=$expected_sha actual=$actual_sha" >&2
  exit 1
fi

# Device-absence control: no block device => bounded fail-closed probe result.
negative="$(
  WSM_QEMU_TRANSCRIPT="$work/negative.expected"   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/sector.img"
)"
printf '%s\n' "$negative" >"$out/no-device-transcript.txt"

runtime_sha="$(sha256sum "$ROOT_DIR/src/runtime.s" | awk '{print $1}')"
cat >"$out/witness.json" <<EOF
{
  "schema": "wsm-os-m2-sector-roundtrip/v1",
  "issue": 82,
  "status": "PASS",
  "transport": "virtio-pci-modern-split-ring",
  "queue_index": 0,
  "queue_size": 8,
  "sector": 0,
  "sector_bytes": 512,
  "sequence": ["IN-zero", "OUT-pattern", "FLUSH", "IN-pattern"],
  "completed_requests": 4,
  "completion_wait": "bounded-used-index-poll",
  "request_status_required": "VIRTIO_BLK_S_OK",
  "flush_required": true,
  "initial_sector_sha256": "$initial_sha",
  "expected_payload_sha256": "$expected_sha",
  "final_sector_sha256": "$actual_sha",
  "payload": "ASCII-SENSM2V1-repeated-64",
  "same_boot_read_after_write": "PASS",
  "host_raw_sector_digest": "PASS",
  "negative_no_device": "PASS",
  "runtime_source_sha256": "$runtime_sha"
}
EOF

echo "M2-SECTOR-ROUNDTRIP: PASS"
echo "requests=4 sequence=IN-zero,OUT,FLUSH,IN-pattern sha256=$actual_sha"
