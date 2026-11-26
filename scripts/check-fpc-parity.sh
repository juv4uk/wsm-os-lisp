#!/usr/bin/env bash
# ADR-006 P2 gate: parity matrix plus the iteration measurement.
#
# Two substrates (assembly, Pascal) x two scenarios (a value, a named failure).
# All four cells must produce the transcript pinned for their scenario, and the
# two substrates must agree with each other, not merely with themselves.
#
# The same run records the number the FPC decision never had: how long a change
# costs on each substrate. It is split on purpose, because lumping it together
# hides where the time actually goes:
#
#   COMPILE  as --64 / ppcx64 -Cn            (the language's own cost)
#   BUILD    image assembly (sgdisk, mkfs, mcopy, dd)  - identical for both
#   BOOT     QEMU boot + transcript verify   - identical for both
#
# Numbers are local and single-machine, reported with the commands that
# produced them. They are a datapoint, never a benchmark of Pascal vs assembly.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

out_dir="${WSM_P2_OUT_DIR:-target/fpc-parity}"
repeats="${WSM_P2_REPEATS:-1}"
expected_version="${WSM_FPC_VERSION:-3.2.2}"

value_transcript="artifacts/nucleus-witness-pascal-entry-qemu-serial-transcript.txt"
oom_transcript="artifacts/nucleus-witness-alloc-oom-fixture-qemu-serial-transcript.txt"

fail() {
  printf 'FPC-PARITY-FAIL: %s\n' "$1" >&2
  exit 1
}

now_ms() { python3 -c 'import time; print(int(time.monotonic()*1000))'; }

ppc="${FPC_PPCX64:-}"
[[ -z "$ppc" ]] && ppc="$(command -v ppcx64 || true)"
if [[ -z "$ppc" ]]; then
  for candidate in /usr/lib/x86_64-linux-gnu/fpc/*/ppcx64 /usr/lib/fpc/*/ppcx64; do
    [[ -x "$candidate" ]] && ppc="$candidate" && break
  done
fi
[[ -n "$ppc" && -x "$ppc" ]] || fail "ppcx64 not found; install fp-compiler or set FPC_PPCX64"
[[ "$("$ppc" -iV | tr -d '\r')" == "$expected_version" ]] \
  || fail "FPC version drift: expected $expected_version"

units_dir="${FPC_UNITS_DIR:-}"
if [[ -z "$units_dir" ]]; then
  for candidate in /usr/lib/x86_64-linux-gnu/fpc/*/units/x86_64-linux \
                   /usr/lib/fpc/*/units/x86_64-linux; do
    [[ -d "$candidate/rtl" ]] && units_dir="$candidate" && break
  done
fi
[[ -n "$units_dir" && -d "$units_dir/rtl" ]] || fail "FPC rtl units not found"

rm -rf "$out_dir"
mkdir -p "$out_dir"
as --64 src/rtl_min.s -o "$out_dir/rtl_min.o" || fail "rtl_min.s assemble failed"

: > "$out_dir/cycle.tsv"
: > "$out_dir/compile.tsv"

# --- builders: print "<object path> TAB <compile ms>" ----------------------
build_asm_fixture() {   # $1 = .s source, $2 = output object
  local t0 t1
  t0=$(now_ms)
  as --64 "$1" -o "$2" || fail "assemble $1"
  t1=$(now_ms)
  printf '%s\t%s' "$2" "$((t1 - t0))"
}

build_pascal_fixture() { # $1 = .pas source, $2 = stem
  local stem="$2" t0 t1
  t0=$(now_ms)
  "$ppc" -Tlinux -O- -Xs- -CX -Cn \
    -Fu"$units_dir/rtl" -Fu"$units_dir/rtl-objpas" \
    -FE"$out_dir" -FU"$out_dir" "$1" >/dev/null || fail "FPC compile $1"
  t1=$(now_ms)
  [[ -s "$out_dir/$stem.o" ]] || fail "FPC produced no object for $1"
  ld -r "$out_dir/$stem.o" "$out_dir/rtl_min.o" -o "$out_dir/${stem}_fixture.o" \
    || fail "relocatable merge $1"
  printf '%s\t%s' "$out_dir/${stem}_fixture.o" "$((t1 - t0))"
}

