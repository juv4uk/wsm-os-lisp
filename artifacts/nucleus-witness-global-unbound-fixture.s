# ===========================================================================
# nucleus-witness-global-unbound-fixture.s
# Constitutional negative: looking up a name that was never bound is a named
# SYMBOL condition, not NIL and not a silent zero word.
#
# Intended program: (f) where f was never defined.
# Expected serial: WSM-OS CONDITION schema=1 kind=SYMBOL source=0 value=44
#   value=44 is the offending name word (symbol id 5 << 3 | 4).
# ===========================================================================
.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $48, %rsp
    movq %rdi, %r12

    movq %r12, %rdi
    movabsq $44, %rsi               # name that was never bound
    call wsm_def_ref

    # wsm_def_ref must not return for an unbound name.
    movq %r12, %rdi
    movl $4, %esi                   # ABI: unbound lookup returned a value
    movq %rax, %rdx
    call wsm_fail

    addq $48, %rsp
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
