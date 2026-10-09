#!/usr/bin/env bash
set -euo pipefail

# #78 Phase A: prove a real x86 timer interrupt substrate on QEMU q35.
# No task context-switch claim is made by this witness.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/wsm-m3-timer.XXXXXX)"
trap 'rm -rf "$work"' EXIT
out="$ROOT_DIR/target/m3-timer-irq"
mkdir -p "$out"

as --64 "$ROOT_DIR/artifacts/m3-timer-irq-probe.s" -o "$work/probe.o"

cat >"$work/pass.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=1 status=ok
EOF
cat >"$work/fail.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=0 status=ok
EOF

bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/probe.o" "$work/timer.img" >/dev/null

positive="$(
  WSM_QEMU_TRANSCRIPT="$work/pass.expected"   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/timer.img"
)"
printf '%s\n' "$positive" >"$out/positive-transcript.txt"

WSM_FORCE_M3_TIMER_MASKED=1   bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/probe.o" "$work/masked.img" >/dev/null

negative="$(
  WSM_QEMU_TRANSCRIPT="$work/fail.expected"   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/masked.img"
)"
printf '%s\n' "$negative" >"$out/masked-irq0-transcript.txt"

runtime_sha="$(sha256sum "$ROOT_DIR/src/runtime.s" | awk '{print $1}')"
profile_sha="$(sha256sum "$ROOT_DIR/contracts/qemu-m0-machine-profile.lisp" | awk '{print $1}')"

cat >"$out/witness.json" <<EOF
{
  "schema": "wsm-os-m3-timer-irq/v1",
  "issue": 78,
  "status": "PASS",
  "machine": "q35",
  "timer": "8254-pit-channel0",
  "timer_mode": 3,
  "timer_divisor": 1193,
  "nominal_hz": 1000,
  "interrupt_controller": "legacy-8259-pic",
  "irq": 0,
  "idt_vector": 32,
  "minimum_observed_ticks": 8,
  "minimum_logical_alternations": 8,
  "wait": "finite-cpu-poll-budget",
  "eoi": "master-pic-nonspecific",
  "negative_masked_irq0": "PASS",
  "task_context_switch_claimed": false,
  "scheduler_policy_claimed": false,
  "sens_semantic_identity_added": false,
  "machine_profile_sha256": "$profile_sha",
  "runtime_source_sha256": "$runtime_sha"
}
EOF

echo "M3-TIMER-IRQ: PASS"
echo "irq0>=8 logical-alternations>=8 masked-irq0=fail-closed context-switch=false"
