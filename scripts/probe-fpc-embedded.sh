#!/usr/bin/env bash
# Research-only FPC x86_64-embedded probe. A green result proves this bounded
# compile/link and static ABI-codegen slice, not full RTL or UEFI acceptance.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="${WSM_FPC_EMBEDDED_OUT:-$ROOT/target/fpc-embedded-probe}"
ARCHIVE_NAME="fpc-3.3.1.x86_64-embedded.built.on.x86_64-linux.tar.gz"
BASE_URL="https://downloads.freepascal.org/fpc/snapshot/trunk/x86_64-embedded"
ARCHIVE_URL="$BASE_URL/$ARCHIVE_NAME"
README_URL="$BASE_URL/README-fpc-3.3.1.x86_64-embedded.built.on.x86_64-linux"
EXPECTED_SOURCE_COMMIT="2e77266e1eafbc802fcb93f59eab356eb588263d"
EXPECTED_ARCHIVE_SHA256="a3e9e0a01c06b28acee6aca51c9d7a2980d965ac5180e8f53700fd2e000182a7"
EXPECTED_COMPILER_VERSION="3.3.1-22061-g2e77266e1e"

mkdir -p "$OUT/install" "$OUT/units" "$OUT/bin"
cd "$ROOT"
exec > >(tee "$OUT/probe.log") 2>&1

echo "FPC_EMBEDDED_PROBE=START"
echo "ARCHIVE_URL=$ARCHIVE_URL"
echo "EXPECTED_SOURCE_COMMIT=$EXPECTED_SOURCE_COMMIT"
echo "P0_ACCEPTANCE=NOT_ESTABLISHED"

timeout 180s curl --fail --location --retry 3 --retry-delay 2 \
  "$ARCHIVE_URL" -o "$OUT/$ARCHIVE_NAME"
ACTUAL_ARCHIVE_SHA256=$(sha256sum "$OUT/$ARCHIVE_NAME" | awk '{print $1}')
echo "$ACTUAL_ARCHIVE_SHA256  $ARCHIVE_NAME" | tee "$OUT/archive.sha256"
[[ "$ACTUAL_ARCHIVE_SHA256" == "$EXPECTED_ARCHIVE_SHA256" ]] || {
  echo "PROBE_FATAL=archive_checksum_mismatch"
  exit 4
}
stat -c 'ARCHIVE_BYTES=%s' "$OUT/$ARCHIVE_NAME" | tee "$OUT/archive.size"
echo "ARCHIVE_CHECKSUM=PASS"

timeout 60s curl --fail --location --retry 2 \
  "$README_URL" -o "$OUT/upstream-readme.txt"
grep -Fq "$EXPECTED_SOURCE_COMMIT" "$OUT/upstream-readme.txt" || {
  echo "PROBE_FATAL=source_commit_mismatch"
  exit 5
}
grep -Fq "$EXPECTED_COMPILER_VERSION" "$OUT/upstream-readme.txt" || {
  echo "PROBE_FATAL=compiler_version_mismatch"
  exit 6
}
echo "SOURCE_COMMIT_CHECK=PASS"
echo "COMPILER_VERSION_PIN=PASS"

tar -xzf "$OUT/$ARCHIVE_NAME" -C "$OUT/install"
tar -tzf "$OUT/$ARCHIVE_NAME" > "$OUT/archive-contents.txt"
COMPILER=$(find "$OUT/install" -type f \( -name ppcrossx64 -o -name ppcx64 \) -print -quit)
[[ -n "$COMPILER" ]] || {
  find "$OUT/install" -maxdepth 5 -type f | sort > "$OUT/install-files.txt"
  echo "PROBE_FATAL=compiler_binary_not_found"
  exit 7
}
chmod +x "$COMPILER"
echo "COMPILER_PATH=$COMPILER"
"$COMPILER" -iVDW 2>&1 | tee "$OUT/compiler-version.txt"
RTL_DIR=$(find "$OUT/install" -type f -name system.ppu -print -quit | xargs -r dirname)
[[ -n "$RTL_DIR" ]] || {
  find "$OUT/install" -type f -name '*.ppu' | head -200 > "$OUT/ppu-files.txt"
  echo "PROBE_FATAL=embedded_system_ppu_not_found"
  exit 8
}
echo "EMBEDDED_RTL_DIR=$RTL_DIR"

