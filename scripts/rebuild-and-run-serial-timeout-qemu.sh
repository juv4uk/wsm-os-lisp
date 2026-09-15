#!/usr/bin/env bash
set -euo pipefail

# PHYSICAL-SERIAL-GATE-1 (issue #31) negative witness: forced never-ready COM1.
#
# Builds a UEFI image whose entry comes from tests/serial-timeout-entry.s, i.e.
# the REAL src/entry.s with the single LSR read (inb in serial_putc) overridden
# to always return THRE-clear. Under QEMU the bounded poll must exhaust its
# finite bound and terminate through the distinct serial transport-failure path:
# isa-debug-exit val 0x13 -> shell exit 39. The marker it emits via its
# non-recursive direct-write path is captured on the live UART.
#
# Asserts:
#   - guest exits 39 (SERIAL-TRANSPORT-FAIL), NOT 33/37/124;
#   - serial log carries the WSM-OS SERIAL-TRANSPORT-FAIL marker;
#   - serial log carries NO normal BOOT/RESULT transcript.
# This is a transport/substrate failure, not a Lisp semantic result.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/ovmf-env.sh"

run_dir="$ROOT_DIR/target/.serial-timeout.$$"
mkdir -p "$run_dir"
trap 'rm -rf "$run_dir"' EXIT

# Assemble the real runtime + the entry harness (fake never-ready LSR).
as --64 "$ROOT_DIR/tests/serial-timeout-entry.s" -o "$run_dir/entry.o"
as --64 "$ROOT_DIR/src/runtime.s" -o "$run_dir/runtime.o"

ld -m elf_x86_64 -T "$ROOT_DIR/src/linker.ld" \
  "$run_dir/entry.o" \
  "$run_dir/runtime.o" \
  "$ROOT_DIR/artifacts/fixture.o" \
  -o "$run_dir/kernel-x86_64.elf"

# Assemble the UEFI GPT/FAT image, mirroring build-uefi-image.sh.
image="$ROOT_DIR/target/wsm-os-serial-timeout-uefi.img"
rm -f "$image"
truncate -s 8M "$image"
sgdisk -n 1:2048:14335 -t 1:ef00 -c 1:"EFI System" "$image" >/dev/null
dd if=/dev/zero of="$run_dir/part.fat" bs=512 count=12288 status=none
mkfs.vfat -F 12 "$run_dir/part.fat" >/dev/null
mmd -i "$run_dir/part.fat" ::efi ::efi/boot
mcopy -i "$run_dir/part.fat" "$ROOT_DIR/artifacts/bootx64.efi" ::efi/boot/bootx64.efi
mcopy -i "$run_dir/part.fat" "$run_dir/kernel-x86_64.elf" ::kernel-x86_64
dd if="$run_dir/part.fat" of="$image" bs=512 seek=2048 conv=notrunc status=none

serial_log="$run_dir/serial.log"
vars_copy="$run_dir/ovmf-vars.fd"
cp "$OVMF_VARS" "$vars_copy"
chmod u+w "$vars_copy"

: "${WSM_OS_QEMU_TIMEOUT:=20}"
set +e
timeout "$WSM_OS_QEMU_TIMEOUT" qemu-system-x86_64 \
  -machine q35 -m 128M \
  -drive "if=pflash,unit=0,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive "if=pflash,unit=1,format=raw,file=$vars_copy" \
  -drive "format=raw,file=$image" \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -serial "file:$serial_log" -display none -no-reboot
status=$?
set -e

lines=$(tr -d '\r' < "$serial_log" | grep '^WSM-OS ' || true)

if [[ "$status" -ne 39 ]]; then
  echo "SERIAL-TIMEOUT-FAIL(exit): expected transport-failure exit 39, got $status" >&2
  printf '%s\n' "$lines" >&2
  exit 1
fi
if ! grep -q 'WSM-OS SERIAL-TRANSPORT-FAIL' "$serial_log"; then
  echo "SERIAL-TIMEOUT-FAIL(marker): missing serial-transport-failure marker" >&2
  printf '%s\n' "$lines" >&2
  exit 1
fi
if grep -q 'WSM-OS BOOT\|WSM-OS RESULT' "$serial_log"; then
  echo "SERIAL-TIMEOUT-FAIL(transcript): normal BOOT/RESULT emitted despite dead transport" >&2
  printf '%s\n' "$lines" >&2
  exit 1
fi

echo "SERIAL-TIMEOUT-PASS: never-ready COM1 terminated as transport failure (exit 39)"
printf 'WSM-OS SERIAL-TRANSPORT-FAIL schema=1 status=error\n'