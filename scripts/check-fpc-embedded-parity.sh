#!/usr/bin/env bash
# ADR-006 W3: embedded-target parity and compile/build/boot cycle measurement.
# Four cells: ASM/Pascal x value/named OOM. No FPC PROGRAM startup or RTL stubs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
OUT="${WSM_P2_OUT_DIR:-target/fpc-embedded-parity}"
REPEATS="${WSM_P2_REPEATS:-3}"
BASE="$ROOT_DIR/target/fpc-embedded-probe"
COMPILER="$BASE/install/bin/x86_64-linux/ppcrossx64"
RTL_DIR="$BASE/install/units/x86_64-embedded/rtl"

VALUE_PIN_ASM="artifacts/qemu-serial-transcript.txt"
VALUE_PIN_PASCAL="artifacts/nucleus-witness-pascal-entry-qemu-serial-transcript.txt"
OOM_PIN="artifacts/nucleus-witness-alloc-oom-fixture-qemu-serial-transcript.txt"

fail() { printf 'FPC-EMBEDDED-PARITY-FAIL: %s\n' "$1" >&2; exit 1; }
now_ms() { python3 -c 'import time; print(int(time.monotonic()*1000))'; }

[[ -x "$COMPILER" ]] || fail "pinned embedded compiler missing; run probe-fpc-embedded.sh first"
[[ -d "$RTL_DIR" ]] || fail "embedded RTL missing"
for pin in "$VALUE_PIN_ASM" "$VALUE_PIN_PASCAL" "$OOM_PIN"; do
  [[ -s "$pin" ]] || fail "missing transcript pin: $pin"
done
cmp -s "$VALUE_PIN_ASM" "$VALUE_PIN_PASCAL" \
  || fail "canonical value pins diverged; Pascal pin must equal ASM baseline"
mkdir -p "$OUT/units" "$OUT/bin"
{
  echo "captured_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "--- uname ---"
  uname -a
  echo "--- os-release ---"
  [[ ! -f /etc/os-release ]] || cat /etc/os-release
  echo "--- cpu ---"
  grep -m1 -E 'model name|Hardware' /proc/cpuinfo || true
  echo "logical_cpus=$(nproc 2>/dev/null || echo unknown)"
  if command -v lscpu >/dev/null 2>&1; then lscpu; fi
  echo "--- memory ---"
  if command -v free >/dev/null 2>&1; then free -h; fi
  echo "--- qemu ---"
  qemu-system-x86_64 --version | head -1
  echo "--- fpc ---"
  "$COMPILER" -iV
} > "$OUT/host-profile.txt"
rm -f "$OUT/compile.tsv" "$OUT/cycle.tsv"
: > "$OUT/compile.tsv"
: > "$OUT/cycle.tsv"
sha256sum "$VALUE_PIN_ASM" "$VALUE_PIN_PASCAL" "$OOM_PIN" > "$OUT/transcript-pins.sha256"
echo "PIN_IDENTITY=PASS"

build_asm() {
  local source="$1" output="$2" t0 t1
  t0=$(now_ms)
  as --64 "$source" -o "$output" || fail "assemble $source"
  t1=$(now_ms)
  printf '%s' "$((t1-t0))"
}
build_pascal() {
  local source="$1" stem="$2" t0 t1 object="$OUT/units/$2.o" undefined
  t0=$(now_ms)
  "$COMPILER" -Tembedded -Px86_64 -n -Fu"$RTL_DIR" \
    -FU"$OUT/units" -FE"$OUT/bin" -Cn -O- -al "$source" \
    > "$OUT/$stem-compile.txt" 2>&1 || {
      cat "$OUT/$stem-compile.txt" >&2
      fail "FPC embedded compile: $source"
    }
  t1=$(now_ms)
  [[ -s "$object" ]] || fail "missing Pascal object: $object"
  nm -u "$object" > "$OUT/$stem-undefined-symbols.txt" 2>&1 || true
  undefined="$(awk '{print $2}' "$OUT/$stem-undefined-symbols.txt" | tr '\n' ' ')"
  [[ "$undefined" == "wsm_cons " ]] || {
    cat "$OUT/$stem-undefined-symbols.txt" >&2
    fail "unexpected FPC runtime imports in $stem; only wsm_cons is allowed"
  }
  printf '%s' "$((t1-t0))"
}

