#!/usr/bin/env bash
# Shell-safety gate: no data-to-command interpolation in repository scripts.
#
# Why this exists: a neighbouring project with heavy agent involvement shipped
# generated bash that interpolated untrusted data into command strings (a media
# title reached a download command; a notification click action was executed as a
# shell string). Both are command-injection classes that a generated script
# reproduces silently.
#
# Scope: every tracked *.sh and *.py outside this file itself.
# Rules (code lines only; full-line comments are ignored):
#   1. `eval` is never allowed.
#   2. `sh|bash|zsh|dash -c "<string containing $>"` is never allowed.
#   3. A command substitution used as the command name (`$(...)` at line start).
#   4. Python `shell=True` and `os.system(` are never allowed.
#
# Performance note (2026-11-27): the first version ran four awk|grep pipelines per
# file, which cost 11.5 s on this repository and dominated the local gate suite.
# It now makes one pass over all files in a single awk process. A gate that is
# slow enough to skip is a gate that gets skipped.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SELF="scripts/check-shell-safety.sh"

fail() {
  printf 'SHELL-SAFETY-FAIL: %s\n' "$1" >&2
  exit 1
}

cd "$ROOT_DIR"

mapfile -t files < <(
  find . \
    -path ./.git -prune -o \
    -path ./target -prune -o \
    -path ./node_modules -prune -o \
    -type f \( -name '*.sh' -o -name '*.py' \) -print | sort
)

# This file is excluded rather than filtered later: its own patterns would always
# match themselves, and a gate that has to explain its own output is noise.
kept=()
for f in "${files[@]}"; do
  [ "$f" = "./$SELF" ] && continue
  kept+=("$f")
done
files=("${kept[@]}")

[ "${#files[@]}" -gt 0 ] || fail 'no shell or python scripts were found; the gate would pass vacuously'

violations="$(
  awk '
    function code_line(l) {
      sub(/^[[:space:]]*/, "", l)
      return (l ~ /^#/) ? "" : l
    }
    {
      line = code_line($0)
      if (line == "") next
      is_py = (FILENAME ~ /\.py$/)

      if (line ~ /(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)/)
        printf "%s:%d: eval is forbidden in repository scripts\n", FILENAME, FNR

      if (line ~ /(bash|sh|zsh|dash)[[:space:]]+-c[[:space:]]+["\047][^"\047]*\$/)
        printf "%s:%d: interpolated command string passed to a shell\n", FILENAME, FNR

      if (line ~ /^[[:space:]]*\$\([^)]*\)/)
        printf "%s:%d: command substitution used as the command name\n", FILENAME, FNR

      if (is_py && line ~ /shell[[:space:]]*=[[:space:]]*True/)
        printf "%s:%d: shell=True is forbidden in repository scripts\n", FILENAME, FNR

      if (is_py && line ~ /os\.system[[:space:]]*\(/)
        printf "%s:%d: os.system( is forbidden in repository scripts\n", FILENAME, FNR
    }
  ' "${files[@]}" || true
)"

if [ -n "$violations" ]; then
  printf '%s\n' "$violations" >&2
  fail "$(printf '%s\n' "$violations" | wc -l) unsafe construct(s) found"
fi

printf 'SHELL-SAFETY-PASS: %s scripts scanned in one pass, no data-to-command interpolation.\n' "${#files[@]}"
