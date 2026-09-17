#!/usr/bin/env bash
set -euo pipefail

# MMIO device-operation witness (issue #40, DEVICE-CAP-VERTICAL-1).
#
# Proves, on the canonical pure-ASM target path (ADR-004, zero Rust), that a
# Lisp device-policy operation executes against a real QEMU virtio-blk
# common-config register through an opaque MMIO capability:
#
#   fixture: ((lambda (mmio)
#               ((lambda (_) (eq (mmio-read32 mmio 20) 1))
#                (mmio-write32 mmio 20 1)))
#             (mmio-capability))
#
# Register 20 (0x14) is virtio-pci common-config device_status: writing 1
# (ACKNOWLEDGE) and reading it back must yield 1.
#
# RED before the write32 value-preservation fix: wsm_mmio_write32 passed the
# value in %rcx through .Ldecode_check_mmio_cap, which clobbers %rcx with the
# capability nonce, so every store wrote low32(nonce << 16 >> 3) == 0x4868E000
# instead of the intended value; the read back was 0 and the fixture yielded
# nil. The fixture itself never sees a physical or virtual address.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve CML binary (same priority as the other #33/#40 gates).
CML=""
if [[ -n "${CML_BIN:-}" && -x "${CML_BIN}" ]]; then
  CML="${CML_BIN}"
elif [[ -x "$ROOT_DIR/../cml/target/release/cml" ]]; then
  CML="$ROOT_DIR/../cml/target/release/cml"
elif command -v cml >/dev/null 2>&1; then
  CML="$(command -v cml)"
else
  echo "MMIO-DEVICE-OP: FAIL (no CML binary; set CML_BIN)" >&2
  exit 1
fi

work=$(mktemp -d /tmp/wsm-mmio-device.XXXXXX)
trap 'rm -rf "$work"' EXIT

fixture_lisp="$ROOT_DIR/artifacts/d2-virtio-blk-status-fixture.lisp"
"$CML" x86-asm "$fixture_lisp" > "$work/fixture.s" 2>"$work/cml.err" || {
  echo "MMIO-DEVICE-OP: FAIL (CML compile error)" >&2
  cat "$work/cml.err" >&2
  exit 1
}

# The generated asm must actually request the MMIO substrate operations.
if ! grep -q 'call wsm_mmio_write32' "$work/fixture.s" || \
   ! grep -q 'call wsm_mmio_read32' "$work/fixture.s"; then
  echo "MMIO-DEVICE-OP: FAIL (CML did not emit wsm_mmio_read32/write32)" >&2
  exit 1
fi

as --64 "$work/fixture.s" -o "$work/fixture.o"
bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/fixture.o" "$work/image.img" >/dev/null

data_disk="$work/virtio-data.raw"
truncate -s 1M "$data_disk"

expected="$ROOT_DIR/artifacts/d2-virtio-blk-status-fixture-wsm-asm-transcript.txt"
observed="$(WSM_QEMU_DATA_DISK="$data_disk" \
  WSM_QEMU_VIRTIO_ADDR=5 \
  WSM_QEMU_VIRTIO_DISABLE_LEGACY=1 \
  WSM_QEMU_TRANSCRIPT="$expected" \
  bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/image.img" 2>"$work/qemu.err")" || {
  echo "MMIO-DEVICE-OP: FAIL (QEMU transcript mismatch)" >&2
  cat "$work/qemu.err" >&2
  exit 1
}

printf '%s\n' "$observed"
echo "MMIO-DEVICE-OP: PASS (Lisp device op writes/reads real virtio-blk device_status via opaque MMIO capability)"
