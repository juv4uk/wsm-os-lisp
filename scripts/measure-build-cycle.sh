#!/usr/bin/env bash
# Measure the mechanism build cycle: assemble + link, nothing else.
#
# This is the second tier of the iteration-time measurement. Tier one
# (measure-gate-suite.sh) answers "did I break an invariant?". This one answers
# "does my change to src/ still build?", and it is the step that a language change
# would actually move: an FPC object plus its RTL against our linker.
#
# Scope, stated because the number is worthless without it:
#   included:  as src/entry.s, as src/runtime.s, ld -T src/linker.ld
#   excluded:  CML lowering of the fixture (needs the pinned toolchain), the UEFI
#              image (needs sgdisk/mtools), QEMU
# So this is not the full cycle either. It is the compile+link core of it, which
# is the part a substrate swap changes first.
#
# Method follows wsm-lazarus/docs/chas-iteratsii.uk.md: cold and warm separated,
# N runs, median and p90 rather than the mean, raw samples kept, and no comparison
# with a number from another machine.
#
# Usage: bash scripts/measure-build-cycle.sh [runs]   (default 20)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-20}"
out_dir="${WSM_MEASURE_OUT:-target/build-cycle-measurement}"
fixture="${WSM_FIXTURE_OBJ:-$ROOT_DIR/artifacts/fixture.o}"

case "$runs" in
  ''|*[!0-9]*) printf 'usage: measure-build-cycle.sh [runs]\n' >&2; exit 2 ;;
esac
[ "$runs" -ge 5 ] || { printf 'need at least 5 runs; one run is not a sample\n' >&2; exit 2; }
[ -s "$fixture" ] || { printf 'fixture object %s is missing\n' "$fixture" >&2; exit 2; }

command -v as >/dev/null || { printf 'as not found\n' >&2; exit 2; }
command -v ld >/dev/null || { printf 'ld not found\n' >&2; exit 2; }

mkdir -p "$out_dir"
raw="$out_dir/samples.tsv"
: > "$raw"

now_ns() { date +%s%N; }

one_run() { # <label> <index> <workdir>
  local label="$1" idx="$2" work="$3" start end

  start="$(now_ns)"
  as --64 "$ROOT_DIR/src/entry.s" -o "$work/entry.o"
  end="$(now_ns)"
  printf '%s\t%s\tas-entry\t%d\n' "$idx" "$label" $(( (end - start) / 1000000 )) >> "$raw"

  start="$(now_ns)"
  as --64 "$ROOT_DIR/src/runtime.s" -o "$work/runtime.o"
  end="$(now_ns)"
  printf '%s\t%s\tas-runtime\t%d\n' "$idx" "$label" $(( (end - start) / 1000000 )) >> "$raw"

  start="$(now_ns)"
  ld -m elf_x86_64 -T "$ROOT_DIR/src/linker.ld" \
    "$work/entry.o" "$work/runtime.o" "$fixture" -o "$work/kernel.elf"
  end="$(now_ns)"
  printf '%s\t%s\tld-kernel\t%d\n' "$idx" "$label" $(( (end - start) / 1000000 )) >> "$raw"
}

printf 'measuring %s runs of assemble+link on %s cores\n' "$runs" "$(nproc)" >&2

for i in $(seq 1 "$runs"); do
  work="$(mktemp -d)"
  label="warm"
  [ "$i" -eq 1 ] && label="cold"
  one_run "$label" "$i" "$work"
  rm -rf "$work"
done

python3 - "$raw" <<'PY'
import statistics, sys
from pathlib import Path

rows = [l.split("\t") for l in Path(sys.argv[1]).read_text().strip().splitlines() if l.count("\t") == 3]

def p90(vals):
    vals = sorted(vals)
    return vals[min(len(vals) - 1, int(round(0.9 * (len(vals) - 1))))]

warm = {}
cold = {}
for idx, label, step, ms in rows:
    target = cold if label == "cold" else warm
    target.setdefault(step, []).append(int(ms))

print("step\tmedian_ms\tp90_ms\tn")
for step in ("as-entry", "as-runtime", "ld-kernel"):
    vals = warm.get(step, [])
    if vals:
        print(f"{step}\t{statistics.median(vals):.0f}\t{p90(vals)}\t{len(vals)}")

per_run = {}
for idx, label, step, ms in rows:
    if label == "cold":
        continue
    per_run.setdefault(idx, 0)
    per_run[idx] += int(ms)

if per_run:
    totals = list(per_run.values())
    print()
    print(f"cycle_warm\tmedian={statistics.median(totals):.0f}\tp90={p90(totals)}\tn={len(totals)}")

cold_total = sum(int(ms) for idx, label, step, ms in rows if label == "cold")
print(f"cycle_cold\tfirst_run={cold_total}\tn=1 (not a sample)")
PY

printf '\nraw samples: %s\n' "$raw"