# --- one cell: image, boot, compare ---------------------------------------
run_cell() {            # $1 = substrate, $2 = scenario, $3 = object, $4 = transcript
  local substrate="$1" scenario="$2" obj="$3" transcript="$4"
  local img="$out_dir/${substrate}_${scenario}.img"
  local log="$out_dir/${substrate}_${scenario}.log"

  local t0 t1 t2 build_ms boot_ms
  t0=$(now_ms)
  bash scripts/build-uefi-image.sh "$obj" "$img" >/dev/null || fail "image ${substrate}/${scenario}"
  t1=$(now_ms)
  build_ms=$((t1 - t0))

  WSM_QEMU_TRANSCRIPT="$transcript" \
  WSM_QEMU_RAW_SERIAL_COPY="$log" \
    bash scripts/run-qemu-uefi.sh "$img" >/dev/null || fail "qemu ${substrate}/${scenario}"
  t2=$(now_ms)
  boot_ms=$((t2 - t1))

  if [[ "$substrate" == "pascal" ]]; then
    [[ -z "$(nm -u target/kernel-x86_64)" ]] || fail "undefined symbols in ${substrate}/${scenario}"
  fi

  printf 'CELL %-6s %-5s build=%5sms boot=%5sms  %s\n' \
    "$substrate" "$scenario" "$build_ms" "$boot_ms" \
    "$(tr -d '\r' < "$log" | grep '^WSM-OS ' | tail -1)"
  printf '%s\t%s\t%s\t%s\n' "$substrate" "$scenario" "$build_ms" "$boot_ms" \
    >> "$out_dir/cycle.tsv"
}

for _ in $(seq 1 "$repeats"); do
  IFS=$'\t' read -r asm_value asm_value_ms <<< "$(build_asm_fixture artifacts/fixture.s "$out_dir/asm_value.o")"
  IFS=$'\t' read -r asm_oom asm_oom_ms <<< "$(build_asm_fixture artifacts/nucleus-witness-alloc-oom-fixture.s "$out_dir/asm_oom.o")"
  IFS=$'\t' read -r pas_value pas_value_ms <<< "$(build_pascal_fixture src/pascal_probe.pas pascal_probe)"
  IFS=$'\t' read -r pas_oom pas_oom_ms <<< "$(build_pascal_fixture src/pascal_probe_oom.pas pascal_probe_oom)"

  printf 'asm\t%s\nasm\t%s\npascal\t%s\npascal\t%s\n' \
    "$asm_value_ms" "$asm_oom_ms" "$pas_value_ms" "$pas_oom_ms" >> "$out_dir/compile.tsv"

  run_cell asm    value "$asm_value" "$value_transcript"
  run_cell asm    oom   "$asm_oom"   "$oom_transcript"
  run_cell pascal value "$pas_value" "$value_transcript"
  run_cell pascal oom   "$pas_oom"   "$oom_transcript"
done

# --- the two substrates must agree with each other, not just with the pin --
for scenario in value oom; do
  asm_line=$(tr -d '\r' < "$out_dir/asm_${scenario}.log" | grep '^WSM-OS ' | tail -1)
  pas_line=$(tr -d '\r' < "$out_dir/pascal_${scenario}.log" | grep '^WSM-OS ' | tail -1)
  [[ "$asm_line" == "$pas_line" ]] \
    || fail "substrates disagree on ${scenario}: asm='${asm_line}' pascal='${pas_line}'"
done

median() { # column $1 of cycle.tsv for substrate $2
  awk -v c="$1" -v s="$2" -F'\t' '$1==s {print $c}' "$out_dir/cycle.tsv" \
    | sort -n | awk '{a[NR]=$1} END {print (NR%2) ? a[(NR+1)/2] : int((a[NR/2]+a[NR/2+1])/2)}'
}

compile_median() { # substrate
  awk -v s="$1" -F'\t' '$1==s {print $2}' "$out_dir/compile.tsv" \
    | sort -n | awk '{a[NR]=$1} END {print (NR%2) ? a[(NR+1)/2] : int((a[NR/2]+a[NR/2+1])/2)}'
}

echo "FPC-PARITY-PASS: 4/4 cells; asm and Pascal agree on both scenarios"
printf 'COMPILE asm    median %4sms  (as --64)\n' "$(compile_median asm)"
printf 'COMPILE pascal median %4sms  (ppcx64 -Cn)\n' "$(compile_median pascal)"
printf 'CYCLE   asm    build %4sms  boot %5sms\n' "$(median 3 asm)" "$(median 4 asm)"
printf 'CYCLE   pascal build %4sms  boot %5sms\n' "$(median 3 pascal)" "$(median 4 pascal)"
echo "NOTE: local single-machine measurement (TCG QEMU, ${repeats} repeat(s)); image build and boot are shared overhead."
