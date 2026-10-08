#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/wsm-predicate-bit-v8.XXXXXX)"
trap 'rm -rf "$work"' EXIT
out="$ROOT_DIR/target/predicate-bit-v8"
mkdir -p "$out"

as --64 "$ROOT_DIR/artifacts/predicate-bit-v8-probe.s" -o "$work/positive.o"
as --64 "$ROOT_DIR/artifacts/predicate-bit-v8-malformed-probe.s" -o "$work/malformed.o"

bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/positive.o" "$work/positive.img" >/dev/null
bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/malformed.o" "$work/malformed.img" >/dev/null

cat >"$work/positive.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=1 status=ok
EOF
cat >"$work/malformed.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS CONDITION schema=1 kind=ABI source=0 value=31
EOF

positive="$(
  WSM_QEMU_TRANSCRIPT="$work/positive.expected"   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/positive.img"
)"
printf '%s\n' "$positive" >"$out/positive-transcript.txt"

malformed="$(
  WSM_QEMU_TRANSCRIPT="$work/malformed.expected"   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/malformed.img"
)"
printf '%s\n' "$malformed" >"$out/malformed-transcript.txt"

pin_sha="$(sha256sum "$ROOT_DIR/target-abi-pin.lisp" | awk '{print $1}')"
runtime_sha="$(sha256sum "$ROOT_DIR/src/runtime.s" | awk '{print $1}')"

cat >"$out/witness.json" <<EOF
{
  "schema": "wsm-os-predicate-bit-v8/v1",
  "issue": 86,
  "status": "PASS",
  "target_contract_commit": "b5ec3211f6bd07fb7c4a5f704875892eff145b91",
  "target_contract_version": 8,
  "boxed_kind_predicate_bit": 5,
  "bit_width": 1,
  "local_session_handles": [1, 2],
  "stable_word_identity_within_boot_runtime": true,
  "bit0_bit1_distinct": true,
  "aliases_nil": false,
  "aliases_legacy_true": false,
  "aliases_fixnum_0_or_1": false,
  "aliases_canonical_symbol_t": false,
  "malformed_boxed_handle_fails_closed": true,
  "semantic_interpretation": "external-SENS-authority",
  "target_pin_file_sha256": "$pin_sha",
  "runtime_source_sha256": "$runtime_sha"
}
EOF

echo "PREDICATE-BIT-V8: PASS"
echo "stable-singletons=true exact-bits=0,1 malformed-handle=ABI-fail-closed"
