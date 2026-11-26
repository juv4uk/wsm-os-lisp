#!/usr/bin/env bash
# Regression tests for the same-commit documentation gate.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/check-docs-in-change.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo"

test_count=0

new_repo() {
  rm -rf "$repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Docs Gate Test"
  git -C "$repo" config user.email "docs-gate@example.invalid"
  mkdir -p "$repo/src" "$repo/docs" "$repo/scripts"
  printf 'baseline\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "baseline"
  BASE="$(git -C "$repo" rev-parse HEAD)"
}

write_and_commit() {
  local path="$1" contents="$2" subject="$3" body="${4:-}"
  mkdir -p "$repo/$(dirname "$path")"
  printf '%s\n' "$contents" > "$repo/$path"
  git -C "$repo" add "$path"
  if [ -n "$body" ]; then
    git -C "$repo" commit -q -m "$subject" -m "$body"
  else
    git -C "$repo" commit -q -m "$subject"
  fi
}

expect_pass() {
  local label="$1" base="$2" head="$3"
  if (cd "$repo" && bash "$checker" "$base" "$head" > "$tmp/out" 2> "$tmp/err"); then
    printf 'PASS: %s\n' "$label"
    test_count=$((test_count + 1))
  else
    cat "$tmp/out" "$tmp/err" >&2
    printf 'FAIL: %s (expected pass)\n' "$label" >&2
    exit 1
  fi
}

expect_fail() {
  local label="$1" base="$2" head="$3"
  if (cd "$repo" && bash "$checker" "$base" "$head" > "$tmp/out" 2> "$tmp/err"); then
    cat "$tmp/out" >&2
    printf 'FAIL: %s (expected failure)\n' "$label" >&2
    exit 1
  else
    printf 'PASS: %s\n' "$label"
    test_count=$((test_count + 1))
  fi
}

# 1. Code + docs in the same commit passes.
new_repo
mkdir -p "$repo/src" "$repo/docs"
printf 'program one;\n' > "$repo/src/one.pas"
printf 'one docs\n' > "$repo/docs/one.md"
git -C "$repo" add src/one.pas docs/one.md
git -C "$repo" commit -q -m "code and docs together"
expect_pass "code and docs in the same commit" "$BASE" "$(git -C "$repo" rev-parse HEAD)"

# 2. A single code-only commit fails.
new_repo
write_and_commit src/one.pas 'program one;' 'code only'
expect_fail "single code-only commit" "$BASE" "$(git -C "$repo" rev-parse HEAD)"

# 3. Code-only followed by docs-only in one push range fails.
new_repo
write_and_commit src/one.pas 'program one;' 'code only'
write_and_commit docs/one.md 'one' 'docs later'
expect_fail "later docs commit cannot excuse code commit" "$BASE" "$(git -C "$repo" rev-parse HEAD)"

# 4. A reasoned exception in the code commit itself passes.
new_repo
write_and_commit src/generated.pas 'generated' 'generated artifact' 'DOCS-NOT-REQUIRED: generated from a pinned schema'
expect_pass "reasoned marker in the same commit" "$BASE" "$(git -C "$repo" rev-parse HEAD)"

# 5. A marker in another commit cannot excuse a previous code-only commit.
new_repo
write_and_commit src/one.pas 'program one;' 'code only'
write_and_commit docs/one.md 'one' 'documentation exception' 'DOCS-NOT-REQUIRED: unrelated docs commit'
expect_fail "marker in another commit cannot excuse code-only commit" "$BASE" "$(git -C "$repo" rev-parse HEAD)"

# 6. Empty marker is rejected.
new_repo
write_and_commit src/one.pas 'program one;' 'code only' 'DOCS-NOT-REQUIRED:'
expect_fail "empty marker reason" "$BASE" "$(git -C "$repo" rev-parse HEAD)"

# 7. Docs-only commit passes.
new_repo
write_and_commit docs/one.md 'one' 'documentation only'
expect_pass "docs-only commit" "$BASE" "$(git -C "$repo" rev-parse HEAD)"

# 8. Empty range passes.
new_repo
expect_pass "empty range" "$BASE" "$BASE"

# 9. Commits on a merged side branch are checked individually.
new_repo
branch_base="$BASE"
git -C "$repo" checkout -q -b feature
write_and_commit src/feature.pas 'feature code' 'code-only feature commit'
write_and_commit docs/feature.md 'feature docs' 'later documentation commit'
git -C "$repo" checkout -q -b integration "$branch_base"
git -C "$repo" merge -q --no-ff feature -m "merge feature"
expect_fail "merge history still checks commits on side branch" "$branch_base" "$(git -C "$repo" rev-parse HEAD)"

# 10. A valid merge with code + docs in one side-branch commit passes.
new_repo
branch_base="$BASE"
git -C "$repo" checkout -q -b feature
mkdir -p "$repo/src" "$repo/docs"
printf 'feature\n' > "$repo/src/feature.pas"
printf 'feature docs\n' > "$repo/docs/feature.md"
git -C "$repo" add src/feature.pas docs/feature.md
git -C "$repo" commit -q -m "feature code and docs"
git -C "$repo" checkout -q -b integration "$branch_base"
git -C "$repo" merge -q --no-ff feature -m "merge valid feature"
expect_pass "valid merge commit" "$branch_base" "$(git -C "$repo" rev-parse HEAD)"

# 11. A squash-style integrated commit with code + docs passes.
new_repo
mkdir -p "$repo/src" "$repo/docs"
printf 'squashed\n' > "$repo/src/squashed.pas"
printf 'squashed docs\n' > "$repo/docs/squashed.md"
git -C "$repo" add src/squashed.pas docs/squashed.md
git -C "$repo" commit -q -m "squashed code and docs"
expect_pass "squash commit contains code and docs" "$BASE" "$(git -C "$repo" rev-parse HEAD)"

printf 'DOCS-IN-CHANGE-TESTS-PASS: %s scenarios\n' "$test_count"
