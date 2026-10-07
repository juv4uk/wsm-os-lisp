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

# Optional test-only assembler flags. WSM_OS_FORCE_NO_PHYS_MAP=1 injects the
# `WSM_FORCE_NO_PHYS_MAP` symbol consumed by src/runtime.s::wsm_boot_handoff to
# witness the fail-closed MMIO path (issue #40). Production builds define none.
as_extra=()
if [[ "${WSM_OS_FORCE_NO_PHYS_MAP:-0}" == "1" ]]; then
  as_extra+=(--defsym WSM_FORCE_NO_PHYS_MAP=1)
fi

# Assemble pure machine runtime and entry
as --64 "${as_extra[@]}" "$ROOT_DIR/src/entry.s" -o "$BUILD_DIR/entry.o"
as --64 "${as_extra[@]}" "$ROOT_DIR/src/runtime.s" -o "$BUILD_DIR/runtime.o"

# Link freestanding kernel ELF
ld -m elf_x86_64 -T "$ROOT_DIR/src/linker.ld" \
  "$BUILD_DIR/entry.o" \
  "$BUILD_DIR/runtime.o" \
  "$FIXTURE_OBJ" \
  -o "$BUILD_DIR/kernel-x86_64.elf"
cp "$BUILD_DIR/kernel-x86_64.elf" "$ROOT_DIR/target/kernel-x86_64"

# Build a reproducible GPT/FAT boot image.
#
# GPT GUIDs are pinned test-image identities rather than generated UUIDs.
# FAT uses mkfs.fat's invariant mode, and the staged directory tree has a fixed
# representable FAT timestamp. This makes repeated builds deterministic in all
# fields we own; the M0/M1 witness still canonicalizes GPT as an independent
# guard against accidental reintroduction of GUID variance.
DISK_GUID="57534d4f-5300-4d30-8000-000000000001"
ESP_GUID="57534d4f-5300-4d30-8000-000000000002"
FAT_TIMESTAMP="198001010000.00"

rm -f "$OUTPUT_IMG"
truncate -s 8M "$OUTPUT_IMG"
sgdisk \
  -n 1:2048:14335 \
  -t 1:ef00 \
  -c 1:"EFI System" \
  -U "$DISK_GUID" \
  -u 1:"$ESP_GUID" \
  "$OUTPUT_IMG" >/dev/null

dd if=/dev/zero of="$BUILD_DIR/part.fat" bs=512 count=12288 status=none
mkfs.vfat --invariant -F 12 "$BUILD_DIR/part.fat" >/dev/null

fat_root="$BUILD_DIR/fat-root"
mkdir -p "$fat_root/EFI/BOOT"
cp "$ROOT_DIR/artifacts/bootx64.efi" "$fat_root/EFI/BOOT/BOOTX64.EFI"
cp "$BUILD_DIR/kernel-x86_64.elf" "$fat_root/kernel-x86_64"

# FAT timestamps have 2-second granularity and a 1980 epoch. Pin every staged
# directory/file before mcopy and preserve the modification timestamp.
find "$fat_root" -exec touch -t "$FAT_TIMESTAMP" {} +
mcopy -s -m -i "$BUILD_DIR/part.fat" \
  "$fat_root/EFI" \
  "$fat_root/kernel-x86_64" \
  ::

dd if="$BUILD_DIR/part.fat" of="$OUTPUT_IMG" bs=512 seek=2048 conv=notrunc status=none

echo "$OUTPUT_IMG"
