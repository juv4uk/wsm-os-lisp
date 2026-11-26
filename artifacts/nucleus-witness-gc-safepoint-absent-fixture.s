# ===========================================================================
# nucleus-witness-gc-safepoint-absent-fixture.s
# #71: with no root map registered every allocation site is NOT-A-SAFEPOINT.
# Allocation must behave exactly as before: no failure, no capture.
# ===========================================================================
.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $64, %rsp
    movq %rdi, %r12

    movq %r12, %rdi
    movabsq $12, %rsi
    movabsq $20, %rdx
    call wsm_cons
    movq %rax, 0(%rsp)

    movq %r12, %rdi
    call wsm_gc_safepoint_state
    cmpl $2, %eax                   # NOT-A-SAFEPOINT
    jne .Lbad_state

    movq %r12, %rdi
    call wsm_gc_safepoint_captures
    testq %rax, %rax
    jnz .Lbad_count

    movq %r12, %rdi
    movl $7, %esi
    movabsq $1, %rdx
    call wsm_closure_new

    movq %r12, %rdi
    call wsm_gc_safepoint_state
    cmpl $2, %eax
    jne .Lbad_state

    movq 0(%rsp), %rax
    addq $64, %rsp
    popq %r12
    ret

.Lbad_state:
    movq %r12, %rdi
    movl $4, %esi
    movq %rax, %rdx
    call wsm_fail

.Lbad_count:
    movq %r12, %rdi
    movl $4, %esi
    movq %rax, %rdx
    call wsm_fail
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
