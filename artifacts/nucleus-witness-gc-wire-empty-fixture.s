# ===========================================================================
# nucleus-witness-gc-wire-empty-fixture.s
# #64: an explicitly empty certificate is CERTIFIED-EMPTY, not NOT-A-SAFEPOINT
# and not "absent". The site is proven to have no roots; allocation proceeds.
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
    movl $1, %ecx
    call wsm_gc_wire_register

    movq %r12, %rdi
    movabsq $12, %rsi
    movabsq $20, %rdx
    call wsm_cons
.Lsite_cons:
    movq %rax, 0(%rsp)

    movq %r12, %rdi
    call wsm_gc_safepoint_state
    cmpl $4, %eax                   # CERTIFIED-EMPTY
    jne .Lbad_state
    movq %r12, %rdi
    call wsm_gc_safepoint_stack_count
    testl %eax, %eax
    jnz .Lbad_state

    movq 0(%rsp), %rax
    addq $64, %rsp
    popq %r12
    ret

.Lbad_state:
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
    .byte 1, 0, 1, 0                # cons, no registers, certified_empty
    .quad 0
    .long 0
    .long 0
    .quad 0
.align 16
.Lbindings:
    .long 1
    .long 0
    .quad .Lsite_cons
.section .note.GNU-stack,"",@progbits
