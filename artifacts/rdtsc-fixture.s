.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $32, %rsp
    movq %rdi, %r12
    rdtsc
    shlq $32, %rdx
    orq %rdx, %rax
    movabsq $0x0FFFFFFFFFFFFFFF, %rcx
    andq %rcx, %rax
    shlq $3, %rax
    orq $3, %rax
    movq %rax, .Ldata_word_0(%rip)
    movq .Ldata_word_0(%rip), %rax
    addq $32, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .bss
.align 8
.Ldata_word_0:
    .quad 0
.section .note.GNU-stack,"",@progbits
