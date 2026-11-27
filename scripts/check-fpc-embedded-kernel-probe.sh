#!/usr/bin/env bash
# Test-only UEFI/QEMU witness: FPC embedded UNIT, no Pascal program startup
# and no RTL stubs. Production runtime/entry remain Assembly-owned.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

BASE="$ROOT/target/fpc-embedded-probe"
OUT="$ROOT/target/fpc-embedded-kernel-probe"
COMPILER="$BASE/install/bin/x86_64-linux/ppcrossx64"
RTL_DIR="$BASE/install/units/x86_64-embedded/rtl"
UNIT_SOURCE="$ROOT/tests/fpc_embedded_kernel_probe.pas"
OBJ="$OUT/units/fpc_embedded_kernel_probe.o"
IMAGE="$OUT/fpc-embedded-kernel.img"
KERNEL="$ROOT/target/kernel-x86_64"
TRANSCRIPT="$OUT/fpc-embedded-serial.log"

fail() {
  echo "FPC-EMBEDDED-KERNEL-FAIL: $1" >&2
  exit 1
}

[[ -x "$COMPILER" ]] || fail "pinned embedded compiler missing: $COMPILER"
[[ -d "$RTL_DIR" ]] || fail "embedded RTL directory missing: $RTL_DIR"
[[ -s "$ROOT/artifacts/qemu-serial-transcript.txt" ]] || fail "assembly transcript missing"
mkdir -p "$OUT/units" "$OUT/bin"

"$COMPILER" -Tembedded -Px86_64 -n -Fu"$RTL_DIR" \
  -FU"$OUT/units" -FE"$OUT/bin" -Cn -O- -al \
  "$UNIT_SOURCE" > "$OUT/compile.txt" 2>&1 || {
    cat "$OUT/compile.txt" >&2
    fail "embedded Pascal unit compile failed"
  }
[[ -s "$OBJ" ]] || fail "compiler produced no object"
file "$OBJ" > "$OUT/object-format.txt"
nm -g "$OBJ" > "$OUT/object-global-symbols.txt"
nm -u "$OBJ" > "$OUT/object-undefined-symbols.txt" 2>&1 || true

undefined="$(awk '{print $2}' "$OUT/object-undefined-symbols.txt" | sed '/^$/d')"
[[ "$undefined" == "wsm_cons" ]] || {
  echo "unexpected object undefined symbols:" >&2
  cat "$OUT/object-undefined-symbols.txt" >&2
  fail "expected only the existing Assembly runtime symbol wsm_cons"
}
grep -Fq 'wsm_entry' "$OUT/object-global-symbols.txt" || fail "wsm_entry export missing"

echo "FPC_EMBEDDED_UNIT_COMPILE=PASS"
echo "OBJECT_UNDEFINED_SYMBOLS=wsm_cons (provided by src/runtime.s)"

timeout 180s bash scripts/build-uefi-image.sh "$OBJ" "$IMAGE" > "$OUT/image-build.txt" \
  || fail "UEFI image build failed"
[[ -s "$IMAGE" && -s "$KERNEL" ]] || fail "image or kernel missing"
nm -u "$KERNEL" > "$OUT/kernel-undefined-symbols.txt" 2>&1 || true
if [ -s "$OUT/kernel-undefined-symbols.txt" ]; then
  cat "$OUT/kernel-undefined-symbols.txt" >&2
  fail "final kernel contains undefined symbols"
fi
file "$KERNEL" > "$OUT/kernel-format.txt"
size "$KERNEL" > "$OUT/kernel-size.txt"
sha256sum "$KERNEL" "$IMAGE" > "$OUT/image-sha256.txt"
echo "FREESTANDING_LINK=PASS"
echo "FINAL_KERNEL_UNDEFINED_SYMBOLS=NONE"

WSM_QEMU_TRANSCRIPT="$ROOT/artifacts/qemu-serial-transcript.txt" \
WSM_QEMU_RAW_SERIAL_COPY="$TRANSCRIPT" \
  timeout 90s bash scripts/run-qemu-uefi.sh "$IMAGE" > "$OUT/qemu.stdout" 2> "$OUT/qemu.stderr" \
  || {
    cat "$OUT/qemu.stdout" "$OUT/qemu.stderr" >&2
    [ ! -f "$TRANSCRIPT" ] || cat "$TRANSCRIPT" >&2
    fail "UEFI/QEMU witness failed"
  }

grep -Fq 'WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok' "$TRANSCRIPT" \
  || fail "expected result line missing from raw serial"
echo "UEFI_QEMU_BOOT=PASS"
echo "FPC-EMBEDDED-KERNEL-PROBE-PASS"
