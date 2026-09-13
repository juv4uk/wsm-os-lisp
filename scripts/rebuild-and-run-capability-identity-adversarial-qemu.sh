#!/usr/bin/env bash
# Capability-identity adversarial witness (d3): a hostile WSM gains a genuine,
# substrate-issued PCI-config capability, then attempts to use that same
# capability word as an MMIO capability on the virtio-blk common-cfg region.
#
# A capability is an opaque substrate-issued token: its decoded class is part
# of its identity. Cross-class reuse must fail closed before any volatile
# MMIO access, even though the descriptor itself is globally well-formed.
# Expected: structured CONDITION (ABI, source = MMIO wrong-capability write
# error 0x4D494F05 = 1296649989) and qemu exit 0x12 -> shell 37.
set -euo pipefail

fixture="d3-mmio-identity-violation-adversarial-fixture"
artifact="artifacts/${fixture}-qemu-serial-transcript.txt"

source "$(dirname "$0")/ovmf-env.sh"

image="target/wsm-os-${fixture}-uefi.img"

run_dir=$(mktemp -d)
trap 'rm -rf "$run_dir"' EXIT
data_disk="$run_dir/virtio-data.raw"
truncate -s 1M "$data_disk"

WSM_FIXTURE="$fixture" cargo run -p m4-generator
WSM_FIXTURE="$fixture" cargo build -p wsm-os-kernel --target x86_64-unknown-none
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

if [[ "$status" -ne 37 ]]; then
  echo "CAPABILITY-ID-FAIL(exit): expected structured failure 37, got $status" >&2
  printf '%s\n' "$observed" >&2
  exit 1
fi
if ! grep -q 'CONDITION schema=1 kind=ABI source=1296649989' "$serial_log"; then
  echo "CAPABILITY-ID-FAIL(condition): missing cross-class capability condition" >&2
  printf '%s\n' "$observed" >&2
  exit 1
fi
if grep -q 'stage=mmio-status value=t' "$serial_log"; then
  echo "CAPABILITY-ID-FAIL(volatile): MMIO volatile access executed through a PCI capability" >&2
  printf '%s\n' "$observed" >&2
  exit 1
fi

cp "$serial_log" "$artifact"
printf 'CAPABILITY-ID-PASS: PCI capability rejected as MMIO capability before volatile access\n'
printf '%s\n' "$observed"