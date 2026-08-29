.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $48, %rsp
    movq %rdi, %r12
    movabsq $12, %rax
    movq %rax, 0(%rsp)
    movabsq $20, %rax
    movq %rax, 8(%rsp)
    movq %r12, %rdi
    movq 0(%rsp), %rsi
    movq 8(%rsp), %rdx
    call wsm_cons
    addq $48, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
