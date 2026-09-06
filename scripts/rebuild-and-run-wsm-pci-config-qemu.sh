#!/usr/bin/env bash
set -euo pipefail

# Resolve OVMF via explicit environment first, then Guix discovery
source "$(dirname "$0")/ovmf-env.sh"

run_fixture() {
  local fixture=$1
  local image="target/wsm-os-${fixture}-uefi.img"

  WSM_FIXTURE="$fixture" cargo run -p m4-generator
  if [[ "$fixture" == *-bounds-fixture ]]; then
    set +e
    WSM_FIXTURE="$fixture" cargo run -p wsm-os-hosted
    hosted_status=$?
    set -e
    [[ "$hosted_status" -eq 4 ]]
  else
    WSM_FIXTURE="$fixture" cargo run -p wsm-os-hosted
  fi
  WSM_FIXTURE="$fixture" cargo build -p wsm-os-kernel --target x86_64-unknown-none
  cargo run -p wsm-os-image -- \
    target/x86_64-unknown-none/debug/wsm-os-kernel \
    "$image"

  WSM_QEMU_DATA_DISK="$data_disk" \
  WSM_QEMU_VIRTIO_ADDR=5 \
  WSM_QEMU_VIRTIO_DISABLE_LEGACY=1 \
  WSM_QEMU_TRANSCRIPT="artifacts/${fixture}-qemu-serial-transcript.txt" \
    "$(dirname "$0")/run-qemu-uefi.sh" "$image"
}

run_dir=$(mktemp -d)
trap 'rm -rf "$run_dir"' EXIT
data_disk="$run_dir/virtio-data.raw"
truncate -s 1M "$data_disk"

run_fixture d1-pci-config-capability-fixture
run_fixture d1-pci-config-bounds-fixture
run_fixture d2-virtio-blk-status-fixture
