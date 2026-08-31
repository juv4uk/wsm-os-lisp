.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $32, %rsp
    movq %rdi, %r12
    movabsq $59, %rax
    movq %rax, %rsi
    movq %rsp, %rdx
    call .Llambda_0
    jmp .Llambda_after_1
.Llambda_0:
    subq $24, %rsp
    movq %rsi, 0(%rsp)
    movq 0(%rsp), %rax
    addq $24, %rsp
    ret
.Llambda_after_1:
    addq $32, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
