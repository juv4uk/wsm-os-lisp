#!/usr/bin/env bash
set -euo pipefail

# #82 first transport slice: prove modern VirtIO PCI notify mapping and one
# enabled split-ring queue0 over the #84 DMA arena. No block request is sent.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/wsm-m2-vq.XXXXXX)"
trap 'rm -rf "$work"' EXIT
out="$ROOT_DIR/target/m2-virtqueue-setup"
mkdir -p "$out"

as --64 "$ROOT_DIR/artifacts/m2-virtqueue-setup-probe.s" -o "$work/probe.o"

cat >"$work/positive.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=1 status=ok
EOF
cat >"$work/negative.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=0 status=ok
EOF

bash "$ROOT_DIR/scripts/build-uefi-image.sh"   "$work/probe.o" "$work/queue.img" >/dev/null

# Positive: explicit modern-only virtio-blk and a separate disposable disk.
truncate -s 1M "$work/virtio-data.raw"
positive="$(
  WSM_QEMU_TRANSCRIPT="$work/positive.expected"   WSM_QEMU_DATA_DISK="$work/virtio-data.raw"   WSM_QEMU_VIRTIO_ADDR=5   WSM_QEMU_VIRTIO_DISABLE_LEGACY=1   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/queue.img"
)"
printf '%s\n' "$positive" >"$out/positive-transcript.txt"

# Negative: same kernel without a virtio-blk device must fail closed.
negative="$(
  WSM_QEMU_TRANSCRIPT="$work/negative.expected"   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/queue.img"
)"
printf '%s\n' "$negative" >"$out/no-device-transcript.txt"

runtime_sha="$(sha256sum "$ROOT_DIR/src/runtime.s" | awk '{print $1}')"
cat >"$out/witness.json" <<EOF
{
  "schema": "wsm-os-m2-virtqueue-setup/v1",
  "issue": 82,
  "status": "PASS",
  "transport": "virtio-pci-modern",
  "queue_index": 0,
  "queue_size": 8,
  "ring": "split",
  "dma_arena_bytes": 4096,
  "descriptor_offset": 0,
  "avail_offset": 128,
  "used_offset": 148,
  "notify_mapping": "bounded-VIRTIO_PCI_CAP_NOTIFY_CFG",
  "feature_policy": "VERSION_1-required; FLUSH-if-offered; no-packed/no-event-idx/no-notification-data",
  "positive_device_observation": 1,
  "negative_no_device_observation": 0,
  "block_request_submitted": false,
  "runtime_source_sha256": "$runtime_sha"
}
EOF

echo "M2-VIRTQUEUE-SETUP: PASS"
echo "queue0=size8 enabled notify=bounded no-device=fail-closed request-submitted=false"
