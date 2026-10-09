#!/usr/bin/env bash
set -euo pipefail

# Historical #37 / issue #31, adapted to current main's LOOP-based UART poll.
# This is a substrate bound witness, not a SENS semantic or D10 admission.
root="$(cd "$(dirname "$0")/.." && pwd)"
src="${WSM_OS_ENTRY_SRC:-$root/src/entry.s}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "SERIAL-POLL-BOUND: FAIL: $*" >&2; exit 1; }
[[ -f "$src" ]] || fail "missing entry source: $src"

# Demand real assembler acceptance, not only a source-text pattern.
as --64 "$src" -o "$tmp/entry.o" || fail "entry source does not assemble"
disasm="$(objdump -d "$tmp/entry.o")"
grep -Eq '[[:space:]]loop[[:space:]]' <<< "$disasm" || fail "no compiled LOOP instruction"

section="$(sed -n '/^serial_putc:/,/^serial_write:/p' "$src")"
[[ -n "$section" ]] || fail "serial_putc function missing"
limit="$(sed -n 's/^[[:space:]]*movl[[:space:]]*\$\([0-9][0-9]*\),[[:space:]]*%ecx.*/\1/p' <<< "$section" | head -n 1)"
[[ "$limit" =~ ^[0-9]+$ ]] || fail "missing finite ECX retry counter"
(( limit > 0 && limit <= 1000000 )) || fail "counter outside admitted positive finite budget"
grep -Eq '^[[:space:]]*loop[[:space:]]+1b' <<< "$section" || fail "poll must decrement and loop with finite ECX"
grep -Eq '^[[:space:]]*jnz[[:space:]]+2f' <<< "$section" || fail "healthy UART THRE branch missing"
! grep -Eq '^[[:space:]]*(jz|jmp)[[:space:]]+1b' <<< "$section" || fail "unbounded backwards branch admitted"
grep -Fq 'movw $0xF4, %dx' <<< "$section" || fail "serial transport exit port missing"
grep -Fq 'movl $0x13, %eax' <<< "$section" || fail "distinct serial transport exit code missing"
grep -Fq 'outl %eax, %dx' <<< "$section" || fail "transport exit not emitted"
grep -Eq '^[[:space:]]*hlt' <<< "$section" || fail "transport failure does not halt"

echo "SERIAL-POLL-BOUND: PASS (assembled finite UART poll, distinct transport exit 39)"
