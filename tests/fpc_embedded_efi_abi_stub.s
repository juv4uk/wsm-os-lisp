.section .rodata
.align 8
callback_context:
    .quad 7

.section .text
.global wsm_efi_msabi_stub
.type wsm_efi_msabi_stub, @function
.extern wsm_efi_callback

wsm_efi_msabi_stub:
    movq %rsp, %rax
    andq $15, %rax
    cmpq $8, %rax
    jne .Learly_fail
    movabsq $0x1122334455667788, %rax
    movq %rax, 8(%rsp)
    movq %rax, 16(%rsp)
    movq %rax, 24(%rsp)
    movq %rax, 32(%rsp)
    leaq (%rcx,%rdx), %rax
    addq %r8, %rax
    addq %r9, %rax
    pushq %rbx
    pushq %rbp
    pushq %rdi
    pushq %rsi
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    subq $40, %rsp
    movq %rax, 32(%rsp)
    movabsq $0x1020304050607081, %rbx
    movabsq $0x2131415161718192, %rbp
    movabsq $0x32425262728293a3, %rdi
    movabsq $0x435363738393a4b4, %rsi
    movabsq $0x5464748494a4b5c5, %r12
    movabsq $0x65758595a5b5c6d6, %r13
    movabsq $0x768696a6b6c6d7e7, %r14
    movabsq $0x8797a7b7c7d7e8f8, %r15
    movq $5, %rcx
    leaq callback_context(%rip), %rdx
    call wsm_efi_callback
    cmpq $12, %rax
    jne .Lcallback_fail
    movabsq $0x1020304050607081, %rax
    cmpq %rax, %rbx
    jne .Lcallback_fail
    movabsq $0x2131415161718192, %rax
    cmpq %rax, %rbp
    jne .Lcallback_fail
    movabsq $0x32425262728293a3, %rax
    cmpq %rax, %rdi
    jne .Lcallback_fail
    movabsq $0x435363738393a4b4, %rax
    cmpq %rax, %rsi
    jne .Lcallback_fail
    movabsq $0x5464748494a4b5c5, %rax
    cmpq %rax, %r12
    jne .Lcallback_fail
    movabsq $0x65758595a5b5c6d6, %rax
    cmpq %rax, %r13
    jne .Lcallback_fail
    movabsq $0x768696a6b6c6d7e7, %rax
    cmpq %rax, %r14
    jne .Lcallback_fail
    movabsq $0x8797a7b7c7d7e8f8, %rax
    cmpq %rax, %r15
    jne .Lcallback_fail
    movq 32(%rsp), %rax
    addq $12, %rax
    jmp .Lrestore
.Lcallback_fail:
    xorq %rax, %rax
.Lrestore:
    addq $40, %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rsi
    popq %rdi
    popq %rbp
    popq %rbx
    ret
.Learly_fail:
    xorq %rax, %rax
    ret
.size wsm_efi_msabi_stub, .-wsm_efi_msabi_stub

.section .note.GNU-stack,"",@progbits
