#!/usr/bin/env bash
set -euo pipefail

echo "Checking wsm-os-runtime for host imports..."
cargo build -p wsm-os-runtime --lib --target x86_64-unknown-none

# Extract all undefined symbols from the rlib
UNDEF=$(nm -u target/x86_64-unknown-none/debug/libwsm_os_runtime.rlib || true)

# Look for banned host symbols (e.g. malloc, free, libc stuff)
# Since it's no_std, we just want to make sure no OS-level stuff slipped in.
# A simple heuristic: no symbols starting with 'std::' or common libc names.
if echo "$UNDEF" | grep -Eq 'malloc|free|printf|fopen|std::'; then
    echo "ERROR: Found forbidden host imports in runtime!"
    echo "$UNDEF" | grep -E 'malloc|free|printf|fopen|std::'
    exit 1
fi

echo "Runtime is clean."
exit 0
