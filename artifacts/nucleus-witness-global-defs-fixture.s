# ===========================================================================
# nucleus-witness-global-defs-fixture.s
# Constitutional witness: bounded global definition table, ordinary and
# mutual recursion through name lookup, and live redefinition.
#
# Intended constitutional program (see the sibling .lisp projection):
#   (define f (lambda (x) (if (atom x) 'done (g (cdr x)))))
#   (define g (lambda (x) (f x)))
#   (f '(a b))                       => done
#   (define f (lambda (x) 'redefined))
#   (f '())                          => redefined
#
# Provenance: hand-written target assembly (fixture-provenance =
# hand-written-assembly). CML emission of the same shape is the obligation of
# CONSTITUTION-GLOBAL-ENV-PARITY, not of this witness.
#
# Word encodings used below (target ABI v8):
#   NIL            = 1
#   symbol id n    = (n << 3) | 4      a=1, b=2, f=3, g=4, done=5, redefined=6
#   closure        = arena pointer | 5
# ===========================================================================
.text
.globl wsm_entry
.type wsm_entry, @function
wsm_entry:
    pushq %r12
    subq $128, %rsp
    movq %rdi, %r12

    # --- (define f (lambda (x) (if (atom x) 'done (g (cdr x)))))  [def 1]
    movq %r12, %rdi
    movl $1, %esi                   # definition id 1
    movl $1, %edx                   # captured environment = NIL
    call wsm_closure_new
    movq %r12, %rdi
    movabsq $28, %rsi               # name = f
    movq %rax, %rdx
    call wsm_def_bind
    movq %rax, 0(%rsp)              # bind echoes the bound value

    # --- (define g (lambda (x) (f x)))  [def 2]
    movq %r12, %rdi
    movl $2, %esi
    movl $1, %edx
    call wsm_closure_new
    movq %r12, %rdi
    movabsq $36, %rsi               # name = g
    movq %rax, %rdx
    call wsm_def_bind

    # --- (cons a (cons b nil))
    movq %r12, %rdi
    movabsq $20, %rsi               # b
    movl $1, %edx
    call wsm_cons
    movq %rax, 8(%rsp)
    movq %r12, %rdi
    movabsq $12, %rsi               # a
    movq 8(%rsp), %rdx
    call wsm_cons
    movq %rax, 16(%rsp)

    # --- apply f, resolved by name, to that list
    movq %r12, %rdi
    movabsq $28, %rsi
    call wsm_def_ref
    movq %rax, 24(%rsp)
    movq %r12, %rdi
    movq 24(%rsp), %rsi
    call wsm_closure_definition
    cmpl $1, %eax
    jne .Lentry_bad_dispatch
    movq %r12, %rdi
    movq 24(%rsp), %rsi
    call wsm_closure_environment
    movq 16(%rsp), %rsi             # argument = the list
    movq %rax, %rdx                 # captured environment
    call .Ldef_1
    movq %rax, 32(%rsp)             # => done

    # --- (define f (lambda (x) 'redefined))  [def 3]: live redefinition
    movq %r12, %rdi
    movl $3, %esi
    movl $1, %edx
    call wsm_closure_new
    movq %r12, %rdi
    movabsq $28, %rsi               # name = f (rebind, not a new slot)
    movq %rax, %rdx
    call wsm_def_bind

    # --- rebinding must not consume capacity: f and g only
    movq %r12, %rdi
    call wsm_def_count
    cmpq $2, %rax
    jne .Lentry_bad_count

    # --- apply the redefined f
    movq %r12, %rdi
    movabsq $28, %rsi
    call wsm_def_ref
    movq %rax, 40(%rsp)
    movq %r12, %rdi
    movq 40(%rsp), %rsi
    call wsm_closure_definition
    cmpl $3, %eax
    jne .Lentry_bad_dispatch
    movq %r12, %rdi
    movq 40(%rsp), %rsi
    call wsm_closure_environment
    movl $1, %esi                   # argument = NIL
    movq %rax, %rdx
    call .Ldef_3
    movq %rax, 48(%rsp)             # => redefined

    # --- (cons done (cons redefined nil))
    movq %r12, %rdi
    movq 48(%rsp), %rsi
    movl $1, %edx
    call wsm_cons
    movq %rax, 56(%rsp)
    movq %r12, %rdi
    movq 32(%rsp), %rsi
    movq 56(%rsp), %rdx
    call wsm_cons

    addq $128, %rsp
    popq %r12
    ret

# ---------------------------------------------------------------------------
# definition 1: (lambda (x) (if (atom x) 'done (g (cdr x))))
# Arguments: RSI = argument, RDX = captured environment, R12 = context
# ---------------------------------------------------------------------------
.Ldef_1:
    subq $72, %rsp
    movq %rsi, 0(%rsp)
    movq %rdx, 8(%rsp)
    movq %r12, %rdi
    movq 0(%rsp), %rsi
    call wsm_atom
    movabsq $0xFFFFFFFFFFFFFFFC, %rcx
    cmpq %rcx, %rax
    je .Ldef_1_done

    movq %r12, %rdi
    movq 0(%rsp), %rsi
    call wsm_cdr
    movq %rax, 16(%rsp)             # (cdr x)
    movq %r12, %rdi
    movabsq $36, %rsi               # resolve g by name
    call wsm_def_ref
    movq %rax, 24(%rsp)
    movq %r12, %rdi
    movq 24(%rsp), %rsi
    call wsm_closure_definition
    cmpl $2, %eax
    jne .Ldef_1_bad
    movq %r12, %rdi
    movq 24(%rsp), %rsi
    call wsm_closure_environment
    movq 16(%rsp), %rsi
    movq %rax, %rdx
    call .Ldef_2
    addq $72, %rsp
    ret

.Ldef_1_done:
    movabsq $44, %rax               # done
    addq $72, %rsp
    ret

.Ldef_1_bad:
    movq %r12, %rdi
    movl $4, %esi                   # ABI: dispatch identity mismatch
    movq 24(%rsp), %rdx
    call wsm_fail

# ---------------------------------------------------------------------------
# definition 2: (lambda (x) (f x))  -- closes the mutual recursion
# ---------------------------------------------------------------------------
.Ldef_2:
    subq $72, %rsp
    movq %rsi, 0(%rsp)
    movq %rdx, 8(%rsp)
    movq %r12, %rdi
    movabsq $28, %rsi               # resolve f by name
    call wsm_def_ref
    movq %rax, 16(%rsp)
    movq %r12, %rdi
    movq 16(%rsp), %rsi
    call wsm_closure_definition
    cmpl $1, %eax
    jne .Ldef_2_bad
    movq %r12, %rdi
    movq 16(%rsp), %rsi
    call wsm_closure_environment
    movq 0(%rsp), %rsi
    movq %rax, %rdx
    call .Ldef_1
    addq $72, %rsp
    ret

.Ldef_2_bad:
    movq %r12, %rdi
    movl $4, %esi
    movq 16(%rsp), %rdx
    call wsm_fail

# ---------------------------------------------------------------------------
# definition 3: (lambda (x) 'redefined)
# ---------------------------------------------------------------------------
.Ldef_3:
    movabsq $52, %rax               # redefined
    ret

.Lentry_bad_dispatch:
    movq %r12, %rdi
    movl $4, %esi
    movq 24(%rsp), %rdx
    call wsm_fail

.Lentry_bad_count:
    movq %r12, %rdi
    movl $4, %esi
    movq %rax, %rdx                 # offending value = observed count
    call wsm_fail

.size wsm_entry, .-wsm_entry
.section .note.GNU-stack,"",@progbits
