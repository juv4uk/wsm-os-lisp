#!/usr/bin/env bash
# Measure the local gate suite: how long does "did my change break an invariant?" take.
#
# This is not the full iteration cycle. It excludes everything that needs QEMU,
# the UEFI image builder (sgdisk/mtools) or the FPC toolchain, because those are
# not available in every environment that runs this script. What it measures is
# the cheap part of the loop — the static gates that catch most regressions —
# and it is labelled that way everywhere the number appears.
#
# Method follows wsm-lazarus/docs/chas-iteratsii.uk.md: warm and cold separated,
# N runs, publish median and p90 rather than the mean, keep the raw samples, and
# never compare the number with one from another machine or repository.
#
# Usage: bash scripts/measure-gate-suite.sh [runs]   (default 20)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-20}"
out_dir="${WSM_MEASURE_OUT:-target/gate-suite-measurement}"

case "$runs" in
  ''|*[!0-9]*) printf 'usage: measure-gate-suite.sh [runs]\n' >&2; exit 2 ;;
esac
[ "$runs" -ge 5 ] || { printf 'need at least 5 runs; one run is not a sample\n' >&2; exit 2; }

mkdir -p "$out_dir"
raw="$out_dir/samples.tsv"
: > "$raw"

# Gates that need no network, no QEMU and no toolchain beyond bash/python3.
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

now_ns() { date +%s%N; }

run_once() { # <label> <run-index>
  local label="$1" idx="$2" gate start end elapsed
  for gate in "${shell_gates[@]}"; do
    start="$(now_ns)"
    bash "$ROOT_DIR/scripts/$gate" >/dev/null 2>&1
    end="$(now_ns)"
    elapsed=$(( (end - start) / 1000000 ))
    printf '%s\t%s\t%s\t%d\n' "$idx" "$label" "$gate" "$elapsed" >> "$raw"
  done
  for gate in "${python_gates[@]}"; do
    start="$(now_ns)"
    python3 "$ROOT_DIR/scripts/$gate" >/dev/null 2>&1
    end="$(now_ns)"
    elapsed=$(( (end - start) / 1000000 ))
    printf '%s\t%s\t%s\t%d\n' "$idx" "$label" "$gate" "$elapsed" >> "$raw"
  done
}

# Suite total per run, measured as one wall-clock span around all gates.
suite="$out_dir/suite.tsv"
: > "$suite"

printf 'measuring %s runs of %s gates on %s cores\n' \
  "$runs" "$(( ${#shell_gates[@]} + ${#python_gates[@]} ))" "$(nproc)" >&2

for i in $(seq 1 "$runs"); do
  label="warm"
  [ "$i" -eq 1 ] && label="cold"
  start="$(now_ns)"
  run_once "$label" "$i"
  end="$(now_ns)"
  printf '%s\t%s\t%d\n' "$i" "$label" $(( (end - start) / 1000000 )) >> "$suite"
done

# --- summary --------------------------------------------------------------
python3 - "$raw" "$suite" <<'PY'
import statistics, sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text().strip().splitlines()
suite = Path(sys.argv[2]).read_text().strip().splitlines()

def rows(lines, warm_only=True):
    out = []
    for line in lines:
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        label = parts[1]
        if warm_only and label == "cold":
            continue
        out.append(parts)
    return out

def p90(values):
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    idx = min(len(values) - 1, int(round(0.9 * (len(values) - 1))))
    return values[idx]

print("gate\tmedian_ms\tp90_ms\tn")
per_gate = {}
for parts in rows(raw):
    per_gate.setdefault(parts[2], []).append(int(parts[3]))
for gate in sorted(per_gate):
    vals = per_gate[gate]
    print(f"{gate}\t{statistics.median(vals):.0f}\t{p90(vals)}\t{len(vals)}")

totals = [int(p[2]) for p in rows(suite)]
cold = [int(p[2]) for p in suite if p[1] == "cold"]
print()
print(f"suite_warm\tmedian={statistics.median(totals):.0f}\tp90={p90(totals)}\tn={len(totals)}")
if cold:
    print(f"suite_cold\tfirst_run={cold[0]}\tn=1 (not a sample)")
PY

printf '\nraw samples: %s\n' "$raw"
