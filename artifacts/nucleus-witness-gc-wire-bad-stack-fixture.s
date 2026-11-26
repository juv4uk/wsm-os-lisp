# ===========================================================================
# nucleus-witness-gc-wire-bad-stack-fixture.s
# #64: a stack root whose certified offset does not fit inside the certified
# frame must be rejected. 64 + 8 > frame_size 64.
# Expected: kind=ABI source=1195573252 (0x47430004) value=0
# ===========================================================================
.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $64, %rsp
    movq %rdi, %r12

.Lpc_base:
    movq %r12, %rdi
    leaq .Lwire(%rip), %rsi
    leaq .Lbindings(%rip), %rdx
    movl $1, %ecx
    call wsm_gc_wire_register

    movq %r12, %rdi
    movl $4, %esi
    movq %rax, %rdx
    call wsm_fail
.size wsm_entry, .-wsm_entry

.section .rodata
.align 16
.Lwire:
    .long 0x4752434D
    .short 1
    .short 1
    .long 32
    .long 0
    .quad .Lpc_base
    .quad 0
    .long 1
    .byte 1, 3, 0, 1                # one stack root
    .quad 64                        # frame_size 64
    .long 64                        # offset 64 -> 64+8 exceeds the frame
    .long 0
    .quad 0
.align 16
.Lbindings:
    .long 1
    .long 0
    .quad .Lpc_base
.section .note.GNU-stack,"",@progbits
