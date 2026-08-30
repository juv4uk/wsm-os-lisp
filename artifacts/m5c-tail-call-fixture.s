.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $112, %rsp
    movq %rdi, %r12
    movabsq $800003, %rax
    movq %rax, 0(%rsp)
.Ltcloop_0:
.Lcond_branch_2:
    movq 0(%rsp), %rax
    movq %rax, 8(%rsp)
    movabsq $3, %rax
    movq %rax, 16(%rsp)
    movq %r12, %rdi
    movq 8(%rsp), %rsi
    movq 16(%rsp), %rdx
    call wsm_eq
    movabsq $1, %rcx
    cmpq %rcx, %rax
    je .Lcond_branch_3
    movabsq $2, %rax
    jmp .Lcond_end_1
.Lcond_branch_3:
    movabsq $2, %rax
    movabsq $1, %rcx
    cmpq %rcx, %rax
    je .Lcond_branch_4
    movq 0(%rsp), %rax
    movq %rax, 24(%rsp)
    movabsq $11, %rax
    movq %rax, 32(%rsp)
    movq 24(%rsp), %rcx
    sarq $3, %rcx
    movq 32(%rsp), %rdx
    sarq $3, %rdx
    subq %rdx, %rcx
    jo .Larith_overflow_6
    movabsq $-1152921504606846976, %rax
    cmpq %rax, %rcx
    jl .Larith_overflow_6
    movabsq $1152921504606846975, %rax
    cmpq %rax, %rcx
    jg .Larith_overflow_6
    shlq $3, %rcx
    orq $3, %rcx
    movq %rcx, %rax
    jmp .Larith_ok_5
.Larith_overflow_6:
    movq %r12, %rdi
    movl $2, %esi
    call wsm_fail
.Larith_ok_5:
    movq %rax, 40(%rsp)
    movq 40(%rsp), %rax
    movq %rax, 0(%rsp)
    jmp .Ltcloop_0
    jmp .Lcond_end_1
.Lcond_branch_4:
    movabsq $1, %rax
.Lcond_end_1:
    addq $112, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
