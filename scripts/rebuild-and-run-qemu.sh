#!/usr/bin/env bash
set -euo pipefail

# Always rebuild the kernel and UEFI image before a local witness. Running an
# older target/wsm-os-uefi.img can produce a serial transcript from a previous
# ABI/runtime revision.

# Resolve OVMF via explicit environment first, then Guix discovery
source "$(dirname "$0")/ovmf-env.sh"

"$(dirname "$0")/build-uefi-image.sh" artifacts/fixture.o target/wsm-os-uefi.img

exec "$(dirname "$0")/run-qemu-uefi.sh" target/wsm-os-uefi.img
