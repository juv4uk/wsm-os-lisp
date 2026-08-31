.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $64, %rsp
    movq %rdi, %r12
    movabsq $12, %rax
    movq %rax, %rsi
    call .Llambda_0
    jmp .Llambda_after_1
.Llambda_0:
    subq $40, %rsp
    movq %rsi, 0(%rsp)
    movq 0(%rsp), %rax
    movq %rax, 8(%rsp)
    movabsq $1, %rax
    movq %rax, 16(%rsp)
    movq %r12, %rdi
    movq 8(%rsp), %rsi
    movq 16(%rsp), %rdx
    call wsm_cons
    addq $40, %rsp
    ret
.Llambda_after_1:
    addq $64, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
