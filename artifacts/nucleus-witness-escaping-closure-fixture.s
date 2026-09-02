.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $112, %rsp
    movq %rdi, %r12
    movabsq $12, %rax
    movq %rax, %rsi
    movq %rsp, %rdx
    call .Llambda_0
    jmp .Llambda_after_1
.Llambda_0:
    subq $72, %rsp
    movq %rsi, 0(%rsp)
    movabsq $1, %rax
    movq %rax, 8(%rsp)
    movq %r12, %rdi
    movq 0(%rsp), %rsi
    movq 8(%rsp), %rdx
    call wsm_cons
    movq %rax, %rdx
    movq %r12, %rdi
    movl $3, %esi
    call wsm_closure_new
    jmp .Lclosure_after_3
.Lclosure_3:
    subq $72, %rsp
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
    movq 16(%rsp), %rax
    movq %rax, 24(%rsp)
    movq 0(%rsp), %rax
    movq %rax, 32(%rsp)
    movabsq $1, %rax
    movq %rax, 40(%rsp)
    movq %r12, %rdi
    movq 32(%rsp), %rsi
    movq 40(%rsp), %rdx
    call wsm_cons
    movq %rax, 48(%rsp)
    movq %r12, %rdi
    movq 24(%rsp), %rsi
    movq 48(%rsp), %rdx
    call wsm_cons
    addq $72, %rsp
    ret
.Lclosure_after_3:
    addq $72, %rsp
    ret
.Llambda_after_1:
    movq %rax, 0(%rsp)
    movabsq $20, %rax
    movq %rax, 8(%rsp)
    movq %r12, %rdi
    movq 0(%rsp), %rsi
    call wsm_closure_environment
    movq %rax, 16(%rsp)
    movq %r12, %rdi
    movq 0(%rsp), %rsi
    call wsm_closure_definition
    cmpl $3, %eax
    jne .Lclosure_dispatch_5
    movq 8(%rsp), %rsi
    movq 16(%rsp), %rdx
    call .Lclosure_3
    jmp .Lclosure_call_end_4
.Lclosure_dispatch_5:
    movq %r12, %rdi
    movl $4, %esi
    movq 0(%rsp), %rdx
    xorl %ecx, %ecx
    call wsm_fail
.Lclosure_call_end_4:
    addq $112, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
