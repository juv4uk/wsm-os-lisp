.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $112, %rsp
    movq %rdi, %r12
    movq %r12, %rdi
    call wsm_mmio_capability
    movq %rax, %rsi
    movq %rsp, %rdx
    call .Llambda_0
    jmp .Llambda_after_1
.Llambda_0:
    subq $104, %rsp
    movq %rsi, 0(%rsp)
    movq 0(%rsp), %rax
    movq %rax, 8(%rsp)
    movabsq $163, %rax
    movq %rax, 16(%rsp)
    movabsq $11, %rax
    movq %rax, 24(%rsp)
    movq %r12, %rdi
    movq 8(%rsp), %rsi
    movq 16(%rsp), %rdx
    movq 24(%rsp), %rcx
    call wsm_mmio_write32
    movq %rax, %rsi
    movq %rsp, %rdx
    call .Llambda_2
    jmp .Llambda_after_3
.Llambda_2:
    subq $56, %rsp
    movq %rsi, 0(%rsp)
    movq 0(%rdx), %rax
    movq %rax, 8(%rsp)
    movq 8(%rsp), %rax
    movq %rax, 16(%rsp)
    movabsq $163, %rax
    movq %rax, 24(%rsp)
    movq %r12, %rdi
    movq 16(%rsp), %rsi
    movq 24(%rsp), %rdx
    call wsm_mmio_read32
    movq %rax, 32(%rsp)
    movabsq $11, %rax
    movq %rax, 40(%rsp)
    movq %r12, %rdi
    movq 32(%rsp), %rsi
    movq 40(%rsp), %rdx
    call wsm_eq
    addq $56, %rsp
    ret
.Llambda_after_3:
    addq $104, %rsp
    ret
.Llambda_after_1:
    addq $112, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
