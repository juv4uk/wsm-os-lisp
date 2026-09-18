#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$(mktemp /tmp/wsm-boxed-rational-runtime.XXXXXX.o)"
trap 'rm -f "$OBJ"' EXIT

contract="$ROOT_DIR/contracts/wsm-target-contract/target-contract.lisp"
grep -Fq '(version . 6)' "$contract"
for symbol in wsm_rational_new wsm_rational_numerator wsm_rational_denominator; do
    grep -Fq "$symbol" "$contract" || {
        echo "BOXED-RATIONAL-RUNTIME-RED: pinned target contract does not ratify $symbol" >&2
        exit 1
    }
done

as --64 "$ROOT_DIR/src/runtime.s" -o "$OBJ"

defined_symbols="$(nm -g --defined-only "$OBJ" | awk '{print $3}' | sort -u)"

require_symbol() {
    local symbol="$1"
    if ! grep -Fxq "$symbol" <<<"$defined_symbols"; then
        echo "BOXED-RATIONAL-RUNTIME-RED: missing native runtime import: $symbol" >&2
        exit 1
    fi
}

# #45 mechanism boundary comes from the pinned neutral target-contract v6.
# This test owns no Lisp arithmetic/reduction answer.
require_symbol wsm_rational_new
require_symbol wsm_rational_numerator
require_symbol wsm_rational_denominator

echo "BOXED-RATIONAL-RUNTIME-GREEN: ratified native Rational imports are exported"
