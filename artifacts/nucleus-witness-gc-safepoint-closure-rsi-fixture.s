# ===========================================================================
# nucleus-witness-gc-safepoint-closure-rsi-fixture.s
# #71: a closure site may certify only %rdx. A record that claims %rsi is a
# root at a closure site is contradictory metadata and must reject.
#
# Expected: ABI condition, source = 0x47430002 (GC map invalid), value = 0.
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
    leaq .Lroot_map(%rip), %rsi
    movl $1, %edx
    leaq .Lpc_base(%rip), %rcx
    call wsm_gc_root_map_register

    movq %r12, %rdi
    movl $7, %esi
    movabsq $12, %rdx
    call wsm_closure_new
.Lsite_closure:
    movq %r12, %rdi
    movl $4, %esi
    movq %rax, %rdx
    call wsm_fail

.align 8
.Lroot_map:
    .long .Lsite_closure - .Lpc_base
    .byte 2, 1, 0, 0                # closure kind but claims %rsi as a root
    .quad 0
    .long 0
    .long 0
    .quad 0
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
