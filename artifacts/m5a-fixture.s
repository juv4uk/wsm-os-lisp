.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $128, %rsp
    movq %rdi, %r12
.Lcond_branch_1:
    movabsq $1, %rax
    movabsq $1, %rcx
    cmpq %rcx, %rax
    je .Lcond_branch_2
    movabsq $20, %rax
    jmp .Lcond_end_0
.Lcond_branch_2:
    movabsq $2, %rax
    movabsq $1, %rcx
    cmpq %rcx, %rax
    je .Lcond_branch_3
    movabsq $339, %rax
    movq %rax, 0(%rsp)
    movabsq $19, %rax
    movq %rax, 8(%rsp)
    movq 0(%rsp), %rcx
    sarq $3, %rcx
    movq 8(%rsp), %rdx
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
    movq %rax, 16(%rsp)
    movabsq $3, %rax
    movq %rax, 24(%rsp)
    movq 16(%rsp), %rcx
    sarq $3, %rcx
    movq 24(%rsp), %rdx
    sarq $3, %rdx
    addq %rdx, %rcx
    jo .Larith_overflow_7
    movabsq $-1152921504606846976, %rax
    cmpq %rax, %rcx
    jl .Larith_overflow_7
    movabsq $1152921504606846975, %rax
    cmpq %rax, %rcx
    jg .Larith_overflow_7
    shlq $3, %rcx
    orq $3, %rcx
    movq %rcx, %rax
    jmp .Larith_ok_4
.Larith_overflow_7:
    movq %r12, %rdi
    movl $2, %esi
    call wsm_fail
.Larith_ok_4:
    jmp .Lcond_end_0
.Lcond_branch_3:
    movabsq $1, %rax
.Lcond_end_0:
    movq %rax, 32(%rsp)
    movabsq $12, %rax
    movq %rax, 40(%rsp)
    movabsq $12, %rax
    movq %rax, 48(%rsp)
    movq %r12, %rdi
    movq 40(%rsp), %rsi
    movq 48(%rsp), %rdx
    call wsm_eq
    movq %rax, 56(%rsp)
    movq %r12, %rdi
    movq 32(%rsp), %rsi
    movq 56(%rsp), %rdx
    call wsm_cons
    addq $128, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
