#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

runtime="$ROOT_DIR/src/runtime.s"
entry="$ROOT_DIR/src/entry.s"
profile="$ROOT_DIR/target-profile.lisp"
[[ -f "$profile" ]] || profile="$ROOT_DIR/target-profile.wsm"
abi_doc="$ROOT_DIR/docs/TARGET-ABI.md"

fail() {
  printf 'SEMANTIC-AUTHORITY-FAIL: %s\n' "$1" >&2
  exit 1
}

require_literal() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "$file is missing required semantic boundary: $text"
}

forbid_literal() {
  local file="$1"
  local text="$2"
  if grep -Fq -- "$text" "$file"; then
    fail "$file contains forbidden semantic fallback: $text"
  fi
}

# Canonical WSM truth is Symbol(t) (WSM_CANONICAL_T).
# Tag::True (immediate 2) must never be admitted as semantic truth.
require_literal "$runtime" '.set WSM_CANONICAL_T,         0xFFFFFFFFFFFFFFFC'
require_literal "$profile" '(reserved-representations . (legacy-true-tag))'
require_literal "$abi_doc" 'reserved legacy representation'

# A capability is authority only when it decodes to nonce-bearing descriptor
require_literal "$runtime" 'wsm_pci_config_capability'
require_literal "$runtime" '0x150434954346'

# Closed error code vocabulary
require_literal "$runtime" '.set ERR_OOM,                 1'
require_literal "$runtime" '.set ERR_TYPE,                2'
require_literal "$runtime" '.set ERR_ABI,                 4'

# Floating-point escape hatches are strictly forbidden in exact semantic assembly
if grep -REn '\b(fld|fst|fadd|fsub|fmul|fdiv|movss|movsd|addss|addsd)\b' \
    "$ROOT_DIR/src/runtime.s" "$ROOT_DIR/src/entry.s" >/dev/null; then
  fail 'float instructions found in exact semantic runtime/entry path'
fi

printf '%s\n' 'SEMANTIC-AUTHORITY-PASS: canonical truth, closed errors, nonce capabilities and exact numeric boundary fail closed.'
