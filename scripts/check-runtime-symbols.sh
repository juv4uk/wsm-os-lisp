#!/usr/bin/env bash
set -euo pipefail

echo "Checking wsm-os-runtime for host imports..."
cargo build -p wsm-os-runtime --lib --target x86_64-unknown-none

# Demangle Rust v0 symbols before classification. Raw crate-disambiguator
# hashes legitimately differ between a local path dependency and its pinned
# Git source, so those hashes are not a stable import boundary.
RUNTIME_RLIB="${CARGO_TARGET_DIR:-target}/x86_64-unknown-none/debug/libwsm_os_runtime.rlib"
UNDEF=$(nm -uC "$RUNTIME_RLIB" 2>/dev/null | sed -n 's/^[[:space:]]*U[[:space:]]*//p' | sort -u || true)

if [ -z "$UNDEF" ]; then
    echo "Runtime is clean (no undefined symbols)."
    exit 0
fi

ALLOWLIST="$(dirname "$0")/runtime-symbol-allowlist.txt"
VIOLATIONS=$(comm -23 <(printf '%s\n' "$UNDEF") "$ALLOWLIST")
if [ -n "$VIOLATIONS" ]; then
    while IFS= read -r symbol; do
        echo "ERROR: Forbidden external import detected: $symbol"
    done <<< "$VIOLATIONS"
    exit 1
fi

echo "Runtime is clean. All undefined symbols match the demangled exact allowlist."
exit 0
