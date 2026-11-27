#!/usr/bin/env bash
set -euo pipefail

# Contract 12 migration: bounded device polling is lowered by the verified
# current-SENS path. D1 EQ is an exact PredicateBit result; D3 COND has exactly
# (test expression) pairs and returns structural NIL on exhaustion.
#
# MMIO access itself is a CML-owned, closed MachineOp category. It is not a
# SENS language identity and never passes through SID8/PrimOp name dispatch.
# The CML bridge test emits two fresh assemblies: expected status 1 (ACK) and
# expected status 4 (never-ready). Each contains exactly 64 ordered reads,
# a single write, one capability request, and no recursive/unbounded loop.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CML_BIN="${CML_BIN:-}"
if [[ -z "$CML_BIN" ]]; then
  if command -v cml >/dev/null 2>&1; then
    CML_BIN="$(command -v cml)"
  elif [[ -x "$ROOT_DIR/../cml/target/release/cml" ]]; then
    CML_BIN="$ROOT_DIR/../cml/target/release/cml"
  fi
fi
if [[ -z "$CML_BIN" || ! -x "$CML_BIN" ]]; then
  echo "MMIO-BOUNDED-POLL: FAIL (no pinned CML binary; set CML_BIN)" >&2
  exit 1
fi

if [[ -n "${CML_SOURCE_DIR:-}" ]]; then
  CML_ROOT="$CML_SOURCE_DIR"
else
  CML_ROOT="$(cd "$(dirname "$CML_BIN")/../.." && pwd)"
fi
if [[ ! -f "$CML_ROOT/Cargo.toml" || ! -f "$CML_ROOT/tests/wsm_os_current_x86_bridge_test.rs" ]]; then
  echo "MMIO-BOUNDED-POLL: FAIL (cannot resolve CML source tree from $CML_BIN; set CML_SOURCE_DIR)" >&2
  exit 1
fi

work="$(mktemp -d /tmp/wsm-mmio-poll.XXXXXX)"
trap 'rm -rf "$work"' EXIT
ack_asm="$work/current-sens-mmio-ack.s"
never_asm="$work/current-sens-mmio-never-ready.s"

echo "MMIO-BOUNDED-POLL: generating two finite current-SENS D1/EQ/COND programs"
(
  cd "$CML_ROOT"
  CML_CURRENT_SENS_MMIO_ACK_ASM_OUT="$ack_asm" \
  CML_CURRENT_SENS_MMIO_NEVER_READY_ASM_OUT="$never_asm" \
    cargo test --test wsm_os_current_x86_bridge_test \
      current_sens_bounded_mmio_poll_uses_only_d1_eq_cond_and_typed_machine_ops \
      -- --exact --nocapture
) || {
  echo "MMIO-BOUNDED-POLL: FAIL (current SENS -> CML -> target-v11 assembly test)" >&2
  exit 1
}

for asm in "$ack_asm" "$never_asm"; do
  if [[ ! -s "$asm" ]]; then
    echo "MMIO-BOUNDED-POLL: FAIL (CML did not emit $asm)" >&2
    exit 1
  fi
  if grep -Eq 'call wsm_eq([[:space:]]|$)|call wsm_atom([[:space:]]|$)' "$asm"; then
    echo "MMIO-BOUNDED-POLL: FAIL (legacy truth-valued predicate import in $asm)" >&2
    exit 1
  fi
  for import in wsm_mmio_capability wsm_mmio_write32 wsm_mmio_read32 wsm_eq_predicate_bit wsm_predicate_bit_bits; do
    grep -q "call $import" "$asm" || {
      echo "MMIO-BOUNDED-POLL: FAIL (missing $import in $asm)" >&2
      exit 1
    }
  done
done

build_image() { # <assembly> <image>
  local assembly="$1"
  local image="$2"
  local object="$work/$(basename "$image").o"
  as --64 "$assembly" -o "$object"
  bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$object" "$image" >/dev/null
}

ack_img="$work/current-sens-mmio-ack.img"
never_img="$work/current-sens-mmio-never-ready.img"
build_image "$ack_asm" "$ack_img"
build_image "$never_asm" "$never_img"

data_disk="$work/virtio-data.raw"
truncate -s 1M "$data_disk"

run_case() { # <label> <image> <expected-transcript>
  local label="$1" image="$2" expected="$3"
  local observed
  observed="$(WSM_QEMU_DATA_DISK="$data_disk" \
    WSM_QEMU_VIRTIO_ADDR=5 \
    WSM_QEMU_VIRTIO_DISABLE_LEGACY=1 \
    WSM_QEMU_TRANSCRIPT="$expected" \
    bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$image" 2>"$work/$label.qemu.err")" || {
      echo "MMIO-BOUNDED-POLL: FAIL ($label: QEMU execution/transcript mismatch)" >&2
      cat "$work/$label.qemu.err" >&2
      return 1
    }
  printf '%s\n' "$observed"
  echo "MMIO-BOUNDED-POLL: PASS ($label)"
}

ack_expected="$work/ack.expected"
cat >"$ack_expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=1 status=ok
EOF

never_expected="$work/never-ready.expected"
cat >"$never_expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=nil status=ok
EOF

run_case "ack-within-64-tests" "$ack_img" "$ack_expected"
run_case "never-ready-exhausts-64-tests" "$never_img" "$never_expected"

echo "MMIO-BOUNDED-POLL: PASS (current SENS D1 EQ + exact two-field D3 COND; 64 MMIO reads; exhaustion is structural NIL; no SID8 or unbounded loop)"
