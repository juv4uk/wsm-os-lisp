#!/usr/bin/env bash
set -euo pipefail

# MMIO bounded-poll witness (issue #40, DEVICE-CAP-VERTICAL-1).
#
# The Lisp device policy polls a real virtio-blk common-config register with an
# explicit finite retry budget. This gate proves, on the canonical pure-ASM
# target path (ADR-004, zero Rust), two outcomes:
#
#   1. d7 (ack-poll): after writing ACKNOWLEDGE (device_status bit 0), the
#      policy confirms the field within budget and returns t.
#   2. d8 (never-ready): the policy polls a field that never becomes ready;
#      it must exhaust the finite budget and return the explicit canonical
#      timeout result nil -- deterministically, without an unbounded spin.
#
# The unbounded-spin negative witness is enforced structurally by the runner:
# run-qemu-uefi.sh exits 124 on QEMU timeout, which fails this gate. A bounded,
# deterministic exit is the positive witness.
#
# The fixtures never see a physical or virtual address; they operate only
# through the opaque MMIO capability.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CML=""
if [[ -n "${CML_BIN:-}" && -x "${CML_BIN}" ]]; then
  CML="${CML_BIN}"
elif [[ -x "$ROOT_DIR/../cml/target/release/cml" ]]; then
  CML="$ROOT_DIR/../cml/target/release/cml"
elif command -v cml >/dev/null 2>&1; then
  CML="$(command -v cml)"
else
  echo "MMIO-BOUNDED-POLL: FAIL (no CML binary; set CML_BIN)" >&2
  exit 1
fi

work=$(mktemp -d /tmp/wsm-mmio-poll.XXXXXX)
trap 'rm -rf "$work"' EXIT

data_disk="$work/virtio-data.raw"
truncate -s 1M "$data_disk"

fail_count=0
fail() {
  echo "MMIO-BOUNDED-POLL: FAIL: $1" >&2
  fail_count=$((fail_count + 1))
}

run_case() { # <fixture> <transcript>
  local fixture="$1" transcript="$2"
  "$CML" x86-asm "$ROOT_DIR/artifacts/$fixture.lisp" > "$work/$fixture.s" 2>"$work/$fixture.cml.err" || {
    fail "$fixture: CML compile error"
    cat "$work/$fixture.cml.err" >&2
    return 1
  }
  as --64 "$work/$fixture.s" -o "$work/$fixture.o"
  bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/$fixture.o" "$work/$fixture.img" >/dev/null

  local expected="$ROOT_DIR/artifacts/$transcript"
  local observed
  observed="$(WSM_QEMU_DATA_DISK="$data_disk" \
    WSM_QEMU_VIRTIO_ADDR=5 \
    WSM_QEMU_VIRTIO_DISABLE_LEGACY=1 \
    WSM_QEMU_TRANSCRIPT="$expected" \
    bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/$fixture.img" 2>"$work/$fixture.qemu.err")" || {
    fail "$fixture: guest did not reach the bounded structured exit"
    cat "$work/$fixture.qemu.err" >&2
    return 1
  }
  printf '%s\n' "$observed"
  echo "MMIO-BOUNDED-POLL: PASS ($fixture)"
}

run_case "d7-virtio-blk-ack-poll-fixture"      "d7-virtio-blk-ack-poll-fixture-qemu-serial-transcript.txt"
run_case "d8-virtio-blk-never-ready-fixture"   "d8-virtio-blk-never-ready-fixture-qemu-serial-transcript.txt"

if [[ "$fail_count" -ne 0 ]]; then
  echo "MMIO-BOUNDED-POLL: RED" >&2
  exit 1
fi

echo "MMIO-BOUNDED-POLL: PASS (Lisp device policy polls with a finite budget; never-ready exits deterministically as nil, no unbounded spin)"
