# ===========================================================================
# nucleus-witness-alloc-oom-fixture.s
# Named-failure half of the ADR-006 P2 parity matrix: allocate until the cons
# arena is exhausted. Exhaustion must be a named OOM condition, never a wrap,
# a silent zero or a reset.
#
# Expected serial:
#   WSM-OS BOOT schema=1 arch=x86_64 status=ok
#   WSM-OS CONDITION schema=1 kind=OOM source=0 value=0
# ===========================================================================
.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $16, %rsp
    movq %rdi, %r12

.Lalloc_loop:
    movq %r12, %rdi
    movl $1, %esi                   # NIL
    movl $1, %edx                   # NIL
    call wsm_cons
    jmp .Lalloc_loop                # 4096 cells, then a named OOM

.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
