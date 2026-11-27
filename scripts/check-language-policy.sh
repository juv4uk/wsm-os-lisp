#!/usr/bin/env bash
set -euo pipefail

# Open language policy + exact upstream source pin.
# Adapted from the pin-consistency pattern in juv4uk/wsm-lazarus/scripts/check-pin.sh.
fail() { printf 'LANGUAGE-POLICY-FAIL: %s\n' "$1" >&2; exit 1; }

policy="docs/ADR-009-OPEN-LANGUAGE-AND-CODE-REUSE.md"
manifest="refs/wsm-lazarus-pin.lisp"
[[ -s "$policy" ]] || fail "missing $policy"
[[ -s "$manifest" ]] || fail "missing $manifest"
grep -Fq "No blanket language bans" "$policy" || fail "open language policy statement missing"
grep -Fq "(production-languages unrestricted)" repo.lisp || fail "repo.lisp still has a language allowlist"

if grep -Eq 'RUST[[:space:]]*=[[:space:]]*0|Rust[^\n]*заборонено|Rust[^\n]*forbidden' AGENTS.md; then
  fail "active agent instructions still contain a Rust/language ban"
fi

expected_pin=$(sed -nE 's/.*\(commit[[:space:]]+\.[[:space:]]+"([0-9a-f]{40})"\).*/\1/p' "$manifest" | head -n1)
[[ "$expected_pin" =~ ^[0-9a-f]{40}$ ]] || fail "invalid Lazarus pin in $manifest"

read -r gitlink_mode gitlink_type actual_pin gitlink_path < <(git ls-tree HEAD external/wsm-lazarus)
[[ "$gitlink_mode" == "160000" && "$gitlink_type" == "commit" ]] || fail "external/wsm-lazarus is not a gitlink"
[[ "$gitlink_path" == "external/wsm-lazarus" ]] || fail "gitlink path mismatch"
[[ "$actual_pin" == "$expected_pin" ]] || fail "gitlink/manifest pin mismatch"

configured_url=$(git config -f .gitmodules --get submodule.wsm-lazarus.url || true)
[[ "$configured_url" == "https://github.com/juv4uk/wsm-lazarus.git" ]] || fail "wrong or missing .gitmodules URL"

printf 'LANGUAGE-POLICY-PASS: unrestricted languages; wsm-lazarus=%s\n' "$expected_pin"
