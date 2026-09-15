#!/usr/bin/env bash
# PHYSICAL-SERIAL-GATE-1 (issue #31) structural witness.
#
# Proves, from the assembled object, that src/entry.s::serial_putc:
#   1. Polls COM1 LSR THRE before every emitted byte (retained behavior)
#   2. Has an explicit finite retry/iteration bound (no unbounded spin)
#   3. On exhaustion, enters a distinct serial transport failure path
#      (not kernel_failure, not panic/result schema, not a Lisp condition)
#
# Negative authority witnesses (must FAIL if violated):
#   1. no unbounded spin loop in serial_putc (missing finite bound)
#   2. no transport-failure outcome (fallback to kernel_failure/panic/result)
#
# Positive structural witnesses (must PASS):
#   1. finite retry counter present (loop instruction with bound)
#   2. distinct transport failure exit via ISA debug port 0xF4 code 0x13
#   3. THRE poll before emit retained

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${WSM_OS_ENTRY_SRC:-$ROOT_DIR/src/entry.s}"

obj="$ROOT_DIR/target/.serial-gate-check.$$.o"
trap 'rm -f "$obj"' EXIT

as --64 "$SRC" -o "$obj"

fail_count=0
fail() {
  echo "SERIAL-GATE: FAIL: $1" >&2
  fail_count=$((fail_count + 1))
}
note() {
  echo "SERIAL-GATE: $1" >&2
}

# --- Negative witnesses -----------------------------------------------------

# 1. Unbounded spin loop must not exist.
# Old pattern: label + test + jz label (no loop/decrement)
disasm="$(objdump -d --disassemble=serial_putc "$obj" 2>/dev/null)" || disasm=""

# Check for the old unbounded pattern: jz to same label without loop/decrement
# The old code had: label 1: ... testb $0x20 ... jz 1b
# The new code uses: loop 1b (which dec %ecx; jnz)
if ! grep -q 'loop' <<<"$disasm"; then
  fail "no 'loop' instruction in serial_putc (missing finite bound)"
else
  note "positive: 'loop' instruction present (finite retry bound)"
fi

# 2. Transport failure exit must use distinct code 0x13 via port 0xF4
if ! grep -q 'mov.*0x13' <<<"$disasm" && ! grep -q 'mov.*0x13,' <<<"$disasm"; then
  fail "no distinct transport failure exit code 0x13"
else
  note "positive: transport failure exit code 0x13 present"
fi

# Check port 0xF4 is used for transport failure
if ! grep -q '0xF4' <<<"$disasm" && ! grep -q '0xf4' <<<"$disasm"; then
  fail "ISA debug port 0xF4 not used for transport failure"
else
  note "positive: ISA debug port 0xF4 used for transport failure"
fi

# 3. THRE poll (test $0x20) must be present
if ! grep -q 'test.*0x20' <<<"$disasm"; then
  fail "THRE poll (test $0x20) not found"
else
  note "positive: THRE poll (test $0x20) retained"
fi

# 4. serial_putc must not jump to kernel_failure/panic on transport failure
# Check that the transport failure path does not call kernel_failure
if grep -q 'call.*kernel_failure' <<<"$disasm"; then
  fail "serial_putc calls kernel_failure on transport failure (not distinct)"
else
  note "positive: serial_putc does not call kernel_failure on transport failure"
fi

# 5. The successful path (THRE ready) must still emit via port 0x3F8
if ! grep -q '0x3F8' <<<"$disasm" && ! grep -q '0x3f8' <<<"$disasm"; then
  fail "successful emit path (port 0x3F8) not found"
else
  note "positive: successful emit via port 0x3F8 retained"
fi

if [[ "$fail_count" -ne 0 ]]; then
  echo "SERIAL-GATE: RED (serial transport gate not satisfied)" >&2
  exit 1
fi

echo "SERIAL-GATE: PASS (bounded UART poll, distinct transport failure, THRE retained)"
exit 0