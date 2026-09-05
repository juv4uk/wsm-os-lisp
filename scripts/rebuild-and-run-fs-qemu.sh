#!/usr/bin/env bash
set -euo pipefail

# Resolve OVMF via explicit environment first, then Guix discovery
source "$(dirname "$0")/ovmf-env.sh"

WSM_FIXTURE=fs-fixture cargo build -p wsm-os-kernel --target x86_64-unknown-none
cargo run -p wsm-os-image -- \
  target/x86_64-unknown-none/debug/wsm-os-kernel \
  target/wsm-os-fs-uefi.img

WSM_QEMU_TRANSCRIPT=artifacts/fs-qemu-serial-transcript.txt \
  exec "$(dirname "$0")/run-qemu-uefi.sh" target/wsm-os-fs-uefi.img
