# ===========================================================================
# nucleus-witness-gc-safepoint-certified-fixture.s
# #71 GC-ENTRY-CAPTURE-1: the allocator captures its entry state before any
# clobber and classifies it against a registered root map.
#
# The map certifies exactly two sites: a cons site (both %rsi and %rdx are
# roots) and a closure site (%rdx only; %rsi is the definition id, not a root).
# The fixture asserts CERTIFIED for both and a capture count of 2.
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
    leaq .Lroot_map(%rip), %rsi
    movl $2, %edx
    leaq .Lpc_base(%rip), %rcx
    call wsm_gc_root_map_register

    # --- certified cons site
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

    # --- certified closure site: %rdx is the environment, %rsi is not a root
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

# entry: pc_offset, kind, rsi_root, rdx_root, pad, pad32
.align 8
.Lroot_map:
    .quad .Lsite_cons - .Lpc_base
    .byte 1, 1, 1, 0
    .long 0
    .quad .Lsite_closure - .Lpc_base
    .byte 2, 0, 1, 0
    .long 0
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
