#!/usr/bin/env bash
# DoD item 5 gate: a change to code carries a documentation change with it.
#
# The owner's Definition of Done says "Docs оновлено в тому ж PR — не «потім»".
# Of the eight items it is the one that is both unambiguous and cheap to check,
# so it is the first of them to get teeth instead of a checklist tick.
#
# Rule: if the range changes anything under src/ or scripts/, it must also change
# something under docs/, README.md or AGENTS.md.
#
# Escape hatch, deliberately explicit: a commit message may contain
#   DOCS-NOT-REQUIRED: <reason>
# and the gate passes. A reason is required — an empty marker fails. The point is
# not to forbid code-only changes, it is to make them a decision someone wrote
# down rather than an omission nobody noticed.
#
# Usage: bash scripts/check-docs-in-change.sh <base-sha> [head-sha]
set -euo pipefail

base="${1:-}"
head="${2:-HEAD}"

fail() {
  printf 'DOCS-IN-CHANGE-FAIL: %s\n' "$1" >&2
  exit 1
}

note() {
  printf 'DOCS-IN-CHANGE: %s\n' "$1"
}

[ -n "$base" ] || fail "usage: check-docs-in-change.sh <base-sha> [head-sha]"

# A new ref arrives as forty zeroes; there is no range to compare.
case "$base" in
  0000000000000000000000000000000000000000)
    note "base is the null SHA (new ref); nothing to compare"
    exit 0
    ;;
esac

if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  fail "base $base is not present locally — the workflow must check out full history"
fi

changed="$(git diff --name-only "$base" "$head")"
[ -n "$changed" ] || { note "empty range; nothing to check"; exit 0; }

code_changed="$(printf '%s\n' "$changed" | grep -E '^(src|scripts)/' || true)"
docs_changed="$(printf '%s\n' "$changed" | grep -E '^(docs/|README\.md$|AGENTS\.md$)' || true)"

if [ -z "$code_changed" ]; then
  note "no code change in range; documentation rule does not apply"
  exit 0
fi

if [ -n "$docs_changed" ]; then
  note "code and documentation changed together"
  exit 0
fi

messages="$(git log --format='%B' "$base..$head")"
marker="$(printf '%s\n' "$messages" | grep -E '^DOCS-NOT-REQUIRED: .+' | head -1 || true)"
if [ -n "$marker" ]; then
  note "code-only change declared: ${marker#DOCS-NOT-REQUIRED: }"
  exit 0
fi

printf '%s\n' "$code_changed" | sed 's/^/  code: /' >&2
fail "code changed without documentation. Add a docs/ or README change in the same push, or write 'DOCS-NOT-REQUIRED: <reason>' in the commit message (Definition of Done item 5)."
