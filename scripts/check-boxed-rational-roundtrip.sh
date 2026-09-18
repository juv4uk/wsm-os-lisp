#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/wsm-rational-roundtrip.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

BOXED_TAG="$(bash "$ROOT_DIR/scripts/target-contract-value.sh" boxed-tag)"

cat >"$TMP/harness.s" <<'ASM'
.section .bss
.align 16
boxed_arena:
    .skip 48                       # two 24-byte runtime-private entries

.section .data
.align 16
.globl saved_boot_info
saved_boot_info:
    .quad 0

.align 16
runtime_context:
    .quad 0                        #  0 heap_base
    .quad 0                        #  8 heap_capacity
    .quad 0                        # 16 heap_len
    .quad 0                        # 24 closure_base
    .quad 0                        # 32 closure_capacity
    .quad 0                        # 40 closure_len
    .long 0                        # 48 condition_kind
    .long 0                        # 52 condition_source
    .quad 0                        # 56 condition_value
    .quad failure_handler          # 64 failure_handler
    .quad boxed_arena              # 72 boxed_base
    .quad 2                        # 80 boxed_capacity
    .quad 0                        # 88 boxed_len

.section .text
.globl _start
.type _start, @function
_start:
    leaq runtime_context(%rip), %rdi
    movq $-7, %rsi                 # representation fact, not arithmetic oracle
    movq $11, %rdx
    call wsm_rational_new
    movq %rax, %r12

    movq %rax, %rcx
    andq $7, %rcx
    cmpq $WSM_TAG_BOXED, %rcx
    jne .Lbad_tag

    leaq runtime_context(%rip), %rdi
    movq %r12, %rsi
    call wsm_rational_numerator
    cmpq $-7, %rax
    jne .Lbad_numerator

    leaq runtime_context(%rip), %rdi
    movq %r12, %rsi
    call wsm_rational_denominator
    cmpq $11, %rax
    jne .Lbad_denominator

    movq $60, %rax                  # Linux x86_64 sys_exit
    xorq %rdi, %rdi
    syscall

failure_handler:
    movq $60, %rax
    movq $90, %rdi
    syscall

.Lbad_tag:
    movq $41, %rdi
    jmp .Lfail
.Lbad_numerator:
    movq $42, %rdi
    jmp .Lfail
.Lbad_denominator:
    movq $43, %rdi
.Lfail:
    movq $60, %rax
    syscall
ASM

as --64 --defsym WSM_TAG_BOXED="$BOXED_TAG" "$ROOT_DIR/src/runtime.s" -o "$TMP/runtime.o"
as --64 --defsym WSM_TAG_BOXED="$BOXED_TAG" "$TMP/harness.s" -o "$TMP/harness.o"
ld -m elf_x86_64 -e _start "$TMP/harness.o" "$TMP/runtime.o" -o "$TMP/roundtrip"
"$TMP/roundtrip"

echo "BOXED-RATIONAL-ROUNDTRIP-GREEN: exact representation facts round-trip through native runtime"
