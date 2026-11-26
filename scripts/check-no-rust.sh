#!/usr/bin/env bash
set -euo pipefail

# Language boundary of wsm-os-lisp.
#
# History, because it matters for reading this file:
#   * ADR-004 (2026-09-14) admitted exactly two languages — Lisp and x86-64
#     assembly — with RUST = 0 and zero C in production.
#   * ADR-006 (2026-11-26) widened that to asm | Pascal | C (external, via FFI) |
#     SENS | Lisp, and this script became a boundary checker that also confined
#     Pascal to src/ and C to third_party/.
#   * 2026-11-27, owner instruction: "там потрібно зняти обмеження на мови".
#     The path confinement is therefore gone. A language is not restricted by
#     where a file lives; the repository no longer tells anyone which directory a
#     language belongs in.
#
# What remains is the one restriction the owner wrote himself and has not lifted:
#   RUST = 0.
# If that changes, this file changes with it — on his word, not on an agent's.
#
# This script checks what exists in the tree. It does not claim that any language
# is suitable for the mechanism layer; suitability is a matter of witnesses, not
# of permission.

echo "Verifying language boundary (ADR-006, owner instruction 2026-11-27)..."

fail() {
  printf 'LANGUAGE-BOUNDARY-FAIL: %s\n' "$1" >&2
  exit 1
}

adr="docs/ADR-006-FPC-AS-FOUNDATION-PROPOSAL.md"
[[ -s "$adr" ]] || fail "missing $adr"

rust_files=$(find . \
  -not -path '*/.*' \
  -not -path './target/*' \
  \( -name '*.rs' -o -name 'Cargo.toml' -o -name 'Cargo.lock' -o -name 'rust-toolchain.toml' \) \
  -print)

if [[ -n "$rust_files" ]]; then
  echo "ERROR: Rust artifacts detected. RUST = 0 is the owner's standing rule:" >&2
  echo "$rust_files" >&2
  exit 1
fi

printf '%s\n' 'LANGUAGE-BOUNDARY-PASS: no path confinement; RUST = 0 holds.'
