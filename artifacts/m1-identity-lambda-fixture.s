.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $16, %rsp
    movq %rdi, %r12
    movabsq $59, %rax
    movq %rax, %rsi
    call .Lidentity_lambda_0
    jmp .Lidentity_after_1
.Lidentity_lambda_0:
    movq %rsi, %rax
    ret
.Lidentity_after_1:
    addq $16, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
