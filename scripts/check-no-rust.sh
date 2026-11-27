#!/usr/bin/env bash
set -euo pipefail
# Backward-compatible entry point. Blanket language bans were removed by the
# owner directive recorded in docs/ADR-009-OPEN-LANGUAGE-AND-CODE-REUSE.md.
exec bash "$(dirname "$0")/check-language-policy.sh" "$@"
