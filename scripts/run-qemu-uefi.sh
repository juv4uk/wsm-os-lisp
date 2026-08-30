#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <uefi-image>" >&2
  exit 2
fi

image=$1
: "${QEMU_SYSTEM_X86_64:=qemu-system-x86_64}"
: "${OVMF_CODE:?set OVMF_CODE to the read-only OVMF code image}"
: "${OVMF_VARS:?set OVMF_VARS to the OVMF variable template}"
: "${WSM_OS_QEMU_TIMEOUT:=20}"

for required in "$image" "$OVMF_CODE" "$OVMF_VARS"; do
  if [[ ! -s "$required" ]]; then
    echo "MISSING: $required" >&2
    exit 2
  fi
done

run_dir=$(mktemp -d)
trap 'rm -rf "$run_dir"' EXIT
serial_log="$run_dir/serial.log"
vars_copy="$run_dir/ovmf-vars.fd"
cp "$OVMF_VARS" "$vars_copy"
chmod u+w "$vars_copy"

set +e
timeout "$WSM_OS_QEMU_TIMEOUT" "$QEMU_SYSTEM_X86_64" \
  -machine q35 \
  -m 128M \
  -drive "if=pflash,unit=0,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive "if=pflash,unit=1,format=raw,file=$vars_copy" \
  -drive "format=raw,file=$image" \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -serial "file:$serial_log" \
  -display none \
  -no-reboot
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
