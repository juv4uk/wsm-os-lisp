#!/usr/bin/env bash
# Shell-safety gate: no data-to-command interpolation in repository scripts.
#
# Why this exists: a neighbouring project with heavy agent involvement shipped
# generated bash that interpolated untrusted data into command strings (a media
# title reached a download command; a notification click action was executed as
# a shell string). Both are command-injection classes that a generated script
# reproduces silently. This gate keeps that class out of this repository.
#
# Scope: every tracked *.sh and *.py outside this file itself.
# Rules (code lines only; full-line comments are ignored):
#   1. `eval` is never allowed.
#   2. `sh|bash|zsh|dash -c "<string containing $>"` is never allowed.
#   3. A command substitution used as the command name (`$(...)` at line start).
#   4. Python `shell=True` and `os.system(` are never allowed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SELF="scripts/check-shell-safety.sh"

fail() {
  printf 'SHELL-SAFETY-FAIL: %s\n' "$1" >&2
  exit 1
}

scan_shell() {
  local file="$1" rel="$2" label="$3" pattern="$4" hits
  hits=$(awk '{ line=$0; sub(/^[[:space:]]*/, "", line); if (line ~ /^#/) next; printf "%d:%s\n", FNR, $0 }' "$file" \
    | grep -E -n "$pattern" || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    fail "$rel: $label"
  fi
}

scan_python() {
  local file="$1" rel="$2" label="$3" pattern="$4" hits
  hits=$(awk '{ line=$0; sub(/^[[:space:]]*/, "", line); if (line ~ /^#/) next; printf "%d:%s\n", FNR, $0 }' "$file" \
    | grep -E -n "$pattern" || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    fail "$rel: $label"
  fi
}

count=0
while IFS= read -r file; do
  rel="${file#"$ROOT_DIR"/}"
  [ "$rel" = "$SELF" ] && continue
  scan_shell "$file" "$rel" 'eval is forbidden in repository scripts' '\beval\b'
  scan_shell "$file" "$rel" 'interpolated command string passed to a shell (-c with $)' \
    '(bash|sh|zsh|dash)[[:space:]]+-c[[:space:]]+["'"'"'][^"'"'"']*\$'
  scan_shell "$file" "$rel" 'command substitution used as the command name' \
    '^[[:space:]]*\$\([^)]*\)'
  count=$((count + 1))
done < <(find "$ROOT_DIR" -path "$ROOT_DIR/.git" -prune -o -name '*.sh' -type f -print | sort)

py_count=0
while IFS= read -r file; do
  rel="${file#"$ROOT_DIR"/}"
  scan_python "$file" "$rel" 'shell=True is forbidden in repository scripts' 'shell[[:space:]]*=[[:space:]]*True'
  scan_python "$file" "$rel" 'os.system( is forbidden in repository scripts' 'os\.system[[:space:]]*\('
  py_count=$((py_count + 1))
done < <(find "$ROOT_DIR" -path "$ROOT_DIR/.git" -prune -o -name '*.py' -type f -print | sort)

[ "$count" -gt 0 ] || fail 'no shell scripts were scanned; the gate would pass vacuously'
[ "$py_count" -gt 0 ] || fail 'no python scripts were scanned; the gate would pass vacuously'

printf 'SHELL-SAFETY-PASS: %s shell and %s python scripts carry no data-to-command interpolation.\n' "$count" "$py_count"
