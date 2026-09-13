#!/usr/bin/env bash
set -euo pipefail

# Architectural enforcement: wsm-os-lisp is Pure Lisp + x86-64 Assembly.
# RUST = 0 in production target per ADR-004.

echo "Verifying zero-Rust boundary in wsm-os-lisp..."

rust_files=$(find . \
  -not -path '*/.*' \
  -not -path './target/*' \
  \( -name '*.rs' -o -name 'Cargo.toml' -o -name 'Cargo.lock' -o -name 'rust-toolchain.toml' \) \
  -print)

if [[ -n "$rust_files" ]]; then
  echo "ERROR: Rust files detected in repository (violates ADR-004 Zero-Rust directive):" >&2
  echo "$rust_files" >&2
  exit 1
fi

echo "OK: Zero Rust files present (ADR-004 verified)."
