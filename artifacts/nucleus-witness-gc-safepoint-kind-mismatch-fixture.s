# ===========================================================================
# nucleus-witness-gc-safepoint-kind-mismatch-fixture.s
# #71: metadata that names the same final PC but the wrong allocator kind must
# reject, not silently fall through to the non-collecting path.
#
# The map declares kind = closure (2) for a site that is actually reached by
# wsm_cons. Expected: ABI condition, source = 0x47430001 (GC kind mismatch),
# value = the site offset from the declared pc_base.
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
    movl $1, %edx
    leaq .Lpc_base(%rip), %rcx
    call wsm_gc_root_map_register

    movq %r12, %rdi
    movabsq $12, %rsi
    movabsq $20, %rdx
    call wsm_cons
.Lsite_cons:
    # Must never return: the declared kind contradicts this allocator.
    movq %r12, %rdi
    movl $4, %esi
    movq %rax, %rdx
    call wsm_fail

.align 8
.Lroot_map:
    .long .Lsite_cons - .Lpc_base
    .byte 2, 3, 0, 0                # declared closure, reached by cons
    .quad 0
    .long 0
    .long 0
    .quad 0
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
