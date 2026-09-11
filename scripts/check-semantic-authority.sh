#!/usr/bin/env bash
set -euo pipefail

runtime="crates/wsm-os-runtime/src/lib.rs"
kernel="crates/wsm-os-kernel/src/main.rs"
hosted="crates/wsm-os-hosted/src/main.rs"
profile="target-profile.wsm"
abi_doc="docs/TARGET-ABI.md"

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

# Canonical WSM truth is Symbol(t). The target contract may reserve the old
# Tag::True bit pattern for ABI history, but runtime/boot validation may not
# admit it as a second language truth value.
forbid_literal "$runtime" 'tag if tag == wsm_os_target::Tag::True as Word'
forbid_literal "$kernel" 'result == wsm_os_target::TRUE'
forbid_literal "$kernel" 'cell.cdr == wsm_os_target::TRUE'
require_literal "$runtime" 'legacy_true_tag_is_not_a_second_semantic_truth'
require_literal "$hosted" 'legacy true tag is not admitted semantic truth'
require_literal "$profile" '(reserved-representations . (legacy-true-tag))'
require_literal "$abi_doc" 'reserved legacy representation'

# A capability is authority only when it decodes to the current descriptor
# shape and matches an active nonce-bearing substrate grant. Numeric ID 1 is
# history, not an alternate authority path.
forbid_literal "$kernel" 'PCI_CONFIG_CAPABILITY_ID'
forbid_literal "$hosted" 'PCI_CONFIG_CAPABILITY_ID'
require_literal "$kernel" 'Legacy numeric IDs are representation history, not authority.'
require_literal "$hosted" 'legacy_numeric_capability_id_is_not_authority'

# Exact numeric semantics must not silently acquire a floating-point escape
# hatch in the semantic runtime or boot validation path.
if grep -REn '\bas f(32|64)\b|\bf(32|64)::|\bf(32|64)\b' \
    crates/wsm-os-runtime/src crates/wsm-os-kernel/src/main.rs >/dev/null; then
  fail 'float use found in exact semantic runtime/boot path'
fi

printf '%s\n' 'SEMANTIC-AUTHORITY-PASS: canonical truth, nonce capabilities and exact numeric boundary fail closed.'
