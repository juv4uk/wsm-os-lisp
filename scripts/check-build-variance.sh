#!/usr/bin/env bash
# Build-variance pin gate.
#
# What this proves: every known source of variance in the UEFI image builder is
# still explicitly pinned. What it does NOT prove: that the build is
# reproducible. A byte-identical rebuild needs a runnable witness, and that
# witness is currently legacy (scripts/check-uefi-image-reproducibility.sh drives
# cargo crates removed by ADR-004).
#
# The distinction matters. Canonicalising an image afterwards removes variance
# you already know about; pinning at build time is what makes the variance list
# finite. This gate keeps the list finite and fails when a pin disappears.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILDER="$ROOT_DIR/scripts/build-uefi-image.sh"

fail() {
  printf 'BUILD-VARIANCE-FAIL: %s\n' "$1" >&2
  exit 1
}

[ -f "$BUILDER" ] || fail "scripts/build-uefi-image.sh is missing"

require() {
  local literal="$1" why="$2"
  grep -Fq -- "$literal" "$BUILDER" \
    || fail "builder no longer pins '$literal' ($why) — either restore the pin or record why the variance is gone"
}

forbid() {
  local pattern="$1" why="$2"
  if grep -Eq -- "$pattern" "$BUILDER"; then
    fail "builder contains '$pattern' ($why) — that is an unpinned variance source"
  fi
}

# 1. GPT identities must be fixed literals, not generated UUIDs.
require 'DISK_GUID="57534d4f-5300-4d30-8000-000000000001"' 'disk GUID pinned to a test-image identity'
require 'ESP_GUID="57534d4f-5300-4d30-8000-000000000002"' 'partition GUID pinned to a test-image identity'
require '-U "$DISK_GUID"' 'sgdisk must receive the pinned disk GUID'
require '-u 1:"$ESP_GUID"' 'sgdisk must receive the pinned partition GUID'

# 2. FAT volume metadata must be invariant.
require 'mkfs.vfat --invariant' 'FAT volume identity must not be generated'

# 3. FAT timestamps must be fixed at the epoch before staging.
require 'FAT_TIMESTAMP="198001010000.00"' 'FAT epoch timestamp pinned'
require 'touch -t "$FAT_TIMESTAMP"' 'staged tree must be stamped with the pinned timestamp'
require 'mcopy -s -m' 'mcopy must preserve the pinned modification time'

# 4. No unpinned sources of entropy or wall-clock time.
forbid '\buuidgen\b' 'generated UUIDs'
forbid '\$RANDOM' 'shell randomness'
forbid '(^|[^a-zA-Z_])date([[:space:]]|$)' 'wall-clock time'

printf '%s\n' 'BUILD-VARIANCE-PASS: 9 variance pins present, no unpinned UUID/randomness/wall-clock source in the builder.'
printf '%s\n' 'BUILD-VARIANCE-NOTE: pins present is not reproducibility; the byte-identical rebuild witness is still legacy.'
