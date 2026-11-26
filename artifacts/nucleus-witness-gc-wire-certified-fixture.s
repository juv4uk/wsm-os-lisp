# ===========================================================================
# nucleus-witness-gc-wire-certified-fixture.s
# #64 GC-ROOT-MAP-CONSUME-1: consume a CML_GC_ROOT_MAP_V1 record at the real
# allocation boundary.
#
# The wire names labels; a separate binding table resolves label -> final_pc.
# Two sites are certified: a cons site with %rsi+%rdx and one certified stack
# root, and a closure site with %rdx only.
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
    movl $2, %ecx
    call wsm_gc_wire_register

    # --- certified cons site (register roots + one stack root)
    movq %r12, %rdi
    movabsq $12, %rsi
    movabsq $20, %rdx
    call wsm_cons
.Lsite_cons:
    movq %rax, 0(%rsp)

    movq %r12, %rdi
    call wsm_gc_safepoint_state
    cmpl $1, %eax                   # CERTIFIED
    jne .Lbad_state
    movq %r12, %rdi
    call wsm_gc_safepoint_captures
    cmpq $1, %rax
    jne .Lbad_count

    # the certified stack root address must be caller_rsp_at_call + offset
    movq %r12, %rdi
    call wsm_gc_safepoint_stack_count
    cmpl $1, %eax
    jne .Lbad_state
    movq %rsp, %rax                 # caller_rsp_at_call == our rsp at the call
    movq %rax, 8(%rsp)
    movq %r12, %rdi
    xorl %esi, %esi
    call wsm_gc_safepoint_stack_root
    cmpq 8(%rsp), %rax
    jne .Lbad_state

    # --- certified closure site: %rdx only, no stack roots
    movq %r12, %rdi
    movl $7, %esi
    movabsq $12, %rdx
    call wsm_closure_new
.Lsite_closure:
    movq %r12, %rdi
    call wsm_gc_safepoint_state
    cmpl $1, %eax
    jne .Lbad_state
    movq %r12, %rdi
    call wsm_gc_safepoint_captures
    cmpq $2, %rax
    jne .Lbad_count

    movq 0(%rsp), %rax
    addq $64, %rsp
    popq %r12
    ret

.Lbad_state:
    movq %r12, %rdi
    movl $4, %esi
    movq %rax, %rdx
    call wsm_fail

.Lbad_count:
    movq %r12, %rdi
    movl $4, %esi
    movq %rax, %rdx
    call wsm_fail
.size wsm_entry, .-wsm_entry

.section .rodata
.align 16
.Lwire:
    .long 0x4752434D                # "GCRM"
    .short 1                        # version
    .short 2                        # entry_count
    .long 32                        # stride
    .long 0                         # flags
    .quad .Lpc_base                 # pc_base
    .quad 0
    # entry 0: label 1, cons, %rsi+%rdx, one stack root at frame offset 0
    .long 1
    .byte 1, 3, 0, 1
    .quad 64
    .long 0
    .long 0
    .quad 0
    # entry 1: label 2, closure, %rdx only, no stack roots
    .long 2
    .byte 2, 2, 0, 0
    .quad 0
    .long 0
    .long 0
    .quad 0
.align 16
.Lbindings:
    .long 1
    .long 0
    .quad .Lsite_cons
    .long 2
    .long 0
    .quad .Lsite_closure
.section .note.GNU-stack,"",@progbits
