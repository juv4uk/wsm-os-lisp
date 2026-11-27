#!/usr/bin/env bash
# Research-only FPC x86_64-embedded probe. A green workflow means the probe
# collected evidence; it does NOT mean P0/UEFI acceptance passed.
set -u
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

if ! command -v curl >/dev/null 2>&1; then echo "PROBE_FATAL=curl_missing"; exit 2; fi
if ! command -v tar >/dev/null 2>&1; then echo "PROBE_FATAL=tar_missing"; exit 2; fi

if ! timeout 180s curl --fail --location --retry 3 --retry-delay 2 "$ARCHIVE_URL" -o "$OUT/$ARCHIVE_NAME"; then
  echo "PROBE_FATAL=archive_download_failed"; exit 3
fi
sha256sum "$OUT/$ARCHIVE_NAME" | tee "$OUT/archive.sha256"
ACTUAL_ARCHIVE_SHA256=$(sha256sum "$OUT/$ARCHIVE_NAME" | cut -d " " -f1)
if [ "$ACTUAL_ARCHIVE_SHA256" != "$EXPECTED_ARCHIVE_SHA256" ]; then
  echo "PROBE_FATAL=archive_checksum_mismatch"
  exit 4
fi
echo "ARCHIVE_CHECKSUM=PASS"
stat -c 'ARCHIVE_BYTES=%s' "$OUT/$ARCHIVE_NAME" | tee "$OUT/archive.size"

if ! timeout 60s curl --fail --location --retry 2 "$README_URL" -o "$OUT/upstream-readme.txt"; then
  echo "PROBE_FATAL=upstream_readme_download_failed"; exit 4
fi
if ! grep -Fq "$EXPECTED_SOURCE_COMMIT" "$OUT/upstream-readme.txt"; then
  echo "PROBE_FATAL=source_commit_mismatch"; exit 5
fi
if ! grep -Fq "$EXPECTED_COMPILER_VERSION" "$OUT/upstream-readme.txt"; then
  echo "PROBE_FATAL=compiler_version_mismatch"
  exit 5
fi
echo "SOURCE_COMMIT_CHECK=PASS"
echo "COMPILER_VERSION_PIN=PASS"

if ! tar -xzf "$OUT/$ARCHIVE_NAME" -C "$OUT/install"; then
  echo "PROBE_FATAL=archive_extract_failed"; exit 6
fi
tar -tzf "$OUT/$ARCHIVE_NAME" > "$OUT/archive-contents.txt"

COMPILER=$(find "$OUT/install" -type f \( -name ppcrossx64 -o -name ppcx64 \) -print -quit)
if [ -z "$COMPILER" ]; then
  echo "PROBE_FATAL=compiler_binary_not_found"
  find "$OUT/install" -maxdepth 5 -type f | sort > "$OUT/install-files.txt"
  exit 7
fi
chmod +x "$COMPILER"
echo "COMPILER_PATH=$COMPILER"
"$COMPILER" -iVDW 2>&1 | tee "$OUT/compiler-version.txt"
VERSION_RC=${PIPESTATUS[0]}
echo "COMPILER_VERSION_EXIT=$VERSION_RC"

RTL_DIR=$(find "$OUT/install" -type f -name system.ppu -print -quit | xargs -r dirname)
if [ -z "$RTL_DIR" ]; then
  echo "PROBE_FATAL=embedded_system_ppu_not_found"
  find "$OUT/install" -type f -name '*.ppu' | head -200 > "$OUT/ppu-files.txt"
  exit 8
fi
echo "EMBEDDED_RTL_DIR=$RTL_DIR"

set +e
"$COMPILER" -Tembedded -Px86_64 -n -Fu"$RTL_DIR" -FU"$OUT/units" -FE"$OUT/bin" -Cn -O- -al "$ROOT/tests/fpc_embedded_probe.pas" > "$OUT/compile.txt" 2>&1
COMPILE_RC=$?
set -e
echo "COMPILE_EXIT=$COMPILE_RC"
cat "$OUT/compile.txt"

OBJ="$OUT/units/fpc_embedded_probe.o"
if [ -f "$OBJ" ]; then
  file "$OBJ" | tee "$OUT/object-format.txt"
  nm -g "$OBJ" > "$OUT/object-global-symbols.txt" 2>&1 || true
  nm -u "$OBJ" > "$OUT/object-undefined-symbols.txt" 2>&1 || true
  objdump -h "$OBJ" > "$OUT/object-sections.txt" 2>&1 || true
  objdump -r "$OBJ" > "$OUT/object-relocations.txt" 2>&1 || true
  size "$OBJ" > "$OUT/object-size.txt" 2>&1 || true
  echo "OBJECT_PRESENT=yes"
else
  echo "OBJECT_PRESENT=no"
fi

if [ "$COMPILE_RC" -eq 0 ] && [ -f "$OBJ" ]; then
  as --64 -o "$OUT/units/fpc_embedded_entry.o" "$ROOT/tests/fpc_embedded_entry.s" > "$OUT/assembly.txt" 2>&1
  AS_RC=$?
  echo "ASSEMBLY_EXIT=$AS_RC"
  cat "$OUT/assembly.txt"
  if [ "$AS_RC" -eq 0 ]; then
    set +e
    ld -T "$ROOT/src/linker.ld" -Map="$OUT/embedded-link.map" \
      -o "$OUT/embedded-link.elf" "$OUT/units/fpc_embedded_entry.o" "$OBJ" > "$OUT/link.txt" 2>&1
    LINK_RC=$?
    set -e
    echo "LINK_EXIT=$LINK_RC"
    cat "$OUT/link.txt"
    if [ -f "$OUT/embedded-link.elf" ]; then
      file "$OUT/embedded-link.elf" > "$OUT/final-format.txt"
      nm -u "$OUT/embedded-link.elf" > "$OUT/final-undefined-symbols.txt" 2>&1 || true
      nm -g "$OUT/embedded-link.elf" > "$OUT/final-global-symbols.txt" 2>&1 || true
      objdump -d "$OUT/embedded-link.elf" > "$OUT/final-disassembly.txt" 2>&1 || true
      size "$OUT/embedded-link.elf" > "$OUT/final-size.txt" 2>&1 || true
    fi
  fi
else
  echo "LINK_STATUS=SKIPPED_COMPILE_FAILED"
fi

echo "QEMU_WITNESS=NOT_ATTEMPTED"
echo "P0_ACCEPTANCE=NOT_ESTABLISHED"
echo "FPC_EMBEDDED_PROBE=EVIDENCE_COLLECTED"
