#!/usr/bin/env bash
set -euo pipefail

# Condition-distinguishability witness (issue #40, DEVICE-CAP-VERTICAL-1).
#
# Acceptance: a transport/device failure must be distinguishable from a Lisp
# semantic failure on the canonical pure-ASM target path (ADR-004, zero Rust).
#
# Both failures use the same structured line
#   WSM-OS CONDITION schema=1 kind=<NAME> source=<code> value=<word>
# and differ in a machine-checkable way:
#
#   Lisp semantic failure : kind=TYPE/...  source=0          (no substrate code)
#   device/ABI failure    : kind=ABI       source=0x4D49_4Fxx (substrate code)
#
# This gate also guards the offending-value field of a semantic failure: for
# (car 11) the reported value MUST be the bad word (fixnum 11 -> 91), not the
# condition kind (regression witnessed 2026-09-17: value=2).

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CML=""
if [[ -n "${CML_BIN:-}" && -x "${CML_BIN}" ]]; then
  CML="${CML_BIN}"
elif [[ -x "$ROOT_DIR/../cml/target/release/cml" ]]; then
  CML="$ROOT_DIR/../cml/target/release/cml"
elif command -v cml >/dev/null 2>&1; then
  CML="$(command -v cml)"
else
  echo "CONDITION-DISTINGUISHABILITY: FAIL (no CML binary; set CML_BIN)" >&2
  exit 1
fi

work=$(mktemp -d /tmp/wsm-cond-dist.XXXXXX)
trap 'rm -rf "$work"' EXIT

fail_count=0
fail() {
  echo "CONDITION-DISTINGUISHABILITY: FAIL: $1" >&2
  fail_count=$((fail_count + 1))
}

run_fixture() { # <fixture> <transcript> [with-device]
  local fixture="$1" transcript="$2" with_device="${3:-0}"
  "$CML" x86-asm "$ROOT_DIR/artifacts/$fixture.lisp" > "$work/$fixture.s" 2>"$work/$fixture.cml.err" || {
    fail "$fixture: CML compile error"
    cat "$work/$fixture.cml.err" >&2
    return 1
  }
  as --64 "$work/$fixture.s" -o "$work/$fixture.o"
  bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/$fixture.o" "$work/$fixture.img" >/dev/null

  local expected="$ROOT_DIR/artifacts/$transcript"
  local env_args=(WSM_QEMU_TRANSCRIPT="$expected")
  if [[ "$with_device" == "1" ]]; then
    local data_disk="$work/virtio-data.raw"
    truncate -s 1M "$data_disk"
    env_args+=(
      WSM_QEMU_DATA_DISK="$data_disk"
      WSM_QEMU_VIRTIO_ADDR=5
      WSM_QEMU_VIRTIO_DISABLE_LEGACY=1
    )
  fi

  local observed
  observed="$(env "${env_args[@]}" bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/$fixture.img" 2>"$work/$fixture.qemu.err")" || {
    fail "$fixture: guest did not reach the expected structured condition"
    cat "$work/$fixture.qemu.err" >&2
    return 1
  }
  printf '%s\n' "$observed"
}

echo "--- Lisp semantic failure ---"
semantic="$(run_fixture d9-lisp-type-failure-fixture d9-lisp-type-failure-fixture-qemu-serial-transcript.txt 0)" || true
if ! grep -q 'kind=TYPE source=0 value=91' <<<"$semantic"; then
  fail "semantic failure is not reported as kind=TYPE source=0 value=91"
fi
if grep -q 'WSM-OS RESULT' <<<"$semantic"; then
  fail "semantic failure produced a success RESULT line"
fi

echo "--- device/ABI failure ---"
device="$(run_fixture d4-mmio-bounds-read-fixture d4-mmio-bounds-read-fixture-qemu-serial-transcript.txt 1)" || true
if ! grep -q 'kind=ABI source=1296649986' <<<"$device"; then
  fail "device failure is not reported as kind=ABI source=1296649986"
fi
if grep -q 'WSM-OS RESULT' <<<"$device"; then
  fail "device failure produced a success RESULT line"
fi

echo "--- boundary ---"
semantic_src="$(grep -oE 'source=[0-9]+' <<<"$semantic" | head -1 | cut -d= -f2)"
device_src="$(grep -oE 'source=[0-9]+' <<<"$device" | head -1 | cut -d= -f2)"
if [[ "$semantic_src" != "0" ]]; then
  fail "semantic failure must carry source=0 (got $semantic_src)"
fi
if [[ -z "$device_src" || "$device_src" == "0" ]]; then
  fail "device failure must carry a non-zero substrate source (got '$device_src')"
fi
if [[ "$semantic_src" == "$device_src" ]]; then
  fail "semantic and device failures are not distinguishable by source"
fi

if [[ "$fail_count" -ne 0 ]]; then
  echo "CONDITION-DISTINGUISHABILITY: RED" >&2
  exit 1
fi

echo "CONDITION-DISTINGUISHABILITY: PASS (Lisp semantic failure kind=TYPE source=0 is distinguishable from device/ABI failure kind=ABI source=<substrate code>)"
