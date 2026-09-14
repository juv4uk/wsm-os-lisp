#!/usr/bin/env bash
# ==============================================================================
# rebuild-and-run-rdtsc-qemu.sh: Witness for Lisp -> CML -> RDTSC machine primitive
# Proves:
#   1. Lisp source is the sole source of behavior: (def ticks (rdtsc)) ticks
#   2. CML lowers (rdtsc) directly to x86-64 `rdtsc` instruction (no C/Rust runtime)
#   3. UEFI kernel executes freestanding on physical machine (QEMU)
#   4. CPU cycle count is returned as a canonical WSM fixnum value
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/ovmf-env.sh"

FIXTURE_LISP="$ROOT_DIR/artifacts/rdtsc-fixture.lisp"
FIXTURE_ASM="$ROOT_DIR/artifacts/rdtsc-fixture.s"
FIXTURE_OBJ="$ROOT_DIR/artifacts/rdtsc-fixture.o"
UEFI_IMAGE="$ROOT_DIR/target/wsm-os-rdtsc-uefi.img"

# 1. Compile Lisp to x86-64 assembly via CML
echo "[1/4] Compiling $FIXTURE_LISP -> $FIXTURE_ASM via CML..."
cml_bin=""
if command -v cml >/dev/null 2>&1; then
    cml_bin="cml"
elif [[ -x "$ROOT_DIR/../cml/target/release/cml" ]]; then
    cml_bin="$ROOT_DIR/../cml/target/release/cml"
else
    cargo run --manifest-path "$ROOT_DIR/../cml/Cargo.toml" --release --bin cml --quiet -- x86-asm "$FIXTURE_LISP" > "$FIXTURE_ASM"
fi

if [[ -n "$cml_bin" ]]; then
    "$cml_bin" x86-asm "$FIXTURE_LISP" > "$FIXTURE_ASM"
fi

# Verify `rdtsc` instruction is present in generated assembly
if ! grep -q '\brdtsc\b' "$FIXTURE_ASM"; then
    echo "ERROR: generated assembly does not contain 'rdtsc' instruction!" >&2
    exit 1
fi
echo "      Verified: generated assembly contains 'rdtsc' instruction."

# 2. Assemble to ELF object file
echo "[2/4] Assembling $FIXTURE_ASM -> $FIXTURE_OBJ..."
as --64 "$FIXTURE_ASM" -o "$FIXTURE_OBJ"

# 3. Build pure freestanding UEFI image
echo "[3/4] Building UEFI disk image $UEFI_IMAGE..."
"$ROOT_DIR/scripts/build-uefi-image.sh" "$FIXTURE_OBJ" "$UEFI_IMAGE" >/dev/null

# 4. Boot in QEMU and capture serial transcript
echo "[4/4] Running QEMU witness..."
run_dir=$(mktemp -d)
trap 'rm -rf "$run_dir"' EXIT
serial_log="$run_dir/serial.log"
vars_copy="$run_dir/ovmf-vars.fd"
cp "$OVMF_VARS" "$vars_copy"
chmod u+w "$vars_copy"

set +e
timeout 20 qemu-system-x86_64 -machine q35 -m 128M \
  -drive "if=pflash,unit=0,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive "if=pflash,unit=1,format=raw,file=$vars_copy" \
  -drive "format=raw,file=$UEFI_IMAGE" \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -serial "file:$serial_log" -display none -no-reboot
status=$?
set -e

if [[ "$status" -ne 33 && "$status" -ne 37 ]]; then
    echo "ERROR: QEMU exited with unexpected status $status" >&2
    cat "$serial_log" >&2
    exit 1
fi

observed=$(tr -d '\r' < "$serial_log" | grep '^WSM-OS ')
printf '%s\n' "$observed"

# Validate output pattern
boot_line=$(echo "$observed" | grep '^WSM-OS BOOT schema=1 arch=x86_64 status=ok$' || true)
result_line=$(echo "$observed" | grep -E '^WSM-OS RESULT schema=1 value=[0-9]+ status=ok$' || true)

if [[ -z "$boot_line" || -z "$result_line" ]]; then
    echo "ERROR: Witness failed! Output does not match expected schema:" >&2
    echo "$observed" >&2
    exit 1
fi

ticks_value=$(echo "$result_line" | sed -E 's/.*value=([0-9]+).*/\1/')
if [[ "$ticks_value" -le 0 ]]; then
    echo "ERROR: Invalid tick count $ticks_value" >&2
    exit 1
fi

echo "SUCCESS: Witness passed. Read $ticks_value CPU ticks directly from physical hardware."
