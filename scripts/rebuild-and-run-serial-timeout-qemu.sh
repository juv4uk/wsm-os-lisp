#!/usr/bin/env bash
set -euo pipefail

# Real current assembly, fault-injected COM1 LSR: forced THRE=0.
# Port becomes never-ready; termination must be the *transport* exit (39),
# not a normal Lisp result (33/37), panic (35), or QEMU deadline (124).
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source scripts/ovmf-env.sh

test -s artifacts/fixture.o
test -s artifacts/bootx64.efi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

as --64 tests/serial-timeout-entry.s -o "$WORK_DIR/entry.o"
as --64 src/runtime.s -o "$WORK_DIR/runtime.o"
ld -m elf_x86_64 -T src/linker.ld \
  "$WORK_DIR/entry.o" \
  "$WORK_DIR/runtime.o" \
  artifacts/fixture.o \
  -o "$WORK_DIR/kernel-x86_64.elf"

IMAGE="$WORK_DIR/never-ready-serial.img"
truncate -s 8M "$IMAGE"
sgdisk -n 1:2048:14335 -t 1:ef00 -c 1:"EFI System" "$IMAGE" >/dev/null
dd if=/dev/zero of="$WORK_DIR/part.fat" bs=512 count=12288 status=none
mkfs.vfat -F 12 "$WORK_DIR/part.fat" >/dev/null
mmd -i "$WORK_DIR/part.fat" ::EFI ::EFI/BOOT
mcopy -i "$WORK_DIR/part.fat" artifacts/bootx64.efi ::EFI/BOOT/BOOTX64.EFI
mcopy -i "$WORK_DIR/part.fat" "$WORK_DIR/kernel-x86_64.elf" ::kernel-x86_64
dd if="$WORK_DIR/part.fat" of="$IMAGE" bs=512 seek=2048 conv=notrunc status=none

cp "$OVMF_VARS" "$WORK_DIR/vars.fd"
chmod u+w "$WORK_DIR/vars.fd"
SERIAL_LOG="$WORK_DIR/serial.log"
: "${WSM_OS_QEMU_TIMEOUT:=30}"
set +e
timeout "$WSM_OS_QEMU_TIMEOUT" qemu-system-x86_64 \
  -machine q35 -m 128M \
  -drive "if=pflash,unit=0,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive "if=pflash,unit=1,format=raw,file=$WORK_DIR/vars.fd" \
  -drive "format=raw,file=$IMAGE" \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -serial "file:$SERIAL_LOG" -display none -no-reboot
status=$?
set -e

if [[ "$status" != 39 ]]; then
  echo "SERIAL-TIMEOUT: FAIL, expected distinct transport exit 39, observed $status" >&2
  [[ ! -f "$SERIAL_LOG" ]] || cat "$SERIAL_LOG" >&2
  exit 1
fi
if [[ -f "$SERIAL_LOG" ]] && grep -Eq '^WSM-OS (BOOT|RESULT)' "$SERIAL_LOG"; then
  echo "SERIAL-TIMEOUT: FAIL, normal transcript despite never-ready COM1" >&2
  cat "$SERIAL_LOG" >&2
  exit 1
fi

echo "SERIAL-TIMEOUT: PASS, never-ready COM1 QEMU returns transport exit 39"
