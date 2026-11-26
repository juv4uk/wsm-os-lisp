#!/usr/bin/env bash
# Gate-suite budget: the static gates must stay inside a wall-clock ceiling.
#
# Why a ceiling and not just a published number: a hook or gate developers wait on
# gets skipped, and skipping it is a security decision made by fatigue rather than
# by judgement. Practice in the field puts the commit-path budget under three
# seconds, with attention leaving the terminal somewhere above ten. The measured
# suite is ~2.9 s on a 2-vCPU container, so the ceiling here is deliberately
# generous — it is not a target, it is a tripwire for a tenfold regression, and it
# must not fail on a slow shared runner.
#
# One run is enough for a tripwire. Publishing a number requires the median of at
# least twenty (scripts/measure-gate-suite.sh); catching a regression that made the
# suite ten times slower does not.
#
# Usage: bash scripts/check-gate-budget.sh [max_seconds]   (default 10)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ceiling="${1:-10}"

case "$ceiling" in
  ''|*[!0-9]*) printf 'usage: check-gate-budget.sh [max_seconds]\n' >&2; exit 2 ;;
esac

shell_gates=(
  check-role-authority.sh
  check-semantic-authority.sh
  check-no-rust.sh
  check-shell-safety.sh
  check-task-dag.sh
  check-build-variance.sh
)
python_gates=(
  check-policy-enforcement.py
  check-task-format.py
)

cd "$ROOT_DIR"
start="$(date +%s%N)"
for gate in "${shell_gates[@]}"; do
  bash "scripts/$gate" >/dev/null 2>&1 || { printf 'GATE-BUDGET-FAIL: %s failed; a broken gate is not a fast gate\n' "$gate" >&2; exit 1; }
done
for gate in "${python_gates[@]}"; do
  python3 "scripts/$gate" >/dev/null 2>&1 || { printf 'GATE-BUDGET-FAIL: %s failed; a broken gate is not a fast gate\n' "$gate" >&2; exit 1; }
done
end="$(date +%s%N)"
elapsed_ms=$(( (end - start) / 1000000 ))
ceiling_ms=$(( ceiling * 1000 ))

if [ "$elapsed_ms" -gt "$ceiling_ms" ]; then
  printf 'GATE-BUDGET-FAIL: the static gate suite took %d ms, above the %d s ceiling.\n' \
    "$elapsed_ms" "$ceiling" >&2
  printf 'Profile it before raising the ceiling: the last two offenders scaled with the repository\n' >&2
  printf 'instead of with the change (a full-tree walk per pattern, workflow files re-read per call).\n' >&2
  printf 'See docs/research/ITERATION-TIME-GATE-SUITE-2026-11-27.md.\n' >&2
  exit 1
fi

printf 'GATE-BUDGET-PASS: %d ms for 8 gates, ceiling %d s.\n' "$elapsed_ms" "$ceiling"
