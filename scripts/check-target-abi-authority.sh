#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PIN_FILE="$ROOT/target-abi-pin.lisp"
RUNTIME="$ROOT/src/runtime.s"

PIN=$(sed -n 's/.*(commit \. "\([0-9a-f]\{40\}\)").*/\1/p' "$PIN_FILE")
SCHEMA=$(sed -n 's/.*(schema \. "\([^"]*\)").*/\1/p' "$PIN_FILE")
VERSION=$(sed -n 's/.*(version \. \([0-9][0-9]*\)).*/\1/p' "$PIN_FILE")
EXPECTED_SHA=$(sed -n 's/.*(projection-sha256 \. "\([0-9a-f]\{64\}\)").*/\1/p' "$PIN_FILE")

[ -n "$PIN" ] && [ -n "$SCHEMA" ] && [ -n "$VERSION" ] && [ -n "$EXPECTED_SHA" ] || {
  echo "target ABI pin is incomplete" >&2
  exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git -C "$TMP" init -q
git -C "$TMP" remote add origin https://github.com/juv4uk/wsm-target-contract.git
git -C "$TMP" fetch -q --depth 1 origin "$PIN"
git -C "$TMP" checkout -q FETCH_HEAD
ACTUAL=$(git -C "$TMP" rev-parse HEAD)
[ "$ACTUAL" = "$PIN" ] || {
  echo "target ABI pin mismatch: expected=$PIN actual=$ACTUAL" >&2
  exit 1
}

PROJECTION="$TMP/target-contract.lisp"
ACTUAL_SHA=$(sha256sum "$PROJECTION" | awk '{print $1}')
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || {
  echo "target ABI projection digest mismatch" >&2
  echo "expected=$EXPECTED_SHA" >&2
  echo "actual=$ACTUAL_SHA" >&2
  exit 1
}

grep -Fq "(schema . \"$SCHEMA\")" "$PROJECTION"
grep -Fq "(version . $VERSION)" "$PROJECTION"
grep -Fq "(semantics . sens-contract-12)" "$PROJECTION"
grep -Fq 'juv4uk/sens:contracts/language-contract-12.lisp' "$PROJECTION"
grep -Fq "(kinds-defined-so-far . (string game-handle rational predicate-bit))" "$PROJECTION"
grep -Fq "(current-predicate-operations . ((atom-import . wsm_atom_predicate_bit) (eq-import . wsm_eq_predicate_bit)" "$PROJECTION"
grep -Fq "wsm_atom_predicate_bit" "$PROJECTION"
grep -Fq "wsm_eq_predicate_bit" "$PROJECTION"
grep -Fq "wsm_predicate_bit_0" "$PROJECTION"
grep -Fq "wsm_predicate_bit_1" "$PROJECTION"
grep -Fq "wsm_predicate_bit_bits" "$PROJECTION"
grep -Fq "wsm_rational_new" "$PROJECTION"

if grep -Eiq 'sid8|sens8|function8|wsm_sid8_' "$PROJECTION"; then
  echo "retired flat-eight identity leaked into active target projection" >&2
  exit 1
fi

# Contract 12 D1 machine imports must return exact runtime-owned PredicateBits.
grep -Fq ".globl wsm_atom_predicate_bit" "$RUNTIME"
grep -Fq ".globl wsm_eq_predicate_bit" "$RUNTIME"
grep -Fq "jmp wsm_predicate_bit_1" "$RUNTIME"
grep -Fq "jmp wsm_predicate_bit_0" "$RUNTIME"
grep -Fq "movl \$ERR_TYPE, %esi" "$RUNTIME"

echo "TARGET-ABI-V10-CONTRACT12-PASS pin=$PIN schema=$SCHEMA version=$VERSION sha256=$ACTUAL_SHA"
