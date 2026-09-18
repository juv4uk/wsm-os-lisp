#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$(mktemp /tmp/wsm-boxed-rational-runtime.XXXXXX.o)"
trap 'rm -f "$OBJ"' EXIT

as --64 "$ROOT_DIR/src/runtime.s" -o "$OBJ"

defined_symbols="$(nm -g --defined-only "$OBJ" | awk '{print $3}' | sort -u)"

require_symbol() {
    local symbol="$1"
    if ! grep -Fxq "$symbol" <<<"$defined_symbols"; then
        echo "BOXED-RATIONAL-RUNTIME-RED: missing native runtime import: $symbol" >&2
        exit 1
    fi
}

# #45 mechanism boundary. These names intentionally match the existing hosted
# reference FFI, while freestanding storage remains a runtime-owned generic
# Boxed arena. This test owns no Lisp arithmetic/reduction answer.
require_symbol wsm_wrap_rational
require_symbol wsm_unwrap_rational

echo "BOXED-RATIONAL-RUNTIME-GREEN: native wrap/unwrap imports are exported"
