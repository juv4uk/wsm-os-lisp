#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Checking pure assembly runtime (src/runtime.s) for forbidden host imports..."
BOXED_TAG="$(bash "$ROOT_DIR/scripts/target-contract-value.sh" boxed-tag)"
as --64 --defsym WSM_TAG_BOXED="$BOXED_TAG" "$ROOT_DIR/src/runtime.s" -o /tmp/runtime_check.o

UNDEF=$(nm -u /tmp/runtime_check.o 2>/dev/null | sed -n 's/^[[:space:]]*U[[:space:]]*//p' | sort -u || true)

if [ -z "$UNDEF" ]; then
    echo "Runtime is clean (no undefined symbols)."
    exit 0
fi

# The only allowed undefined symbols are those deliberately provided by
# src/entry.s to the freestanding runtime:
#   wsm_fail        - failure boundary called from inside the runtime;
#   saved_boot_info - BootInfo pointer saved by entry.s and read by
#                     wsm_boot_handoff (see docs/TARGET-BOOT-HANDOFF-ABI.md).
for sym in $UNDEF; do
    case "$sym" in
        wsm_fail|saved_boot_info) ;;
        *)
            echo "ERROR: Forbidden external import detected: $sym"
            exit 1
            ;;
    esac
done

echo "Runtime is clean. All undefined symbols match the freestanding ABI boundary."
exit 0
