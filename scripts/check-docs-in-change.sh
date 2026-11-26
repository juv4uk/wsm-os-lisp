#!/usr/bin/env bash
# DoD item 5: code changes must carry documentation in the same commit.
# The range is checked commit-by-commit; a later docs-only commit cannot excuse
# an earlier code-only commit, and a marker applies only to its own commit.
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

case "$base" in
  0000000000000000000000000000000000000000)
    note "base is the null SHA (new ref); nothing to compare"
    exit 0
    ;;
esac

if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  fail "base $base is not present locally — the workflow must check out full history"
fi
if ! git cat-file -e "${head}^{commit}" 2>/dev/null; then
  fail "head $head is not present locally — the workflow must check out full history"
fi

commits="$(git rev-list --reverse --topo-order "${base}..${head}")"
[ -n "$commits" ] || { note "empty range; nothing to check"; exit 0; }

checked=0
while IFS= read -r commit; do
  [ -n "$commit" ] || continue
  commit_line="$(git show -s --format='%h %s' "$commit")"

  # Compare each commit with its first parent. Commits on merged side branches
  # are visited independently; the merge commit is also checked against its
  # first parent so its integrated diff cannot disappear from the audit.
  read -r -a commit_record <<<"$(git rev-list --parents -n1 "$commit")"
  if [ "${#commit_record[@]}" -gt 1 ]; then
    first_parent="${commit_record[1]}"
    changed="$(git diff --no-renames --name-only "$first_parent" "$commit")"
  else
    changed="$(git diff-tree --root --no-commit-id --no-renames --name-only -r "$commit")"
  fi

  [ -n "$changed" ] || { note "$commit_line: no file changes"; continue; }
  code_changed="$(printf '%s\n' "$changed" | grep -E '^(src|scripts)/' || true)"
  [ -n "$code_changed" ] || { note "$commit_line: no code change"; continue; }

  docs_changed="$(printf '%s\n' "$changed" | grep -E '^(docs/|README\.md$|AGENTS\\.md$)' || true)"
  if [ -n "$docs_changed" ]; then
    note "$commit_line: code and documentation changed in the same commit"
    checked=$((checked + 1))
    continue
  fi

  message="$(git show -s --format='%B' "$commit")"
  marker_line="$(printf '%s\n' "$message" | grep -E '^DOCS-NOT-REQUIRED:' | head -1 || true)"
  if [ -n "$marker_line" ]; then
    reason="${marker_line#DOCS-NOT-REQUIRED:}"
    reason="$(printf '%s' "$reason" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$reason" ] || fail "$commit_line: DOCS-NOT-REQUIRED marker has an empty reason"
    note "$commit_line: code-only change declared in this commit: $reason"
    checked=$((checked + 1))
    continue
  fi

  printf '%s\n' "$code_changed" | sed "s#^#  $commit_line code: #" >&2
  fail "$commit_line: code changed without documentation in the same commit. Add docs/ or README changes, or write 'DOCS-NOT-REQUIRED: <reason>' in this commit message."
done <<<"$commits"

note "checked $checked code commit(s) individually"
