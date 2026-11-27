#!/usr/bin/env bash
# P1 test-only witness: the embedded Pascal UNIT reads BootInfo itself,
# compares with the independent Assembly reading, and fails closed on defects.
# No FPC program startup or no-op RTL stubs are linked.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE="$ROOT/target/fpc-embedded-probe"
OUT="$ROOT/target/fpc-embedded-pascal-handoff"
COMPILER="$BASE/install/bin/x86_64-linux/ppcrossx64"
RTL_DIR="$BASE/install/units/x86_64-embedded/rtl"
OBJ="$OUT/units/pascal_handoff.o"
FIXTURE="$OUT/pascal-handoff-fixture.o"

fail() {
  printf 'FPC-EMBEDDED-PASCAL-HANDOFF-FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$COMPILER" ]] || fail "pinned embedded compiler missing"
[[ -d "$RTL_DIR" ]] || fail "embedded RTL missing"
rm -rf "$OUT"
mkdir -p "$OUT/units" "$OUT/bin"

"$COMPILER" -Tembedded -Px86_64 -n -Fu"$RTL_DIR" \
  -FU"$OUT/units" -FE"$OUT/bin" -Cn -O- -al \
  src/pascal_handoff.pas > "$OUT/compile.txt" 2>&1 \
  || { cat "$OUT/compile.txt" >&2; fail "embedded handoff unit compile failed"; }

[[ -s "$OBJ" ]] || fail "pascal_handoff.o missing"
file "$OBJ" > "$OUT/object-format.txt"
nm -g "$OBJ" > "$OUT/object-global-symbols.txt"
nm -u "$OBJ" > "$OUT/object-undefined-symbols.txt" 2>&1 || true
actual_undefined="$(awk '{print $2}' "$OUT/object-undefined-symbols.txt" | sort | tr '\n' ' ')"
expected_undefined="$(printf '%s\n' 'RTTI_$SYSTEM_$$_BYTE$indirect' saved_boot_info wsm_cons wsm_fail_src wsm_target_phys_mem_offset | sort | tr '\n' ' ')"
[[ "$actual_undefined" == "$expected_undefined" ]] || {
  cat "$OUT/object-undefined-symbols.txt" >&2
  fail "unexpected handoff unit imports"
}

for symbol in saved_boot_info wsm_target_phys_mem_offset wsm_cons wsm_fail_src; do
  grep -Fq "$symbol" "$OUT/object-undefined-symbols.txt" \
    || fail "expected Assembly boundary symbol missing: $symbol"
done
for forbidden in fpc_initializeunits fpc_do_exit INIT\$_\$SYSTEM FINALIZE\$_\$OBJPAS THREADVARLIST; do
  if grep -Fq "$forbidden" "$OUT/object-undefined-symbols.txt"; then
    fail "Pascal UNIT unexpectedly depends on PROGRAM startup hook: $forbidden"
  fi
done

echo "EMBEDDED_HANDOFF_UNIT_COMPILE=PASS"
echo "HANDOFF_EXTERNALS=saved_boot_info,wsm_target_phys_mem_offset,wsm_cons,wsm_fail_src"

run_cell() {
  # Apply the same section-GC profile to valid and negative cells; this only drops unused Byte RTTI.
  local cell="$1"
  local transcript="$2"
  local env_name="$3"
  local image="$OUT/$cell.img"
  local log="$OUT/$cell.serial.log"

  local -a build_env=(WSM_OS_LINK_GC_SECTIONS=1)
  if [[ -n "$env_name" ]]; then
    build_env+=("$env_name=1")
  fi
  env "${build_env[@]}" timeout 180s bash scripts/build-uefi-image.sh "$OBJ" "$image" > "$OUT/$cell-build.txt" \
    || fail "image build failed: $cell"

  nm -u target/kernel-x86_64 > "$OUT/$cell-kernel-undefined.txt" 2>&1 || true
  [[ ! -s "$OUT/$cell-kernel-undefined.txt" ]] || {
    cat "$OUT/$cell-kernel-undefined.txt" >&2
    fail "undefined symbols in final kernel: $cell"
  }

  WSM_QEMU_TRANSCRIPT="$ROOT/$transcript" \
  WSM_QEMU_RAW_SERIAL_COPY="$log" \
    timeout 90s bash scripts/run-qemu-uefi.sh "$image" > "$OUT/$cell-qemu.stdout" 2> "$OUT/$cell-qemu.stderr" \
    || {
      cat "$OUT/$cell-qemu.stdout" "$OUT/$cell-qemu.stderr" >&2
      [[ ! -f "$log" ]] || cat "$log" >&2
      fail "QEMU transcript mismatch or boot failure: $cell"
    }

  printf 'PASS %-11s %s\n' "$cell" \
    "$(tr -d '\r' < "$log" | grep '^WSM-OS ' | tail -1)"
}

run_cell valid artifacts/nucleus-witness-pascal-handoff-fixture-qemu-serial-transcript.txt ""
run_cell missing artifacts/nucleus-witness-pascal-handoff-missing-fixture-qemu-serial-transcript.txt WSM_FORCE_NO_BOOT_INFO
run_cell badtag artifacts/nucleus-witness-pascal-handoff-badtag-fixture-qemu-serial-transcript.txt WSM_FORCE_BAD_BOOT_INFO_TAG
run_cell zerooffset artifacts/nucleus-witness-pascal-handoff-zerooffset-fixture-qemu-serial-transcript.txt WSM_FORCE_ZERO_BOOT_INFO_OFFSET

echo "FPC-EMBEDDED-PASCAL-HANDOFF-PASS: 4/4 valid/missing/badtag/zerooffset"
