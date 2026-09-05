#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <uefi-image>" >&2
  exit 2
fi

image=$1
: "${QEMU_SYSTEM_X86_64:=qemu-system-x86_64}"
: "${WSM_OS_QEMU_TIMEOUT:=20}"

# Resolve OVMF via explicit environment first, then Guix discovery
source "$(dirname "$0")/ovmf-env.sh"

for required in "$image" "$OVMF_CODE" "$OVMF_VARS"; do
  if [[ ! -s "$required" ]]; then
    echo "MISSING: $required" >&2
    exit 2
  fi
done
if [[ -n "${WSM_QEMU_DATA_DISK:-}" && ! -s "$WSM_QEMU_DATA_DISK" ]]; then
  echo "MISSING: $WSM_QEMU_DATA_DISK" >&2
  exit 2
fi

run_dir=$(mktemp -d)
trap 'rm -rf "$run_dir"' EXIT
serial_log="$run_dir/serial.log"
vars_copy="$run_dir/ovmf-vars.fd"
cp "$OVMF_VARS" "$vars_copy"
chmod u+w "$vars_copy"

qemu_args=(
  -machine q35 -m 128M
  -drive "if=pflash,unit=0,format=raw,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,unit=1,format=raw,file=$vars_copy"
  -drive "format=raw,file=$image"
)
if [[ -n "${WSM_QEMU_DATA_DISK:-}" ]]; then
  qemu_args+=( -drive "format=raw,file=$WSM_QEMU_DATA_DISK,if=none,id=wsm-data" )
  virtio_device="virtio-blk-pci,drive=wsm-data"
  if [[ -n "${WSM_QEMU_VIRTIO_ADDR:-}" ]]; then
    virtio_device+=",addr=${WSM_QEMU_VIRTIO_ADDR}"
  fi
  if [[ "${WSM_QEMU_VIRTIO_DISABLE_LEGACY:-0}" == 1 ]]; then
    virtio_device+=",disable-legacy=on"
  fi
  qemu_args+=( -device "$virtio_device" )
fi
qemu_args+=( -device isa-debug-exit,iobase=0xf4,iosize=0x04
  -serial "file:$serial_log" -display none -no-reboot )

set +e
timeout "$WSM_OS_QEMU_TIMEOUT" "$QEMU_SYSTEM_X86_64" "${qemu_args[@]}"
status=$?
set -e

case "$status" in
  33|37)
    transcript_file=${WSM_QEMU_TRANSCRIPT:-artifacts/qemu-serial-transcript.txt}
    expected=$(cat "$transcript_file")
    observed=$(tr -d '\r' < "$serial_log" | grep '^WSM-OS ')
    if [[ "$observed" != "$expected" ]]; then
      echo "SERIAL-MISMATCH against $transcript_file" >&2
      printf 'observed: %q\n' "$observed" >&2
      cat "$serial_log" >&2
      exit 1
    fi
    printf '%s\n' "$observed"
    ;;
  35)
    echo "PANIC: guest reported the structured panic exit" >&2
    cat "$serial_log" >&2
    exit 1
    ;;
  124)
    echo "TIMEOUT: guest did not reach a structured exit" >&2
    cat "$serial_log" >&2
    exit 1
    ;;
  *)
    echo "QEMU-FAIL: unexpected exit $status" >&2
    cat "$serial_log" >&2
    exit 1
    ;;
esac
