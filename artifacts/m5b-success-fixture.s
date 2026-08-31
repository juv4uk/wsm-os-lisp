.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $64, %rsp
    movq %rdi, %r12
    movabsq $9223372036854775795, %rax
    movq %rax, 0(%rsp)
    movabsq $11, %rax
    movq %rax, 8(%rsp)
    movq 0(%rsp), %rcx
    sarq $3, %rcx
    movq 8(%rsp), %rdx
    sarq $3, %rdx
    addq %rdx, %rcx
    jo .Larith_overflow_1
    movabsq $-1152921504606846976, %rax
    cmpq %rax, %rcx
    jl .Larith_overflow_1
    movabsq $1152921504606846975, %rax
    cmpq %rax, %rcx
    jg .Larith_overflow_1
    shlq $3, %rcx
    orq $3, %rcx
    movq %rcx, %rax
    jmp .Larith_ok_0
.Larith_overflow_1:
    movq %r12, %rdi
    movl $2, %esi
    xorl %edx, %edx
    xorl %ecx, %ecx
    call wsm_fail
.Larith_ok_0:
    movq %rax, 16(%rsp)
    movabsq $9223372036854775819, %rax
    movq %rax, 24(%rsp)
    movabsq $11, %rax
    movq %rax, 32(%rsp)
    movq 24(%rsp), %rcx
    sarq $3, %rcx
    movq 32(%rsp), %rdx
    sarq $3, %rdx
    subq %rdx, %rcx
    jo .Larith_overflow_3
    movabsq $-1152921504606846976, %rax
    cmpq %rax, %rcx
    jl .Larith_overflow_3
    movabsq $1152921504606846975, %rax
    cmpq %rax, %rcx
    jg .Larith_overflow_3
    shlq $3, %rcx
    orq $3, %rcx
    movq %rcx, %rax
    jmp .Larith_ok_2
.Larith_overflow_3:
    movq %r12, %rdi
    movl $2, %esi
    xorl %edx, %edx
    xorl %ecx, %ecx
    call wsm_fail
.Larith_ok_2:
    movq %rax, 40(%rsp)
    movq %r12, %rdi
    movq 16(%rsp), %rsi
    movq 40(%rsp), %rdx
    call wsm_cons
    addq $64, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