"$COMPILER" -Tembedded -Px86_64 -n -Fu"$RTL_DIR" \
  -FU"$OUT/units" -FE"$OUT/bin" -Cn -O- -al \
  "$ROOT/tests/fpc_embedded_probe.pas" > "$OUT/compile.txt" 2>&1
OBJ="$OUT/units/fpc_embedded_probe.o"
[[ -s "$OBJ" ]] || {
  echo "PROBE_FATAL=object_missing"
  exit 9
}
file "$OBJ" | tee "$OUT/object-format.txt"
nm -g "$OBJ" > "$OUT/object-global-symbols.txt"
nm -u "$OBJ" > "$OUT/object-undefined-symbols.txt" 2>&1 || true
objdump -h "$OBJ" > "$OUT/object-sections.txt"
objdump -r "$OBJ" > "$OUT/object-relocations.txt"
size "$OBJ" > "$OUT/object-size.txt"
echo "EMBEDDED_COMPILE=PASS"

FPC_ASM="$OUT/units/fpc_embedded_probe.s"
[[ -s "$FPC_ASM" ]] || {
  echo "PROBE_FATAL=generated_assembly_missing"
  exit 10
}
cp "$FPC_ASM" "$OUT/fpc-generated-assembly.s"
require_abi_pattern() {
  local pattern="$1"
  if ! grep -Eq "$pattern" "$FPC_ASM"; then
    echo "MS_ABI_PATTERN_MISSING=$pattern"
    exit 12
  fi
}
require_abi_pattern 'movq[[:space:]]+[$]4,%r9'
require_abi_pattern 'movq[[:space:]]+[$]3,%r8'
require_abi_pattern 'movq[[:space:]]+[$]2,%rdx'
require_abi_pattern 'movq[[:space:]]+[$]1,%rcx'
require_abi_pattern 'call[[:space:]]+[*]'
require_abi_pattern 'movq[[:space:]]+%rcx,-8[(]%rbp[)]'
require_abi_pattern 'movq[[:space:]]+%rdx,-16[(]%rbp[)]'
require_abi_pattern 'leaq[[:space:]]+-80[(]%rsp[)],%rsp'
echo "MS_ABI_DISASSEMBLY=PASS"

as --64 "$ROOT/tests/fpc_embedded_entry.s" -o "$OUT/units/fpc_embedded_entry.o"
ld --gc-sections -T "$ROOT/src/linker.ld" -Map="$OUT/embedded-link.map" \
  -o "$OUT/embedded-link.elf" "$OUT/units/fpc_embedded_entry.o" "$OBJ"
file "$OUT/embedded-link.elf" > "$OUT/final-format.txt"
nm -u "$OUT/embedded-link.elf" > "$OUT/final-undefined-symbols.txt" 2>&1 || true
nm -g "$OUT/embedded-link.elf" > "$OUT/final-global-symbols.txt"
objdump -d "$OUT/embedded-link.elf" > "$OUT/final-disassembly.txt"
size "$OUT/embedded-link.elf" > "$OUT/final-size.txt"
[[ ! -s "$OUT/final-undefined-symbols.txt" ]] || {
  cat "$OUT/final-undefined-symbols.txt"
  echo "PROBE_FATAL=final_undefined_symbols"
  exit 13
}
echo "FREESTANDING_LINK=PASS"
echo "FINAL_UNDEFINED_SYMBOLS=NONE"
echo "QEMU_WITNESS=DEFERRED_TO_KERNEL_PROBE"
echo "P0_ACCEPTANCE=NOT_ESTABLISHED"
echo "FPC_EMBEDDED_PROBE=PASS"
