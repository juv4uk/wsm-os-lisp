#!/usr/bin/env bash
set -euo pipefail

# TARGET-OBSERVER-GENERALIZE-1 (issue #33) structural witness.
#
# Proves, from the assembled object, that src/entry.s::print_value does NOT
# carry fixture-derived expected symbol names (no target-authored expected
# truth): the target serializes only the observable symbol id (sym<id>) and
# never emits compiler-owned names.
#
# Negative authority witnesses (must each FAIL if violated):
#   1. no dead hardcoded expected value row "value=(A . B)" in .rodata
#   2. no fixture-specific symbol name literals in .rodata
#   3. no hardcoded symbol ID dispatch in print_value (cmp against encoded IDs
#      mapping to fixture-specific interned names)
#
# Positive structural witness (must PASS): the generic sym<id> renderer exists
# and is reached without any fixture-specific comparison.
#
# On pre-fix main (`cmp $12 -> 'A'`, `cmp $20 -> 'B'`, dead msg_result_ab) the
# negative witnesses all FAIL, so this script was the RED witness for issue #33.
# After the bounded-observer fix the negative witnesses PASS and the positive
# witness must hold.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${WSM_OS_ENTRY_SRC:-$ROOT_DIR/src/entry.s}"

mkdir -p "$ROOT_DIR/target"
obj="$ROOT_DIR/target/.target-observer-check.$.o"
trap 'rm -f "$obj"' EXIT

as --64 "$SRC" -o "$obj"

fail_count=0
fail() {
  echo "TARGET-OBSERVER: FAIL: $1" >&2
  fail_count=$((fail_count + 1))
}
note() {
  echo "TARGET-OBSERVER: $1" >&2
}

# --- Negative witnesses -----------------------------------------------------

# 1. Dead hardcoded expected value row must not exist.
if nm "$obj" | grep -q 'msg_result_ab'; then
  fail "dead hardcoded expected literal 'msg_result_ab' present (fixture-specific expected result)"
fi

# 2. Fixture-specific symbol name literals must not exist.
sym_names_found=""
if nm "$obj" | grep -q 'msg_sym_a'; then
  sym_names_found="msg_sym_a"
fi
if nm "$obj" | grep -q 'msg_sym_b'; then
  sym_names_found="${sym_names_found:+$sym_names_found }msg_sym_b"
fi
if [[ -n "$sym_names_found" ]]; then
  fail "target-authored fixture symbol names present: $sym_names_found"
fi

# 3. print_value must not contain hardcoded symbol ID dispatch.
disasm="$(objdump -d --disassemble=print_value "$obj" 2>/dev/null)" || disasm=""
if [[ -n "$disasm" ]]; then
  # Known fixture symbol IDs (encode_symbol: id << 3 | 4):
  #   A=1 -> encode(1) = 12 (0x0c), decoded by print_value as (12 >> 3) = 1
  #   B=2 -> encode(2) = 20 (0x14), decoded by print_value as (20 >> 3) = 2
  # After bounded fix, print_value prints "sym1" / "sym2" (decoded id), not "sym12" / "sym20".
  if grep -qE 'cmp[[:blank:]]+\$0xc,' <<<"$disasm" || \
     grep -qE 'cmp[[:blank:]]+\$0x14,' <<<"$disasm"; then
    fail "print_value contains hardcoded fixture symbol ID dispatch (cmp against 0x0c/0x14)"
  fi
fi

# --- Positive structural witness --------------------------------------------

print_value_disasm_ok=0
if [[ -n "$disasm" ]]; then
  # The generic renderer prints the prefix 'sym' (via msg_sym_prefix) and the
  # decimal id (via print_decimal call). Both must be present and wired into
  # print_value without any fixture-specific branch.
  if nm "$obj" | grep -q 'msg_sym_prefix'; then
    note "positive: msg_sym_prefix literal present"
  else
    fail "no msg_sym_prefix literal (generic 'sym' prefix renderer missing)"
  fi
  print_decimal_calls="$(grep -c 'call.*print_decimal' <<<"$disasm" || true)"
  if [[ "$print_decimal_calls" -ge 1 ]]; then
    note "positive: print_value calls print_decimal (generic id renderer wired)"
  else
    fail "print_value never calls print_decimal (bounded symbol id renderer missing)"
  fi
else
  fail "print_value absent from object; cannot verify bounded symbol renderer"
fi

if [[ "$fail_count" -ne 0 ]]; then
  echo "TARGET-OBSERVER: RED (target carries fixture-derived expected truth or lacks bounded renderer)" >&2
  exit 1
fi

echo "TARGET-OBSERVER: PASS (target serializes only observable representations, no fixture names)"
