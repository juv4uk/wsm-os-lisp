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
    subq $88, %rsp
    movq %rsi, 0(%rsp)
    movabsq $20, %rax
    movq %rax, %rsi
    movq %rsp, %rdx
    call .Llambda_2
    jmp .Llambda_after_3
.Llambda_2:
    subq $72, %rsp
    movq %rsi, 0(%rsp)
    movq 0(%rdx), %rax
    movq %rax, 8(%rsp)
    movq 8(%rsp), %rax
    movq %rax, 16(%rsp)
    movq 0(%rsp), %rax
    movq %rax, 24(%rsp)
    movabsq $1, %rax
    movq %rax, 32(%rsp)
    movq %r12, %rdi
    movq 24(%rsp), %rsi
    movq 32(%rsp), %rdx
    call wsm_cons
    movq %rax, 40(%rsp)
    movq %r12, %rdi
    movq 16(%rsp), %rsi
    movq 40(%rsp), %rdx
    call wsm_cons
    addq $72, %rsp
    ret
.Llambda_after_3:
    addq $88, %rsp
    ret
.Llambda_after_1:
    addq $112, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
