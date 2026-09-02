.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $32, %rsp
    movq %rdi, %r12
    movabsq $1, %rax
    movq %rax, 0(%rsp)
    movq %r12, %rdi
    movq 0(%rsp), %rsi
    call wsm_atom
    addq $32, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
