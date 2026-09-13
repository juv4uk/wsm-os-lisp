#!/usr/bin/env bash
# Fail-closed witness for PHYS-MAP: when the bootloader does not provide the
# requested dynamic physical-memory mapping, the MMIO path must reject the
# access BEFORE any volatile access, instead of assuming identity mapping
# (offset zero is not proof of a mapping being present).
#
# Builds the d2 MMIO fixture kernel with WSM_OS_FORCE_NO_PHYS_MAP=1, runs it
# under bounded QEMU, and asserts that:
#   - the guest exits through the structured failure path (0x12 -> 37);
#   - the serial log carries a substrate mapping-unavailable condition
#     (source = MMIO_ERR_MAPPING_UNAVAILABLE_WRITE, 0x4D494F08 = 1296649992);
#   - the successful mmio-status witness is NOT emitted (no volatile access).
set -euo pipefail

fixture="d2-virtio-blk-status-fixture"
artifact="artifacts/${fixture}-fail-closed-phys-map-transcript.txt"

# Substrate MMIO mapping error codes (crates/wsm-os-kernel/src/main.rs):
#   MMIO_ERR_MAPPING_UNAVAILABLE_READ  = 0x4D49_4F07 = 1296649991
#   MMIO_ERR_MAPPING_UNAVAILABLE_WRITE = 0x4D49_4F08 = 1296649992

source "$(dirname "$0")/ovmf-env.sh"

image="target/wsm-os-${fixture}-no-phys-map-uefi.img"

run_dir=$(mktemp -d)
trap 'rm -rf "$run_dir"' EXIT
data_disk="$run_dir/virtio-data.raw"
truncate -s 1M "$data_disk"

WSM_FIXTURE="$fixture" cargo run -p m4-generator
WSM_OS_FORCE_NO_PHYS_MAP=1 WSM_FIXTURE="$fixture" \
  cargo build -p wsm-os-kernel --target x86_64-unknown-none
cargo run -p wsm-os-image -- \
  target/x86_64-unknown-none/debug/wsm-os-kernel \
  "$image"

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
  -drive "format=raw,file=$data_disk,if=none,id=wsm-data" \
  -device "virtio-blk-pci,drive=wsm-data,addr=5,disable-legacy=on" \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -serial "file:$serial_log" -display none -no-reboot
status=$?
set -e

observed=$(tr -d '\r' < "$serial_log" | grep '^WSM-OS ' || true)

print_transcript() {
  printf '%s\n' "$observed"
  if [[ -n "${WSM_OS_KEEP_ARTIFACT:-}" ]]; then
    cp "$serial_log" "$artifact"
    echo "artifact: $artifact" >&2
  fi
}

if [[ "$status" -ne 37 ]]; then
  echo "PHYS-MAP-FAIL(exit): expected structured failure 37, got $status" >&2
  print_transcript >&2
  exit 1
fi
if ! grep -q 'CONDITION schema=1 kind=ABI source=1296649992' "$serial_log"; then
  echo "PHYS-MAP-FAIL(condition): missing mapping-unavailable condition" >&2
  print_transcript >&2
  exit 1
fi
if grep -q 'stage=mmio-status value=t' "$serial_log"; then
  echo "PHYS-MAP-FAIL(volatile): MMIO volatile access executed despite missing mapping" >&2
  print_transcript >&2
  exit 1
fi

printf 'PHYS-MAP-PASS: MMIO path rejected missing physical-memory mapping before volatile access\n'
print_transcript