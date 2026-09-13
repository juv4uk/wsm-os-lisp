#!/usr/bin/env bash
set -euo pipefail

# Pure freestanding builder for wsm-os-lisp (Zero-Rust target per ADR-004)
# Usage: ./scripts/build-uefi-image.sh [fixture_obj] [output_img]

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_OBJ="${1:-$ROOT_DIR/artifacts/fixture.o}"
OUTPUT_IMG="${2:-$ROOT_DIR/target/wsm-os-uefi.img}"

mkdir -p "$ROOT_DIR/target"
BUILD_DIR=$(mktemp -d /tmp/wsm-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT

# Assemble pure machine runtime and entry
as --64 "$ROOT_DIR/src/entry.s" -o "$BUILD_DIR/entry.o"
as --64 "$ROOT_DIR/src/runtime.s" -o "$BUILD_DIR/runtime.o"

# Link freestanding kernel ELF
ld -m elf_x86_64 -T "$ROOT_DIR/src/linker.ld" \
  "$BUILD_DIR/entry.o" \
  "$BUILD_DIR/runtime.o" \
  "$FIXTURE_OBJ" \
  -o "$BUILD_DIR/kernel-x86_64.elf"
cp "$BUILD_DIR/kernel-x86_64.elf" "$ROOT_DIR/target/kernel-x86_64"


# Create UEFI GPT disk image with FAT12/16 partition
rm -f "$OUTPUT_IMG"
truncate -s 8M "$OUTPUT_IMG"
sgdisk -n 1:2048:14335 -t 1:ef00 -c 1:"EFI System" "$OUTPUT_IMG" >/dev/null

dd if=/dev/zero of="$BUILD_DIR/part.fat" bs=512 count=12288 status=none
mkfs.vfat -F 12 "$BUILD_DIR/part.fat" >/dev/null
mmd -i "$BUILD_DIR/part.fat" ::efi ::efi/boot
mcopy -i "$BUILD_DIR/part.fat" "$ROOT_DIR/artifacts/bootx64.efi" ::efi/boot/bootx64.efi
mcopy -i "$BUILD_DIR/part.fat" "$BUILD_DIR/kernel-x86_64.elf" ::kernel-x86_64
dd if="$BUILD_DIR/part.fat" of="$OUTPUT_IMG" bs=512 seek=2048 conv=notrunc status=none

echo "$OUTPUT_IMG"
