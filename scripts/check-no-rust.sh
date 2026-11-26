#!/usr/bin/env bash
set -euo pipefail

# Architectural enforcement: the production language boundary of wsm-os-lisp.
#
# ADR-006 (ACCEPTED, 2026-11-26) sets the boundary:
#   level 1  asm            bootstrap / critical minimum
#   level 2  Pascal         kernel, drivers, memory manager, GC, image loader
#   level 3  C              external libraries only, via FFI, under third_party/
#   level 4  SENS           policy and semantics (not implemented here)
#   level 5  Lisp           interactive environment
# Rust stays forbidden (RUST = 0), carried over from ADR-004 unchanged.

echo "Verifying production language boundary (ADR-006)..."

fail() {
  printf 'LANGUAGE-BOUNDARY-FAIL: %s\n' "$1" >&2
  exit 1
}

adr="docs/ADR-006-FPC-HOST-LANGUAGE.md"
[[ -s "$adr" ]] || fail "missing $adr"
grep -Fq -- "**Status/Статус**: **ACCEPTED**" "$adr" \
  || fail "ADR-006 is not ACCEPTED; Pascal is not admissible in the production boundary"

# 1. Rust is forbidden everywhere, in any form.
rust_files=$(find . \
  -not -path '*/.*' \
  -not -path './target/*' \
  \( -name '*.rs' -o -name 'Cargo.toml' -o -name 'Cargo.lock' -o -name 'rust-toolchain.toml' \) \
  -print)

if [[ -n "$rust_files" ]]; then
  echo "ERROR: Rust artifacts detected (RUST = 0 per ADR-004, carried into ADR-006):" >&2
  echo "$rust_files" >&2
  exit 1
fi

# 2. C lives outside the production boundary: external libraries only.
c_outside=$(find . \
  -not -path '*/.*' \
  -not -path './target/*' \
  -not -path './third_party/*' \
  \( -name '*.c' -o -name '*.h' \) \
  -print)

if [[ -n "$c_outside" ]]; then
  echo "ERROR: C source inside the production boundary (allowed only under third_party/):" >&2
  echo "$c_outside" >&2
  exit 1
fi

# 3. Pascal is admissible, but only under the target source tree.
pas_outside=$(find . \
  -not -path '*/.*' \
  -not -path './target/*' \
  -not -path './src/*' \
  \( -name '*.pas' -o -name '*.pp' -o -name '*.lpr' \) \
  -print)

if [[ -n "$pas_outside" ]]; then
  echo "ERROR: Pascal source outside src/ (target mechanism belongs there):" >&2
  echo "$pas_outside" >&2
  exit 1
fi

echo "OK: no Rust artifacts; no C in the production boundary; Pascal confined to src/."
echo "Boundary (ADR-006): asm | Pascal | C(third_party, FFI) | SENS | Lisp; RUST = 0."
