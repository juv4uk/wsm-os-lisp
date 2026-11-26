#!/usr/bin/env bash
# Ratification gate: an ADR may say ACCEPTED only if the owner said so.
#
# The check is provenance, not opinion. For every docs/ADR-*.md whose status line
# says ACCEPTED, git blame tells us which commit introduced that line and who
# authored it. If the author is not one of the declared owner identities, the ADR
# needs an entry in docs/decisions/OWNER-CONFIRMATIONS.lisp, and that entry must
# itself be owner-authored.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$ROOT_DIR/docs/decisions/OWNER-CONFIRMATIONS.lisp"

fail() { printf 'ADR-RATIFICATION-FAIL: %s\n' "$1" >&2; exit 1; }
note() { printf 'ADR-RATIFICATION: %s\n' "$1"; }

[ -f "$CONF" ] || fail "docs/decisions/OWNER-CONFIRMATIONS.lisp is missing; no ratification can be checked"

owners="$(sed -n '/owner-identities/,/)/p' "$CONF" | grep -oE '"[^"]+@[^"]+"' | tr -d '"')"
[ -n "$owners" ] || fail "OWNER-CONFIRMATIONS.lisp declares no owner identities"

is_owner() {
  local who="$1" o
  for o in $owners; do [ "$who" = "$o" ] && return 0; done
  return 1
}

confirmed_ids="$(grep -oE '\(confirmed "[^"]+"' "$CONF" | sed 's/.*"\(.*\)"/\1/' || true)"

checked=0
problems=0

cd "$ROOT_DIR"
for adr in docs/ADR-*.md; do
  [ -f "$adr" ] || continue
  line_no="$(grep -n '\*\*Status/Статус\*\*: \*\*ACCEPTED\*\*' "$adr" | head -1 | cut -d: -f1 || true)"
  [ -n "$line_no" ] || continue
  checked=$((checked + 1))

  # An ADR with named deciders is a decision; one without them is a blog post.
  deciders="$(grep -E '^\*\*(Deciders|Хто вирішив)' "$adr" | head -1 || true)"
  if ! printf '%s' "$deciders" | grep -qE ': *[^ *]'; then
    problems=$((problems + 1))
    printf '  %s: ACCEPTED but names no decider — add a "**Deciders/Хто вирішив**: <name>" line\n' "$adr" >&2
  fi

  blame="$(git blame --porcelain -L "${line_no},${line_no}" -- "$adr" 2>/dev/null || true)"
  [ -n "$blame" ] || fail "$adr: cannot blame the status line (workflow needs full history)"
  mail="$(printf '%s\n' "$blame" | sed -n 's/^author-mail <\(.*\)>$/\1/p' | head -1)"
  sha="$(printf '%s\n' "$blame" | head -1 | awk '{print substr($1,1,12)}')"

  if is_owner "$mail"; then
    note "$adr: ACCEPTED by owner identity ($mail, $sha)"
    continue
  fi

  adr_id="$(basename "$adr" | grep -oE '^ADR-[0-9]+' || true)"
  if printf '%s\n' "$confirmed_ids" | grep -Fxq "$adr_id"; then
    conf_line="$(grep -n "(confirmed \"$adr_id\"" "$CONF" | head -1 | cut -d: -f1)"
    conf_mail="$(git blame --porcelain -L "${conf_line},${conf_line}" -- "$CONF" 2>/dev/null | sed -n 's/^author-mail <\(.*\)>$/\1/p' | head -1)"
    if is_owner "$conf_mail"; then
      note "$adr: ACCEPTED, confirmed in OWNER-CONFIRMATIONS.lisp by owner identity"
      continue
    fi
    problems=$((problems + 1))
    printf '  %s: confirmation line exists but was added by <%s>, not the owner\n' "$adr_id" "$conf_mail" >&2
    continue
  fi

  problems=$((problems + 1))
  printf '  %s: ACCEPTED by <%s> in %s, and no owner confirmation on record\n' "$adr" "$mail" "$sha" >&2
done

if [ "$problems" -ne 0 ]; then
  printf '%s\n' "" >&2
  printf 'An ADR marked ACCEPTED without the owner is an agent ratifying architecture.\n' >&2
  printf 'Fix, either way, in an owner-authored commit:\n' >&2
  printf '  * confirm: add (confirmed "ADR-00N" "YYYY-MM-DD" "what was confirmed") to\n' >&2
  printf '    docs/decisions/OWNER-CONFIRMATIONS.lisp, or\n' >&2
  printf '  * reverse: move the ADR back to PROPOSED and restore the superseded one.\n' >&2
  fail "$problems ADR(s) claim a decision the owner did not sign"
fi

[ "$checked" -gt 0 ] || fail "no ACCEPTED ADR found; the gate would pass vacuously"
note "$checked ACCEPTED ADR(s) checked"
