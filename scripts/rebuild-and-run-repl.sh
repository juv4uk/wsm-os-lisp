#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${OVMF_CODE:-}" || -z "${OVMF_VARS:-}" ]]; then
  echo "usage: OVMF_CODE=/path/code.fd OVMF_VARS=/path/vars.fd $0" >&2
  exit 2
fi

WSM_FIXTURE=repl-fixture cargo build -p wsm-os-kernel --target x86_64-unknown-none
cargo run -p wsm-os-image -- \
  target/x86_64-unknown-none/debug/wsm-os-kernel \
  target/wsm-os-repl-uefi.img

exec "$(dirname "$0")/run-qemu-interactive.sh" target/wsm-os-repl-uefi.img
