# ===========================================================================
# wsm-os-lisp: Pure x86-64 Freestanding Lisp Machine Runtime
# Architecture: Pure Lisp + x86-64 Assembly (Zero Rust, ADR-004)
# ===========================================================================

.text
.align 16

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
.set WSM_NIL,                 1                       # tag 001
.set WSM_CANONICAL_T,         0xFFFFFFFFFFFFFFFC      # (SYMBOL_ID_MAX << 3) | 4
.set WSM_TAG_MASK,            7
.set WSM_TAG_CONS,            0                       # tag 000
.set WSM_TAG_NIL,             1                       # tag 001
.set WSM_TAG_FIXNUM,          3                       # tag 011
.set WSM_TAG_SYMBOL,          4                       # tag 100
.set WSM_TAG_CLOSURE,         5                       # tag 101
.set WSM_TAG_CAPABILITY,      6                       # tag 110

.set ERR_OOM,                 1
.set ERR_TYPE,                2
.set ERR_SYMBOL,              3
.set ERR_ABI,                 4
.set ERR_OVERFLOW,            5

# RuntimeContext offsets:
#   offset  0: heap_base        (uint64_t*)
#   offset  8: heap_capacity    (uint64_t)
#   offset 16: heap_len         (uint64_t)
#   offset 24: closure_base     (uint64_t*)
#   offset 32: closure_capacity (uint64_t)
#   offset 40: closure_len      (uint64_t)
#   offset 48: condition_kind   (uint32_t)
#   offset 52: condition_source (uint32_t)
#   offset 56: condition_value  (uint64_t)
#   offset 64: failure_handler  (void (*)(RuntimeContext*, uint32_t))

# ---------------------------------------------------------------------------
# Word wsm_cons(RuntimeContext* ctx, Word car, Word cdr)
# Arguments: RDI = ctx, RSI = car, RDX = cdr
# Returns:   RAX = pointer to cons cell (16-byte aligned, tag 000)
# ---------------------------------------------------------------------------
.globl wsm_cons
.type wsm_cons, @function
wsm_cons:
    movq 16(%rdi), %rax             # heap_len
    cmpq 8(%rdi), %rax              # heap_len >= heap_capacity?
    jae .Lcons_oom

    movq %rax, %rcx
    shlq $4, %rcx                   # offset = len * 16
    addq 0(%rdi), %rcx              # cell_ptr = heap_base + offset

    movq %rsi, 0(%rcx)              # [cell_ptr + 0] = car
    movq %rdx, 8(%rcx)              # [cell_ptr + 8] = cdr

    incq %rax
    movq %rax, 16(%rdi)             # heap_len++

    movq %rcx, %rax                 # return cell_ptr (tag 000)
    ret

.Lcons_oom:
    movl $ERR_OOM, %esi
    xorq %rdx, %rdx
    jmp wsm_fail

# ---------------------------------------------------------------------------
# Word wsm_car(RuntimeContext* ctx, Word pair)
# Arguments: RDI = ctx, RSI = pair
# Returns:   RAX = car word
# ---------------------------------------------------------------------------
.globl wsm_car
.type wsm_car, @function
wsm_car:
    movq %rsi, %rax
    andq $WSM_TAG_MASK, %rax
    cmpq $WSM_TAG_CONS, %rax
    jne .Lcar_type_err

    # Check bounds: pair must be >= heap_base and < heap_base + len * 16
    movq 0(%rdi), %rcx              # heap_base
    cmpq %rcx, %rsi
    jb .Lcar_abi_err
    movq 16(%rdi), %rax             # len
    shlq $4, %rax
    addq %rcx, %rax                 # heap_limit
    cmpq %rax, %rsi
    jae .Lcar_abi_err

    movq 0(%rsi), %rax              # car
    ret

.Lcar_type_err:
    movl $ERR_TYPE, %esi
    movq %rsi, %rdx
    jmp wsm_fail

.Lcar_abi_err:
    movl $ERR_ABI, %esi
    movq %rsi, %rdx
    jmp wsm_fail

