#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <uefi-image>" >&2
  exit 2
fi
: "${OVMF_CODE:?set OVMF_CODE}"
: "${OVMF_VARS:?set OVMF_VARS}"
: "${QEMU_SYSTEM_X86_64:=qemu-system-x86_64}"
: "${WSM_OS_QEMU_TIMEOUT:=300}"

image=$1
[[ -s "$image" && -s "$OVMF_CODE" && -s "$OVMF_VARS" ]] || {
  echo "missing image or OVMF firmware" >&2
  exit 2
}

vars_copy=$(mktemp /tmp/wsm-ovmf-vars.XXXXXX)
trap 'rm -f "$vars_copy"' EXIT
cp "$OVMF_VARS" "$vars_copy"
chmod 600 "$vars_copy"

echo "WSM-OS interactive serial console; type input only after REPL prompt"
timeout "$WSM_OS_QEMU_TIMEOUT" "$QEMU_SYSTEM_X86_64" \
  -machine q35 -m 128M \
  -drive "if=pflash,unit=0,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive "if=pflash,unit=1,format=raw,file=$vars_copy" \
  -drive "format=raw,file=$image" \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -chardev stdio,id=wsm-serial,mux=off,signal=off \
  -serial chardev:wsm-serial -nographic -no-reboot
