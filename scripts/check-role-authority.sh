#!/usr/bin/env bash
set -euo pipefail

repo_my="repo.my"
readme="README.md"
adr1="docs/ADR-001-COMPILER-FIRST.md"
adr3="docs/ADR-003-RUST-LISP-MECHANISM-POLICY.md"

fail() {
  printf 'ROLE-AUTHORITY-FAIL: %s\n' "$1" >&2
  exit 1
}

require_literal() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "$file is missing required authority statement: $text"
}

forbid_literal() {
  local file="$1"
  local text="$2"
  if grep -Fq -- "$text" "$file"; then
    fail "$file contains forbidden stale authority statement: $text"
  fi
}

# repo.my is the machine-readable authority root for this repository.
require_literal "$repo_my" "(role my-lisp-bare-metal-control-target)"
require_literal "$repo_my" "(authorities target-abi boot-runtime boot-image qemu-execution-evidence physical-parity-ledger)"
require_literal "$repo_my" "(non-authorities language-semantics cml-ir fpga-isa cuda-runtime physical-platform-research)"

# Human-facing docs must agree with repo.my and distinguish the later clean-slate lab.
require_literal "$readme" '`wsm-os-lisp` owns this lineage'
require_literal "$readme" '`wsm-os` owns separate physical-platform research'
forbid_literal "$readme" '`wsm-os` owns boot, platform services, and bare-metal integration evidence.'

# ADR-001 predates the repo rename, so it must carry the explicit historical-name binding.
require_literal "$adr1" 'Post-rename authority note (2026-09-11)'
require_literal "$adr1" 'today'
require_literal "$adr1" '`wsm-os-lisp`'
require_literal "$adr1" '`juv4uk/wsm-os` repository is a separate physical-platform research lab'

# ADR-003 is current mechanism policy and must name the present control target explicitly.
require_literal "$adr3" 'Repository-role amendment / Уточнення ролі репозиторію (2026-09-11)'
require_literal "$adr3" 'This mechanism-policy split anchors to existing `wsm-os-lisp` foundations'
require_literal "$adr3" 'new physical-platform research itself belongs'

# Semantic authority must remain upstream. Catch the most dangerous accidental grant
# even if someone edits the exact formatting of the authorities list later.
if grep -E '^\s*\(authorities[^)]*(language-semantics|cml-ir)' "$repo_my" >/dev/null; then
  fail "repo.my grants language/compiler semantic authority to wsm-os-lisp"
fi

printf '%s\n' 'ROLE-AUTHORITY-PASS: wsm-os-lisp remains the my-lisp bare-metal control target; wsm-os remains the separate physical-platform lab.'
