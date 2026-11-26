# ===========================================================================
# nucleus-witness-gc-wire-dup-label-fixture.s
# #64: two binding rows for the same label make resolution ambiguous and must
# fail closed at registration.
# Expected: kind=ABI source=1195573251 (0x47430003) value=1
# ===========================================================================
.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $64, %rsp
    movq %rdi, %r12

.Lpc_base:
    movq %r12, %rdi
    leaq .Lwire(%rip), %rsi
    leaq .Lbindings(%rip), %rdx
    movl $2, %ecx
    call wsm_gc_wire_register

    movq %r12, %rdi
    movl $4, %esi
    movq %rax, %rdx
    call wsm_fail
.size wsm_entry, .-wsm_entry

.section .rodata
.align 16
.Lwire:
    .long 0x4752434D
    .short 1
    .short 1
    .long 32
    .long 0
    .quad .Lpc_base
    .quad 0
    .long 1
    .byte 1, 3, 0, 0
    .quad 0
    .long 0
    .long 0
    .quad 0
.align 16
.Lbindings:
    .long 1
    .long 0
    .quad .Lpc_base
    .long 1                         # same label again
    .long 0
    .quad .Lpc_base
.section .note.GNU-stack,"",@progbits