run_cell() {
  local substrate="$1" scenario="$2" object="$3" pin="$4" repeat="$5"
  local image="$OUT/$substrate-$scenario-$repeat.img"
  local log="$OUT/$substrate-$scenario-$repeat.serial.log"
  local t0 t1 t2 build_ms boot_ms
  t0=$(now_ms)
  bash scripts/build-uefi-image.sh "$object" "$image" > "$OUT/$substrate-$scenario-$repeat-build.txt" \
    || fail "image build: $substrate/$scenario"
  t1=$(now_ms)
  build_ms=$((t1-t0))

  if [[ "$substrate" == "pascal" ]]; then
    nm -u target/kernel-x86_64 > "$OUT/$substrate-$scenario-$repeat-kernel-undefined.txt" 2>&1 || true
    [[ ! -s "$OUT/$substrate-$scenario-$repeat-kernel-undefined.txt" ]] \
      || fail "undefined symbols in final Pascal kernel: $scenario"
  fi

  WSM_QEMU_TRANSCRIPT="$ROOT_DIR/$pin" \
  WSM_QEMU_RAW_SERIAL_COPY="$log" \
    timeout 90s bash scripts/run-qemu-uefi.sh "$image" \
      > "$OUT/$substrate-$scenario-$repeat-qemu.stdout" \
      2> "$OUT/$substrate-$scenario-$repeat-qemu.stderr" \
      || fail "QEMU/transcript: $substrate/$scenario"
  t2=$(now_ms)
  boot_ms=$((t2-t1))
  sha256sum "$image" > "$OUT/$substrate-$scenario-$repeat-image.sha256"

  printf '%s\t%s\t%s\t%s\n' "$substrate" "$scenario" "$build_ms" "$boot_ms" >> "$OUT/cycle.tsv"
  printf 'CELL %-6s %-5s build=%5sms boot=%5sms  %s\n' \
    "$substrate" "$scenario" "$build_ms" "$boot_ms" \
    "$(tr -d '\r' < "$log" | grep '^WSM-OS ' | tail -1)"
}

median() {
  awk -v col="$1" -v substrate="$2" -F'\t' '$1==substrate {print $col}' "$OUT/compile.tsv" \
    | sort -n | awk '{a[NR]=$1} END {if (NR) print (NR%2) ? a[(NR+1)/2] : int((a[NR/2]+a[NR/2+1])/2)}'
}
median_cycle() {
  awk -v col="$1" -v substrate="$2" -F'\t' '$1==substrate {print $col}' "$OUT/cycle.tsv" \
    | sort -n | awk '{a[NR]=$1} END {if (NR) print (NR%2) ? a[(NR+1)/2] : int((a[NR/2]+a[NR/2+1])/2)}'
}

for repeat in $(seq 1 "$REPEATS"); do
  asm_value="$OUT/asm-value-$repeat.o"
  asm_oom="$OUT/asm-oom-$repeat.o"
  t=$(build_asm artifacts/fixture.s "$asm_value")
  printf 'asm\tvalue\t%s\n' "$t" >> "$OUT/compile.tsv"
  t=$(build_asm artifacts/nucleus-witness-alloc-oom-fixture.s "$asm_oom")
  printf 'asm\toom\t%s\n' "$t" >> "$OUT/compile.tsv"

  t=$(build_pascal src/pascal_probe.pas pascal_probe)
  pas_value="$OUT/units/pascal_probe.o"
  printf 'pascal\tvalue\t%s\n' "$t" >> "$OUT/compile.tsv"
  t=$(build_pascal src/pascal_probe_oom.pas pascal_probe_oom)
  pas_oom="$OUT/units/pascal_probe_oom.o"
  printf 'pascal\toom\t%s\n' "$t" >> "$OUT/compile.tsv"

  run_cell asm value "$asm_value" "$VALUE_PIN_ASM" "$repeat"
  run_cell asm oom "$asm_oom" "$OOM_PIN" "$repeat"
  run_cell pascal value "$pas_value" "$VALUE_PIN_PASCAL" "$repeat"
  run_cell pascal oom "$pas_oom" "$OOM_PIN" "$repeat"

  for scenario in value oom; do
    asm_lines="$(tr -d '\r' < "$OUT/asm-$scenario-$repeat.serial.log" | grep '^WSM-OS ')"
    pascal_lines="$(tr -d '\r' < "$OUT/pascal-$scenario-$repeat.serial.log" | grep '^WSM-OS ')"
    [[ "$asm_lines" == "$pascal_lines" ]] || fail "ASM/Pascal transcript parity failed: $scenario"
  done
done

echo "SUBSTRATE_PARITY=PASS"
echo "P2_EMBEDDED_PARITY=PASS: 4/4 cells per repeat"
printf 'COMPILE asm    median %sms\n' "$(median 3 asm)"
printf 'COMPILE pascal median %sms\n' "$(median 3 pascal)"
printf 'CYCLE   asm    build %sms boot %sms\n' "$(median_cycle 3 asm)" "$(median_cycle 4 asm)"
printf 'CYCLE   pascal build %sms boot %sms\n' "$(median_cycle 3 pascal)" "$(median_cycle 4 pascal)"
echo "NOTE: GitHub-hosted TCG/QEMU timings are CI datapoints, not the user's i5-6400 measurement."
