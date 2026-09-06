.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $224, %rsp
    movq %rdi, %r12
    movq %r12, %rdi
    call wsm_pci_config_capability
    movq %rax, %rsi
    movq %rsp, %rdx
    call .Llambda_0
    jmp .Llambda_after_1
.Llambda_0:
    subq $216, %rsp
    movq %rsi, 0(%rsp)
    movq 0(%rsp), %rax
    movq %rax, 8(%rsp)
    movabsq $3, %rax
    movq %rax, 16(%rsp)
    movabsq $43, %rax
    movq %rax, 24(%rsp)
    movabsq $3, %rax
    movq %rax, 32(%rsp)
    movabsq $3, %rax
    movq %rax, 40(%rsp)
    movq %r12, %rdi
    movq 8(%rsp), %rsi
    movq 16(%rsp), %rdx
    movq 24(%rsp), %rcx
    movq 32(%rsp), %r8
    movq 40(%rsp), %r9
    call wsm_pci_config_read16
    movq %rax, %rsi
    movq %rsp, %rdx
    call .Llambda_2
    jmp .Llambda_after_3
.Llambda_2:
    subq $104, %rsp
    movq %rsi, 0(%rsp)
    movq 0(%rdx), %rax
    movq %rax, 8(%rsp)
    movabsq $1, %rax
    movq %rax, 16(%rsp)
    movq %r12, %rdi
    movq 0(%rsp), %rsi
    movq 16(%rsp), %rdx
    call wsm_cons
    movq %rax, 24(%rsp)
    movq %r12, %rdi
    movq 8(%rsp), %rsi
    movq 24(%rsp), %rdx
    call wsm_cons
    movq %rax, %rdx
    movq %r12, %rdi
    movl $5, %esi
    call wsm_closure_new
    jmp .Lclosure_after_5
.Lclosure_5:
    subq $104, %rsp
    movq %rsi, 0(%rsp)
    movq %rdx, 8(%rsp)
    movq %r12, %rdi
    movq 8(%rsp), %rsi
    call wsm_car
    movq %rax, 16(%rsp)
    movq %r12, %rdi
    movq 8(%rsp), %rsi
    call wsm_cdr
    movq %rax, 8(%rsp)
    movq %r12, %rdi
    movq 8(%rsp), %rsi
    call wsm_car
    movq %rax, 24(%rsp)
    movq %r12, %rdi
    movq 8(%rsp), %rsi
    call wsm_cdr
    movq %rax, 8(%rsp)
.Lcond_branch_7:
    movq 24(%rsp), %rax
    movq %rax, 32(%rsp)
    movabsq $55203, %rax
    movq %rax, 40(%rsp)
    movq %r12, %rdi
    movq 32(%rsp), %rsi
    movq 40(%rsp), %rdx
    call wsm_eq
    movabsq $1, %rcx
    cmpq %rcx, %rax
    je .Lcond_branch_8
    movq 0(%rsp), %rax
    movq %rax, 48(%rsp)
    movabsq $33299, %rax
    movq %rax, 56(%rsp)
    movq %r12, %rdi
    movq 48(%rsp), %rsi
    movq 56(%rsp), %rdx
    call wsm_eq
    jmp .Lcond_end_6
.Lcond_branch_8:
    movabsq $18446744073709551612, %rax
    movabsq $1, %rcx
    cmpq %rcx, %rax
    je .Lcond_branch_9
    movabsq $1, %rax
    jmp .Lcond_end_6
.Lcond_branch_9:
    movabsq $1, %rax
.Lcond_end_6:
    addq $104, %rsp
    ret
.Lclosure_after_5:
    addq $104, %rsp
    ret
.Llambda_after_3:
    movq %rax, 48(%rsp)
    movq 0(%rsp), %rax
    movq %rax, 56(%rsp)
    movabsq $3, %rax
    movq %rax, 64(%rsp)
    movabsq $43, %rax
    movq %rax, 72(%rsp)
    movabsq $3, %rax
    movq %rax, 80(%rsp)
    movabsq $19, %rax
    movq %rax, 88(%rsp)
    movq %r12, %rdi
    movq 56(%rsp), %rsi
    movq 64(%rsp), %rdx
    movq 72(%rsp), %rcx
    movq 80(%rsp), %r8
    movq 88(%rsp), %r9
    call wsm_pci_config_read16
    movq %rax, 96(%rsp)
    movq %r12, %rdi
    movq 48(%rsp), %rsi
    call wsm_closure_environment
    movq %rax, 104(%rsp)
    movq %r12, %rdi
    movq 48(%rsp), %rsi
    call wsm_closure_definition
    cmpl $5, %eax
    jne .Lclosure_dispatch_11
    movq 96(%rsp), %rsi
    movq 104(%rsp), %rdx
    call .Lclosure_5
    jmp .Lclosure_call_end_10
.Lclosure_dispatch_11:
    movq %r12, %rdi
    movl $4, %esi
    movq 48(%rsp), %rdx
    xorl %ecx, %ecx
    call wsm_fail
.Lclosure_call_end_10:
    addq $216, %rsp
    ret
.Llambda_after_1:
    addq $224, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
