#!/usr/bin/env bash
set -euo pipefail

# Resolve OVMF via explicit environment first, then Guix discovery
source "$(dirname "$0")/ovmf-env.sh"

fixture=d0-virtio-identity-fixture

WSM_FIXTURE="$fixture" cargo run -p m4-generator
WSM_FIXTURE="$fixture" cargo run -p wsm-os-hosted
WSM_FIXTURE="$fixture" cargo build -p wsm-os-kernel --target x86_64-unknown-none
cargo run -p wsm-os-image -- \
  target/x86_64-unknown-none/debug/wsm-os-kernel \
  target/wsm-os-d0-virtio-identity-uefi.img

WSM_QEMU_TRANSCRIPT="artifacts/${fixture}-qemu-serial-transcript.txt" \
  exec "$(dirname "$0")/run-qemu-uefi.sh" \
  target/wsm-os-d0-virtio-identity-uefi.img