# ---------------------------------------------------------------------------
# Word wsm_cdr(RuntimeContext* ctx, Word pair)
# Arguments: RDI = ctx, RSI = pair
# Returns:   RAX = cdr word
# ---------------------------------------------------------------------------
.globl wsm_cdr
.type wsm_cdr, @function
wsm_cdr:
    movq %rsi, %rax
    andq $WSM_TAG_MASK, %rax
    cmpq $WSM_TAG_CONS, %rax
    jne .Lcdr_type_err

    movq 0(%rdi), %rcx              # heap_base
    cmpq %rcx, %rsi
    jb .Lcdr_abi_err
    movq 16(%rdi), %rax             # len
    shlq $4, %rax
    addq %rcx, %rax                 # heap_limit
    cmpq %rax, %rsi
    jae .Lcdr_abi_err

    movq 8(%rsi), %rax              # cdr
    ret

.Lcdr_type_err:
    movl $ERR_TYPE, %esi
    movq %rsi, %rdx
    jmp wsm_fail

.Lcdr_abi_err:
    movl $ERR_ABI, %esi
    movq %rsi, %rdx
    jmp wsm_fail

# ---------------------------------------------------------------------------
# Word wsm_eq(RuntimeContext* ctx, Word left, Word right)
# Arguments: RDI = ctx, RSI = left, RDX = right
# Returns:   RAX = CANONICAL_T if equal, NIL if not
# ---------------------------------------------------------------------------
.globl wsm_eq
.type wsm_eq, @function
wsm_eq:
    cmpq %rsi, %rdx
    jne 1f
    movabsq $WSM_CANONICAL_T, %rax
    ret
1:
    movq $WSM_NIL, %rax
    ret

# ---------------------------------------------------------------------------
# Word wsm_atom(RuntimeContext* ctx, Word value)
# Arguments: RDI = ctx, RSI = value
# Returns:   RAX = CANONICAL_T if atom (tag != 0), NIL if cons (tag == 0)
# ---------------------------------------------------------------------------
.globl wsm_atom
.type wsm_atom, @function
wsm_atom:
    movq %rsi, %rax
    andq $WSM_TAG_MASK, %rax
    cmpq $WSM_TAG_CONS, %rax
    je 1f
    movabsq $WSM_CANONICAL_T, %rax
    ret
1:
    movq $WSM_NIL, %rax
    ret

# ---------------------------------------------------------------------------
# Word wsm_closure_new(RuntimeContext* ctx, uint32_t def_id, Word env)
# Arguments: RDI = ctx, ESI = def_id, RDX = env
# Returns:   RAX = closure tagged pointer (tag 101)
# ---------------------------------------------------------------------------
.globl wsm_closure_new
.type wsm_closure_new, @function
wsm_closure_new:
    movq 40(%rdi), %rax             # closure_len
    cmpq 32(%rdi), %rax             # closure_len >= closure_capacity?
    jae .Lclosure_oom

    movq %rax, %rcx
    shlq $4, %rcx                   # 16 bytes per descriptor
    addq 24(%rdi), %rcx             # desc_ptr = closure_base + offset

    movl %esi, 0(%rcx)              # [desc_ptr + 0] = def_id
    movl $0, 4(%rcx)                # zero padding
    movq %rdx, 8(%rcx)              # [desc_ptr + 8] = env

    incq %rax
    movq %rax, 40(%rdi)             # closure_len++

    orq $WSM_TAG_CLOSURE, %rcx       # tag = 101
    movq %rcx, %rax
    ret

.Lclosure_oom:
    movl $ERR_OOM, %esi
    xorq %rdx, %rdx
    jmp wsm_fail

# ---------------------------------------------------------------------------
# uint32_t wsm_closure_definition(RuntimeContext* ctx, Word closure)
# Arguments: RDI = ctx, RSI = closure
# Returns:   EAX = def_id
# ---------------------------------------------------------------------------
.globl wsm_closure_definition
.type wsm_closure_definition, @function
wsm_closure_definition:
    movq %rsi, %rax
    andq $WSM_TAG_MASK, %rax
    cmpq $WSM_TAG_CLOSURE, %rax
    jne .Lclosure_type_err

    andq $-8, %rsi                  # strip tag
    movl 0(%rsi), %eax              # def_id
    ret

