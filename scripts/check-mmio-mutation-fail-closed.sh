#!/usr/bin/env bash
set -euo pipefail

# MMIO mutation fail-closed witness (issue #40, DEVICE-CAP-VERTICAL-1).
#
# Proves, on the canonical pure-ASM target path (ADR-004, zero Rust), that the
# MMIO boundary fails closed *before any volatile access* under the adversarial
# mutations required by #40, and that each failure is reported as a structured
# device/ABI condition (kind=ABI source=<substrate code>) distinguishable from a
# Lisp semantic failure (kind=TYPE/OOM/... source=0).
#
# Mutations witnessed:
#   1. out-of-bounds read  (offset == region length)      -> source 0x4D494F02
#   2. out-of-bounds write (offset == region length)      -> source 0x4D494F05
#   3. wrong/unknown capability (PCI cap used as MMIO)    -> source 0x4D494F05
#   4. provisioned mapping absent (no virtio-blk device)  -> source 0x4D494F00 value=6
#   5. bootloader physical mapping absent (forced)        -> source 0x4D494F00 value=2
#
# Every expected transcript is failure-only: it must NOT contain a
# `WSM-OS RESULT ... status=ok` line, which is the witness that no volatile
# access (and no semantic result) was produced.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CML=""
if [[ -n "${CML_BIN:-}" && -x "${CML_BIN}" ]]; then
  CML="${CML_BIN}"
elif [[ -x "$ROOT_DIR/../cml/target/release/cml" ]]; then
  CML="$ROOT_DIR/../cml/target/release/cml"
elif command -v cml >/dev/null 2>&1; then
  CML="$(command -v cml)"
else
  echo "MMIO-MUTATION: FAIL (no CML binary; set CML_BIN)" >&2
  exit 1
fi

work=$(mktemp -d /tmp/wsm-mmio-mutation.XXXXXX)
trap 'rm -rf "$work"' EXIT

data_disk="$work/virtio-data.raw"
truncate -s 1M "$data_disk"

fail_count=0
fail() {
  echo "MMIO-MUTATION: FAIL: $1" >&2
  fail_count=$((fail_count + 1))
}

build_fixture() { # <fixture-name> <image-path>; honors WSM_OS_FORCE_NO_PHYS_MAP
  local fixture="$1" image="$2"
  "$CML" x86-asm "$ROOT_DIR/artifacts/$fixture.lisp" > "$work/$fixture.s" 2>"$work/$fixture.cml.err" || {
    fail "$fixture: CML compile error"
    cat "$work/$fixture.cml.err" >&2
    return 1
  }
  as --64 "$work/$fixture.s" -o "$work/$fixture.o"
  bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/$fixture.o" "$image" >/dev/null
}

run_case() { # <name> <fixture> <transcript> <with-device:0|1>
  local name="$1" fixture="$2" transcript="$3" with_device="$4"
  local image="$work/$fixture-$name.img"

  if [[ "$name" == "forced-no-phys-map" ]]; then
    WSM_OS_FORCE_NO_PHYS_MAP=1 build_fixture "$fixture" "$image" || return 1
  else
    build_fixture "$fixture" "$image" || return 1
  fi

  local expected="$ROOT_DIR/artifacts/$transcript"
  if grep -q 'WSM-OS RESULT' "$expected"; then
    fail "$name: expected transcript contains a success RESULT line"
    return 1
  fi

  local env_args=(WSM_QEMU_TRANSCRIPT="$expected")
  if [[ "$with_device" == "1" ]]; then
    env_args+=(
      WSM_QEMU_DATA_DISK="$data_disk"
      WSM_QEMU_VIRTIO_ADDR=5
      WSM_QEMU_VIRTIO_DISABLE_LEGACY=1
    )
  fi

  local observed
  observed="$(env "${env_args[@]}" bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$image" 2>"$work/$name.qemu.err")" || {
    fail "$name: guest did not reach the expected structured failure"
    cat "$work/$name.qemu.err" >&2
    return 1
  }
  if grep -q 'WSM-OS RESULT' <<<"$observed"; then
    fail "$name: guest produced a RESULT under an adversarial mutation"
    return 1
  fi
  printf '%s\n' "$observed"
  echo "MMIO-MUTATION: PASS ($name)"
}

run_case "bounds-read"            "d4-mmio-bounds-read-fixture"  "d4-mmio-bounds-read-fixture-qemu-serial-transcript.txt" 1
run_case "bounds-write"           "d5-mmio-bounds-write-fixture" "d5-mmio-bounds-write-fixture-qemu-serial-transcript.txt" 1
run_case "wrong-capability"       "d6-mmio-wrong-capability-fixture" "d6-mmio-wrong-capability-fixture-qemu-serial-transcript.txt" 1
run_case "provision-unavailable"  "d4-mmio-bounds-read-fixture"  "d4-mmio-bounds-read-fixture-provision-unavailable-transcript.txt" 0
run_case "forced-no-phys-map"     "d4-mmio-bounds-read-fixture"  "d4-mmio-bounds-read-fixture-no-phys-map-transcript.txt" 1

if [[ "$fail_count" -ne 0 ]]; then
  echo "MMIO-MUTATION: RED ($fail_count mutation(s) did not fail closed)" >&2
  exit 1
fi

echo "MMIO-MUTATION: PASS (all adversarial MMIO mutations fail closed with structured device/ABI conditions before volatile access)"
