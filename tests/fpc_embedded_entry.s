.section .rodata
.align 8
callback_context:
    .quad 7

.section .bss
.align 16
stack_bottom:
    .skip 4096
stack_top:

.section .text
.global _start
.global wsm_efi_msabi_stub
.extern wsm_fpc_embedded_probe
.extern wsm_invoke_efi_probe
.extern wsm_efi_callback

# Microsoft x64 ABI callee used as a stand-in for an EFI function pointer.
# Validate callee-entry alignment, touch all four 8-byte home slots, and
# return RCX + RDX + R8 + R9.
wsm_efi_msabi_stub:
    movq %rsp, %rax
    andq $15, %rax
    cmpq $8, %rax
    jne .Lmsabi_bad
    movabsq $0x1122334455667788, %rax
    movq %rax, 8(%rsp)
    movq %rax, 16(%rsp)
    movq %rax, 24(%rsp)
    movq %rax, 32(%rsp)
    leaq (%rcx,%rdx), %rax
    addq %r8, %rax
    addq %r9, %rax
    ret
.Lmsabi_bad:
    movq $-1, %rax
    ret

_start:
    leaq stack_top(%rip), %rsp
    andq $-16, %rsp

    # System V AMD64 cdecl control: 40 + 2 = 42.
    movl $40, %edi
    movl $2, %esi
    call wsm_fpc_embedded_probe
    cmpl $42, %eax
    jne .Lfail

    # Pascal caller invokes an EFI-shaped function pointer using MS ABI.
    leaq wsm_efi_msabi_stub(%rip), %rdi
    call wsm_invoke_efi_probe
    cmpq $10, %rax
    jne .Lfail

    # External caller invokes a Pascal callback declared MS_ABI_Default.
    # Verify Microsoft callee-saved registers survive the callback.
    movabsq $0x1122334455667788, %rbx
    movabsq $0x2233445566778899, %rdi
    movabsq $0x33445566778899aa, %rsi
    movabsq $0x445566778899aabb, %r12
    movabsq $0x5566778899aabbcc, %r13
    movabsq $0x66778899aabbccdd, %r14
    movabsq $0x778899aabbccddee, %r15
    movq $5, %rcx
    leaq callback_context(%rip), %rdx
    subq $32, %rsp
    call wsm_efi_callback
    addq $32, %rsp
    cmpq $12, %rax
    jne .Lfail

    movabsq $0x1122334455667788, %rax
    cmpq %rax, %rbx
    jne .Lfail
    movabsq $0x2233445566778899, %rax
    cmpq %rax, %rdi
    jne .Lfail
    movabsq $0x33445566778899aa, %rax
    cmpq %rax, %rsi
    jne .Lfail
    movabsq $0x445566778899aabb, %rax
    cmpq %rax, %r12
    jne .Lfail
    movabsq $0x5566778899aabbcc, %rax
    cmpq %rax, %r13
    jne .Lfail
    movabsq $0x66778899aabbccdd, %rax
    cmpq %rax, %r14
    jne .Lfail
    movabsq $0x778899aabbccddee, %rax
    cmpq %rax, %r15
    jne .Lfail

.Lpass:
    movw $0xF4, %dx
    movl $0x10, %eax
    outl %eax, %dx
    hlt
    jmp .Lpass

.Lfail:
    movw $0xF4, %dx
    movl $0x11, %eax
    outl %eax, %dx
    hlt
    jmp .Lfail

.section .note.GNU-stack,"",@progbits
