#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Checking pure assembly runtime (src/runtime.s) for forbidden host imports..."
as --64 "$ROOT_DIR/src/runtime.s" -o /tmp/runtime_check.o

UNDEF=$(nm -u /tmp/runtime_check.o 2>/dev/null | sed -n 's/^[[:space:]]*U[[:space:]]*//p' | sort -u || true)

if [ -z "$UNDEF" ]; then
    echo "Runtime is clean (no undefined symbols)."
    exit 0
fi

# The only allowed undefined symbol is wsm_fail when called from inside runtime
for sym in $UNDEF; do
    if [[ "$sym" != "wsm_fail" ]]; then
        echo "ERROR: Forbidden external import detected: $sym"
        exit 1
    fi
done

echo "Runtime is clean. All undefined symbols match the freestanding ABI boundary."
exit 0
