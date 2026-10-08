#!/usr/bin/env bash
set -euo pipefail

# #82 fail-closed matrix for the real virtio-blk data path.
# Every mutation uses the same production roundtrip probe and must return
# target fixnum 0 without changing sector 0 on the disposable raw disk.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/wsm-m2-falsifiers.XXXXXX)"
trap 'rm -rf "$work"' EXIT
out="$ROOT_DIR/target/m2-block-falsifiers"
mkdir -p "$out"

as --64 "$ROOT_DIR/artifacts/m2-sector-roundtrip-probe.s" -o "$work/probe.o"

cat >"$work/negative.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=0 status=ok
EOF

zero_sha="$(
python3 - <<'PY'
import hashlib
print(hashlib.sha256(bytes(512)).hexdigest())
PY
)"

run_case() {
  local name=$1
  local flag=$2
  local image="$work/$name.img"
  local disk="$work/$name.raw"

  env "$flag=1" bash "$ROOT_DIR/scripts/build-uefi-image.sh"     "$work/probe.o" "$image" >/dev/null
  truncate -s 1M "$disk"

  local observed
  observed="$(
    WSM_QEMU_TRANSCRIPT="$work/negative.expected"     WSM_QEMU_DATA_DISK="$disk"     WSM_QEMU_VIRTIO_ADDR=5     WSM_QEMU_VIRTIO_DISABLE_LEGACY=1     bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$image"
  )"
  printf '%s\n' "$observed" >"$out/$name-transcript.txt"

  local sector_sha
  sector_sha="$(dd if="$disk" bs=512 count=1 status=none | sha256sum | awk '{print $1}')"
  if [[ "$sector_sha" != "$zero_sha" ]]; then
    echo "$name changed sector0 while expected fail-closed: $sector_sha" >&2
    exit 1
  fi
}

run_case queue-unsupported WSM_FORCE_VIRTIO_QUEUE_UNSUPPORTED
run_case bad-geometry WSM_FORCE_VIRTIO_BAD_GEOMETRY
run_case flush-unsupported WSM_FORCE_VIRTIO_NO_FLUSH
run_case completion-timeout WSM_FORCE_VIRTIO_TIMEOUT
run_case nonzero-status WSM_FORCE_VIRTIO_BAD_STATUS

runtime_sha="$(sha256sum "$ROOT_DIR/src/runtime.s" | awk '{print $1}')"
cat >"$out/witness.json" <<EOF
{
  "schema": "wsm-os-m2-block-falsifiers/v1",
  "issue": 82,
  "status": "PASS",
  "dynamic_negative_controls": {
    "queue_size_unsupported": "PASS",
    "invalid_queue_geometry": "PASS",
    "unsupported_flush": "PASS",
    "bounded_completion_timeout": "PASS",
    "nonzero_virtio_status": "PASS"
  },
  "construction_guards": {
    "dma_translation_unavailable": "proved-by-issue-84",
    "descriptor_ring_address_overflow": "eliminated-by-proved-4096-byte-contiguous-dma-page-and-in-page-offsets",
    "sector_out_of_admitted_bound": "eliminated-by-closed-sector0-only-request-constructor"
  },
  "failed_cases_leave_sector0_zero": true,
  "runtime_source_sha256": "$runtime_sha"
}
EOF

echo "M2-BLOCK-FALSIFIERS: PASS"
echo "queue,geometry,flush,timeout,status all fail closed; sector0 unchanged"
