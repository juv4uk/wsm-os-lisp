# ===========================================================================
# nucleus-witness-global-full-fixture.s
# Constitutional negative: the global definition table is bounded. Binding one
# more name than the arena holds is a deterministic named OOM failure, never a
# silent overwrite of a live definition and never corruption.
#
# Arena: 256 entries (src/entry.s::def_arena). The fixture binds 256 distinct
# names, then attempts the 257th.
# Expected serial: WSM-OS CONDITION schema=1 kind=OOM source=0 value=0
# ===========================================================================
.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    pushq %rbx
    subq $56, %rsp
    movq %rdi, %r12

    movl $1, %ebx                   # name id 1 .. 257
.Lbind_loop:
    movq %rbx, %rsi
    shlq $3, %rsi
    orq $4, %rsi                    # symbol word for this name id
    movq %r12, %rdi
    movl $1, %edx                   # value = NIL
    call wsm_def_bind

    incl %ebx
    cmpl $257, %ebx                 # names 1..256 fill the arena exactly
    jb .Lbind_loop

    # The 257th distinct name has no slot left and must fail closed.
    movq %rbx, %rsi
    shlq $3, %rsi
    orq $4, %rsi
    movq %r12, %rdi
    movl $1, %edx
    call wsm_def_bind

    # Exhaustion must not return normally.
    movq %r12, %rdi
    movl $4, %esi                   # ABI: table exhaustion returned a value
    movq %rax, %rdx
    call wsm_fail

    addq $56, %rsp
    popq %rbx
    popq %r12
    ret
.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
