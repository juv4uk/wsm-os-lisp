# #86 target ABI v8 PredicateBit positive witness.
.text
.globl wsm_entry
.type wsm_entry, @function
.extern wsm_predicate_bit_0
.extern wsm_predicate_bit_1
.extern wsm_predicate_bit_bits

wsm_entry:
    pushq %rbx
    pushq %r12
    pushq %r13
    movq %rdi, %r13

    call wsm_predicate_bit_0
    movq %rax, %rbx
    movq %r13, %rdi
    call wsm_predicate_bit_0
    cmpq %rbx, %rax
    jne .Lfail

    movq %r13, %rdi
    call wsm_predicate_bit_1
    movq %rax, %r12
    movq %r13, %rdi
    call wsm_predicate_bit_1
    cmpq %r12, %rax
    jne .Lfail

    cmpq %r12, %rbx
    je .Lfail

    # Both are Boxed(tag 111), but neither aliases historical/common carriers.
    movq %rbx, %rax
    andq $7, %rax
    cmpq $7, %rax
    jne .Lfail
    movq %r12, %rax
    andq $7, %rax
    cmpq $7, %rax
    jne .Lfail

    cmpq $1, %rbx                    # NIL
    je .Lfail
    cmpq $2, %rbx                    # historical Tag::True
    je .Lfail
    cmpq $3, %rbx                    # Fixnum 0
    je .Lfail
    cmpq $11, %rbx                   # Fixnum 1
    je .Lfail
    movabsq $0xFFFFFFFFFFFFFFFC, %rax # canonical Symbol(t)
    cmpq %rax, %rbx
    je .Lfail

    cmpq $1, %r12
    je .Lfail
    cmpq $2, %r12
    je .Lfail
    cmpq $3, %r12
    je .Lfail
    cmpq $11, %r12
    je .Lfail
    movabsq $0xFFFFFFFFFFFFFFFC, %rax
    cmpq %rax, %r12
    je .Lfail

    movq %r13, %rdi
    movq %rbx, %rsi
    call wsm_predicate_bit_bits
    testl %eax, %eax
    jne .Lfail

    movq %r13, %rdi
    movq %r12, %rsi
    call wsm_predicate_bit_bits
    cmpl $1, %eax
    jne .Lfail

    # Contract 12 D1 ATOM: NIL is an atom -> exact D1:1 carrier.
    movq %r13, %rdi
    movq $1, %rsi
    call wsm_atom_predicate_bit
    cmpq %r12, %rax
    jne .Lfail

    # A pair is not an atom -> exact D1:0 carrier.
    movq %r13, %rdi
    leaq .Lpredicate_probe_pair(%rip), %rsi
    call wsm_atom_predicate_bit
    cmpq %rbx, %rax
    jne .Lfail

    # Contract 12 D1 EQ: identical admitted atoms -> D1:1.
    movq %r13, %rdi
    movq $1, %rsi
    movq $1, %rdx
    call wsm_eq_predicate_bit
    cmpq %r12, %rax
    jne .Lfail

    # Distinct admitted atoms -> D1:0 (not NIL).
    movq %r13, %rdi
    movq $1, %rsi
    movq $11, %rdx
    call wsm_eq_predicate_bit
    cmpq %rbx, %rax
    jne .Lfail

    movq $11, %rax                   # target Fixnum 1: witness passed
    jmp .Ldone

.Lfail:
    movq $3, %rax                    # target Fixnum 0
.Ldone:
    popq %r13
    popq %r12
    popq %rbx
    ret


.data
.balign 16
.Lpredicate_probe_pair:
    .quad 1
    .quad 1
