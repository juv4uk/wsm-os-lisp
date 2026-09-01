.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $64, %rsp
    movq %rdi, %r12
    movq %r12, %rdi
    call wsm_pci_config_capability
    movq %rax, %rsi
    movq %rsp, %rdx
    call .Llambda_0
    jmp .Llambda_after_1
.Llambda_0:
    subq $56, %rsp
    movq %rsi, 0(%rsp)
    movq 0(%rsp), %rax
    movq %rax, 8(%rsp)
    movabsq $3, %rax
    movq %rax, 16(%rsp)
    movabsq $259, %rax
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
    addq $56, %rsp
    ret
.Llambda_after_1:
    addq $64, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
