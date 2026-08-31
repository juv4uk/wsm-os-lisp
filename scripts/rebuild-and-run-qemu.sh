#!/usr/bin/env bash
set -euo pipefail

# Always rebuild the kernel and UEFI image before a local witness. Running an
# older target/wsm-os-uefi.img can produce a serial transcript from a previous
# ABI/runtime revision.

if [[ -z "${OVMF_CODE:-}" || -z "${OVMF_VARS:-}" ]]; then
  echo "usage: OVMF_CODE=/path/code.fd OVMF_VARS=/path/vars.fd $0" >&2
  exit 2
fi

cargo build -p wsm-os-kernel --target x86_64-unknown-none
cargo run -p wsm-os-image -- \
  target/x86_64-unknown-none/debug/wsm-os-kernel \
  target/wsm-os-uefi.img

exec "$(dirname "$0")/run-qemu-uefi.sh" target/wsm-os-uefi.img