.Lclosure_type_err:
    movl $ERR_TYPE, %esi
    movq %rsi, %rdx
    jmp wsm_fail

# ---------------------------------------------------------------------------
# Word wsm_closure_environment(RuntimeContext* ctx, Word closure)
# Arguments: RDI = ctx, RSI = closure
# Returns:   RAX = env word
# ---------------------------------------------------------------------------
.globl wsm_closure_environment
.type wsm_closure_environment, @function
wsm_closure_environment:
    movq %rsi, %rax
    andq $WSM_TAG_MASK, %rax
    cmpq $WSM_TAG_CLOSURE, %rax
    jne .Lclosure_type_err

    andq $-8, %rsi
    movq 8(%rsi), %rax              # env
    ret

# ---------------------------------------------------------------------------
# void wsm_fail(RuntimeContext* ctx, uint32_t code, Word value)
# Arguments: RDI = ctx, ESI = code, RDX = value
# ---------------------------------------------------------------------------
.globl wsm_fail
.type wsm_fail, @function
wsm_fail:
    movl %esi, 48(%rdi)             # condition.kind = code
    movl $0, 52(%rdi)               # condition.source_id = 0
    movq %rdx, 56(%rdi)             # condition.offending_value = value

    movq 64(%rdi), %rax             # failure_handler
    testq %rax, %rax
    jz 1f
    call *%rax
1:
    ud2                             # halt if failure_handler returns

# ---------------------------------------------------------------------------
# Word wsm_pci_config_capability(RuntimeContext* ctx)
# Returns: 45-bit valid nonce capability descriptor with tag 110
# ---------------------------------------------------------------------------
.globl wsm_pci_config_capability
.type wsm_pci_config_capability, @function
wsm_pci_config_capability:
    # Nonce 0x150434954346, kind 0 (PciConfig), instance 0
    # Payload: (nonce << 19) | (instance << 3) | kind
    # Encoded word: (payload << 3) | 6
    movabsq $0x150434954346, %rax
    shlq $22, %rax
    orq $WSM_TAG_CAPABILITY, %rax
    ret

# ---------------------------------------------------------------------------
# Word wsm_pci_config_read16(RuntimeContext* ctx, Word cap, Word bus, Word dev, Word func, Word off)
# Reads 16-bit PCI configuration word. Arguments are fixnums.
# ---------------------------------------------------------------------------
.globl wsm_pci_config_read16
.type wsm_pci_config_read16, @function
wsm_pci_config_read16:
    # Decode fixnums: shift right by 3
    sarq $3, %rdx                   # bus
    sarq $3, %rcx                   # dev
    sarq $3, %r8                    # func
    sarq $3, %r9                    # off

    # Build PCI config address (port 0xCF8):
    # bit 31 = enable, bits 23:16 = bus, 15:11 = dev, 10:8 = func, 7:2 = off & 0xFC
    movl $0x80000000, %eax
    andl $0xFF, %edx
    shll $16, %edx
    orl %edx, %eax
    andl $0x1F, %ecx
    shll $11, %ecx
    orl %ecx, %eax
    andl $0x07, %r8d
    shll $8, %r8d
    orl %r8d, %eax
    movl %r9d, %edx
    andl $0xFC, %edx
    orl %edx, %eax

    movw $0xCF8, %dx
    outl %eax, %dx

    movw $0xCFC, %dx
    movl %r9d, %ecx
    andl $0x02, %ecx                # if offset bit 1 is set, read upper 16 bits
    shll $3, %ecx                   # cl = bit shift (0 or 16)
    inl %dx, %eax
    shrl %cl, %eax
    movzwl %ax, %eax

    # Encode as fixnum: (value << 3) | 3
    shlq $3, %rax
    orq $WSM_TAG_FIXNUM, %rax
    ret

.section .note.GNU-stack,"",@progbits
