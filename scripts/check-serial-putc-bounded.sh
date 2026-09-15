#!/usr/bin/env bash
set -euo pipefail

# PHYSICAL-SERIAL-GATE-1 (issue #31) structural witness.
#
# Proves, from the assembled object, that src/entry.s::serial_putc has:
#   1. a finite retry counter (a `dec` feeding a conditional jump inside the
#      THRE poll loop) — so a never-ready COM1 cannot trap the evidence path;
#   2. an explicit serial transport failure symbol (serial_transport_failure);
#   3. a jump from serial_putc to that failure symbol — the bounded loop owns an
#      explicit transport-failure exit, distinct from kernel_failure / runtime.
#
# On the pre-fix loop (`1: inb; testb $0x20; jz 1b`) every check below fails,
# so this script is the RED witness for issue #31.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${WSM_OS_ENTRY_SRC:-$ROOT_DIR/src/entry.s}"

obj="$ROOT_DIR/target/.serial-putc-check.$$.o"
trap 'rm -f "$obj"' EXIT

as --64 "$SRC" -o "$obj"

fail_count=0
fail() {
  echo "SERIAL-POLL-BOUND: FAIL: $1" >&2
  fail_count=$((fail_count + 1))
}

# 1. Explicit transport-failure symbol must exist.
if nm "$obj" | grep -q 'serial_transport_failure'; then
  : # present
else
  fail "no distinct serial_transport_failure symbol/exit path"
fi

disasm="$(objdump -d --disassemble=serial_putc "$obj")"

# 2. serial_putc must contain a finite counter (dec + conditional jump).
#    objdump lines are "<addr>: <encoded bytes> <mnemonic> <operands>", so the
#    mnemonic is matched anywhere on the line inside the serial_putc body.
if grep -q 'dec[[:blank:]]' <<<"$disasm"; then
  : # counter present
else
  fail "serial_putc has no finite retry counter (no dec of a poll bound)"
fi
if grep -qE 'jne[[:blank:]]' <<<"$disasm" || grep -qE 'jnz[[:blank:]]' <<<"$disasm"; then
  : # conditional branch present
else
  fail "serial_putc has no conditional loop branch tied to the counter"
fi

# 3. serial_putc must jump to the distinct transport-failure path.
if grep -q 'serial_transport_failure' <<<"$disasm"; then
  : # explicit failure exit targeted
else
  fail "serial_putc has no jump to serial_transport_failure"
fi

if [[ "$fail_count" -ne 0 ]]; then
  echo "SERIAL-POLL-BOUND: RED (unbounded poll present)" >&2
  exit 1
fi

echo "SERIAL-POLL-BOUND: PASS (bounded THRE poll with explicit transport-failure exit)"