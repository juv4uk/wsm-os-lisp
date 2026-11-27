#!/usr/bin/env bash
# Test-only UEFI/QEMU witness: FPC embedded UNIT, no Pascal program startup
# and no no-op RTL stubs. Production runtime/entry remain Assembly-owned.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

BASE="$ROOT/target/fpc-embedded-probe"
OUT="$ROOT/target/fpc-embedded-kernel-probe"
COMPILER="$BASE/install/bin/x86_64-linux/ppcrossx64"
RTL_DIR="$BASE/install/units/x86_64-embedded/rtl"
UNIT_SOURCE="$ROOT/tests/fpc_embedded_kernel_probe.pas"
ABI_STUB="$ROOT/tests/fpc_embedded_efi_abi_stub.s"
OBJ="$OUT/units/fpc_embedded_kernel_probe.o"
STUB_OBJ="$OUT/units/fpc_embedded_efi_abi_stub.o"
FIXTURE_OBJ="$OUT/units/fpc_embedded_fixture.o"
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

as --64 "$ABI_STUB" -o "$STUB_OBJ" > "$OUT/abi-stub-assembly.txt" 2>&1 \
  || fail "Microsoft x64 ABI stub assembly failed"
ld -r "$OBJ" "$STUB_OBJ" -o "$FIXTURE_OBJ" > "$OUT/fixture-merge.txt" 2>&1 \
  || fail "Pascal/ABI fixture relocatable merge failed"
nm -g "$FIXTURE_OBJ" > "$OUT/fixture-global-symbols.txt"
nm -u "$FIXTURE_OBJ" > "$OUT/fixture-undefined-symbols.txt" 2>&1 || true

undefined="$(awk '{print $2}' "$OUT/fixture-undefined-symbols.txt" | sort | tr '\n' ' ')"
expected="$(printf '%s\n' 'RTTI_$SYSTEM_$$_QWORD$indirect' 'wsm_cons' | sort | tr '\n' ' ')"
[[ "$undefined" == "$expected" ]] || {
  echo "unexpected fixture undefined symbols:" >&2
  cat "$OUT/fixture-undefined-symbols.txt" >&2
  fail "only unused procedural RTTI metadata and existing Assembly runtime wsm_cons may remain before final GC link"
}
grep -Fq 'wsm_entry' "$OUT/fixture-global-symbols.txt" || fail "wsm_entry export missing"
grep -Fq 'wsm_efi_callback' "$OUT/fixture-global-symbols.txt" || fail "MS ABI Pascal callback missing"
grep -Fq 'wsm_efi_msabi_stub' "$OUT/fixture-global-symbols.txt" || fail "MS ABI function-pointer target missing"

echo "FPC_EMBEDDED_UNIT_COMPILE=PASS"
echo "MS_ABI_FUNCTION_POINTER_AND_CALLBACK_FIXTURE=LINKED"
echo "PRELINK_UNDEFINED=unused_procedural_RTTI,wsm_cons"

WSM_OS_LINK_GC_SECTIONS=1 timeout 180s bash scripts/build-uefi-image.sh "$FIXTURE_OBJ" "$IMAGE" > "$OUT/image-build.txt" \
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
    fail "UEFI/QEMU witness failed (this also fails the MS ABI callback assertions)"
  }

grep -Fq 'WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok' "$TRANSCRIPT" \
  || fail "expected result line missing; MS ABI function pointer/callback assertion did not complete"
echo "UEFI_QEMU_BOOT=PASS"
echo "MS_ABI_FUNCTION_POINTER=PASS"
echo "MS_ABI_CALLBACK=PASS"
echo "MS_ABI_SHADOW_SPACE_ALIGNMENT_CALLEE_SAVED=PASS"
echo "FPC-EMBEDDED-KERNEL-PROBE-PASS"
