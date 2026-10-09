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
.set WSM_TAG_BOXED,           7                       # tag 111

# Target ABI v8 exact PredicateBit representation. This runtime admits one
# boot-session RuntimeContext, so handles 1/2 are its two canonical singleton
# objects for this session. The target transports bit 0/1 only; SENS owns
# predicate meaning.
.set BOXED_KIND_PREDICATE_BIT, 5
.set PREDICATE_BIT0_HANDLE,    1
.set PREDICATE_BIT1_HANDLE,    2
.set PREDICATE_BIT0_WORD,      15                      # (1 << 3) | 7
.set PREDICATE_BIT1_WORD,      23                      # (2 << 3) | 7

# WSM_TAG_BOXED is injected from the pinned neutral target-contract v6.
# Do not duplicate its raw wire value in this runtime.
.ifndef WSM_TAG_BOXED
.error "WSM_TAG_BOXED must be supplied from pinned target contract"
.endif

# Runtime-private boxed-table discriminant. This number is never exposed in
# the WSM word; target-contract owns only the Boxed wire tag/handle shape.
.set WSM_BOXED_KIND_RATIONAL, 1

.set ERR_OOM,                 1
.set ERR_TYPE,                2
.set ERR_SYMBOL,              3
.set ERR_ABI,                 4
.set ERR_OVERFLOW,            5

# ---------------------------------------------------------------------------
# MMIO failure-source codes (structured condition `source=`, kind=ABI).
# Ported from the pre-ADR-004 kernel (commit 7b66ca8) so the pure-ASM path
# reports the same device/ABI failure vocabulary as the historical witnesses.
# Read and write directions stay distinct, mirroring the legacy pairs.
#   0x4D494F01 decode_fixnum (read)      0x4D494F04 decode_fixnum (write)
#   0x4D494F02 capability/bounds (read)  0x4D494F05 capability/bounds (write)
#   0x4D494F03 not provisioned (read)    0x4D494F06 not provisioned (write)
#   0x4D494F07 mapping unavailable (read) 0x4D494F08 mapping unavailable (write)
#   0x4D494F09 address overflow (read)   0x4D494F0A address overflow (write)
# 0x4D494F00 is pure-ASM-only: fail-closed provisioning of the MMIO
# capability itself (direction-neutral); see docs/MMIO-MUTATION-...md.
# ---------------------------------------------------------------------------
.set MMIO_ERR_DECODE_READ,          0x4D494F01
.set MMIO_ERR_CAPABILITY_READ,      0x4D494F02
.set MMIO_ERR_NOT_PROVISIONED_READ, 0x4D494F03
.set MMIO_ERR_DECODE_WRITE,         0x4D494F04
.set MMIO_ERR_CAPABILITY_WRITE,     0x4D494F05
.set MMIO_ERR_NOT_PROVISIONED_WRITE,0x4D494F06
.set MMIO_ERR_MAPPING_READ,         0x4D494F07
.set MMIO_ERR_MAPPING_WRITE,        0x4D494F08
.set MMIO_ERR_OVERFLOW_READ,        0x4D494F09
.set MMIO_ERR_OVERFLOW_WRITE,       0x4D494F0A
.set MMIO_ERR_PROVISIONING,         0x4D494F00

# ---------------------------------------------------------------------------
# Boot handoff / MMIO target state (ADR-004: target owns mechanism).
# The only values lifted from the Rust BootInfo are the physical-memory
# offset (a runtime fact) and, later, the provisioned MMIO region resolved
# through a live PCI walk. Neither CML nor Lisp ever sees physical addresses.
# ---------------------------------------------------------------------------
.section .bss
.align 16
# physical_memory_offset: u64; 0 means "not handed off / map unavailable".
.globl wsm_target_phys_mem_offset
wsm_target_phys_mem_offset:
    .skip 8
# Provisioned MMIO region (valid == 1 after successful provisioning).
.globl wsm_mmio_region_base
wsm_mmio_region_base:
    .skip 8                          # virtual address of provisioned region
.globl wsm_mmio_region_len
wsm_mmio_region_len:
    .skip 8                          # byte length from VirtIO PCI capability
.globl wsm_mmio_region_valid
wsm_mmio_region_valid:
    .skip 8

# M2 / #84: one target-owned page used only as the first bounded DMA arena
# witness.  Raw addresses remain target mechanism and are never exposed as
# SENS/WSM semantic values or CML runtime imports.
.p2align 12
.globl wsm_dma_arena
wsm_dma_arena:
    .skip 4096
wsm_dma_arena_end:

.globl wsm_dma_arena_phys
wsm_dma_arena_phys:
    .skip 8
.globl wsm_dma_arena_valid
wsm_dma_arena_valid:
    .skip 8

# M2 / #82 modern VirtIO block queue0 mechanism state.
# These are target-only transport facts, never SENS semantic identities.
.globl wsm_virtio_blk_bdf
wsm_virtio_blk_bdf:
    .skip 8
.globl wsm_virtio_notify_base
wsm_virtio_notify_base:
    .skip 8
.globl wsm_virtio_notify_len
wsm_virtio_notify_len:
    .skip 8
.globl wsm_virtio_notify_multiplier
wsm_virtio_notify_multiplier:
    .skip 8
.globl wsm_virtio_notify_valid
wsm_virtio_notify_valid:
    .skip 8
.globl wsm_virtio_queue0_notify_addr
wsm_virtio_queue0_notify_addr:
    .skip 8
.globl wsm_virtio_queue0_size
wsm_virtio_queue0_size:
    .skip 8
.globl wsm_virtio_flush_supported
wsm_virtio_flush_supported:
    .skip 8
.globl wsm_virtio_queue0_valid
wsm_virtio_queue0_valid:
    .skip 8
.globl wsm_virtio_block_roundtrip_stage
wsm_virtio_block_roundtrip_stage:
    .skip 8
.globl wsm_virtio_block_completed_requests
wsm_virtio_block_completed_requests:
    .skip 8
.globl wsm_virtio_persistence_stage
wsm_virtio_persistence_stage:
    .skip 8

# Exact target v8 PredicateBit singleton descriptors. These bytes are mechanism
# only. Handles are session-local and never carry SENS NO/YES semantics.
.section .data
.align 2
wsm_predicate_bit_table:
    .byte BOXED_KIND_PREDICATE_BIT, 0
    .byte BOXED_KIND_PREDICATE_BIT, 1

.section .text
.align 16

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
#   offset 72: boxed_base       (24-byte runtime-private entries)
#   offset 80: boxed_capacity   (entry count)
#   offset 88: boxed_len        (entry count)

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
    movq %rsi, %rdx                 # offending value = the bad word
    movl $ERR_TYPE, %esi
    jmp wsm_fail

.Lcar_abi_err:
    movq %rsi, %rdx                 # offending value = the bad word
    movl $ERR_ABI, %esi
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
    movq %rsi, %rdx                 # offending value = the bad word
    movl $ERR_TYPE, %esi
    jmp wsm_fail

.Lcdr_abi_err:
    movq %rsi, %rdx                 # offending value = the bad word
    movl $ERR_ABI, %esi
    jmp wsm_fail

# ---------------------------------------------------------------------------
# Word wsm_rational_new(RuntimeContext* ctx, int64_t numerator, int64_t denominator)
# Arguments: RDI = ctx, RSI = numerator, RDX = denominator
# Returns:   RAX = target-contract Boxed(handle), handle is 1-based.
#
# This is representation mechanism only. The compiler/shared IR supplies the
# already-canonical exact pair. Runtime deliberately performs no gcd/reduction
# and owns no Lisp arithmetic law.
# ---------------------------------------------------------------------------
.globl wsm_rational_new
.type wsm_rational_new, @function
wsm_rational_new:
    testq %rdx, %rdx
    jz .Lrational_new_abi_err

    movq 88(%rdi), %rax             # boxed_len / zero-based index
    cmpq 80(%rdi), %rax             # len >= capacity?
    jae .Lrational_oom

    movq %rax, %rcx
    imulq $24, %rcx, %rcx
    addq 72(%rdi), %rcx             # entry = boxed_base + index*24

    movq $WSM_BOXED_KIND_RATIONAL, 0(%rcx)
    movq %rsi, 8(%rcx)              # exact numerator fact
    movq %rdx, 16(%rcx)             # exact denominator fact

    incq %rax                       # 1-based handle; zero is never returned
    movq %rax, 88(%rdi)             # boxed_len = old_len + 1

    shlq $3, %rax
    orq $WSM_TAG_BOXED, %rax
    ret

.Lrational_new_abi_err:
    # denominator zero is an invalid stored representation here, not a Lisp
    # DivisionByZero observation: this constructor performs no division.
    movl $ERR_ABI, %esi
    # RDX is already the offending zero denominator.
    jmp wsm_fail

.Lrational_oom:
    movl $ERR_OOM, %esi
    xorq %rdx, %rdx
    jmp wsm_fail

# ---------------------------------------------------------------------------
# int64_t wsm_rational_numerator(RuntimeContext* ctx, Word rational)
# int64_t wsm_rational_denominator(RuntimeContext* ctx, Word rational)
#
# Both accessors validate the neutral Boxed wire shape, runtime ownership/range
# and the runtime-private Rational kind before exposing representation facts.
# ---------------------------------------------------------------------------
.globl wsm_rational_numerator
.type wsm_rational_numerator, @function
wsm_rational_numerator:
    movl $8, %r8d
    jmp .Lrational_access

.globl wsm_rational_denominator
.type wsm_rational_denominator, @function
wsm_rational_denominator:
    movl $16, %r8d

.Lrational_access:
    movq %rsi, %rax
    andq $WSM_TAG_MASK, %rax
    cmpq $WSM_TAG_BOXED, %rax
    jne .Lrational_type_err

    movq %rsi, %rax
    shrq $3, %rax                   # 1-based handle
    testq %rax, %rax
    jz .Lrational_handle_abi_err
    decq %rax                       # zero-based index
    cmpq 88(%rdi), %rax             # must name an allocated entry
    jae .Lrational_handle_abi_err

    movq %rax, %rcx
    imulq $24, %rcx, %rcx
    addq 72(%rdi), %rcx
    cmpq $WSM_BOXED_KIND_RATIONAL, 0(%rcx)
    jne .Lrational_type_err

    movq (%rcx,%r8,1), %rax
    ret

.Lrational_type_err:
    movq %rsi, %rdx
    movl $ERR_TYPE, %esi
    jmp wsm_fail

.Lrational_handle_abi_err:
    movq %rsi, %rdx
    movl $ERR_ABI, %esi
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
# Target ABI v8 PredicateBit representation-only accessors.
#
# These do not define truth, branch selection or predicate semantics.
# They only expose two canonical boxed singleton words and recover exact bit
# 0/1 after validating the local runtime-owned descriptor.
# ---------------------------------------------------------------------------
.globl wsm_predicate_bit_0
.type wsm_predicate_bit_0, @function
wsm_predicate_bit_0:
    movl $PREDICATE_BIT0_WORD, %eax
    ret

.globl wsm_predicate_bit_1
.type wsm_predicate_bit_1, @function
wsm_predicate_bit_1:
    movl $PREDICATE_BIT1_WORD, %eax
    ret

.globl wsm_predicate_bit_bits
.type wsm_predicate_bit_bits, @function
wsm_predicate_bit_bits:
    movq %rsi, %rdx                  # preserve offending word for fail-closed path
    movq %rsi, %rax
    movq %rax, %rcx
    andq $WSM_TAG_MASK, %rcx
    cmpq $WSM_TAG_BOXED, %rcx
    jne .Lpredicate_bits_type

    shrq $3, %rax
    cmpq $PREDICATE_BIT0_HANDLE, %rax
    je .Lpredicate_bits_0
    cmpq $PREDICATE_BIT1_HANDLE, %rax
    je .Lpredicate_bits_1
    jmp .Lpredicate_bits_abi

.Lpredicate_bits_0:
    leaq wsm_predicate_bit_table(%rip), %rcx
    cmpb $BOXED_KIND_PREDICATE_BIT, 0(%rcx)
    jne .Lpredicate_bits_abi
    cmpb $0, 1(%rcx)
    jne .Lpredicate_bits_abi
    xorl %eax, %eax
    ret

.Lpredicate_bits_1:
    leaq wsm_predicate_bit_table+2(%rip), %rcx
    cmpb $BOXED_KIND_PREDICATE_BIT, 0(%rcx)
    jne .Lpredicate_bits_abi
    cmpb $1, 1(%rcx)
    jne .Lpredicate_bits_abi
    movl $1, %eax
    ret

.Lpredicate_bits_type:
    movl $ERR_TYPE, %esi
    jmp wsm_fail

.Lpredicate_bits_abi:
    movl $ERR_ABI, %esi
    jmp wsm_fail

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
    movq %rsi, %rdx                 # offending value = the bad word
    movl $ERR_TYPE, %esi
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
# Generic/Lisp condition: source_id stays 0 (closed error vocabulary).
# ---------------------------------------------------------------------------
.globl wsm_fail
.type wsm_fail, @function
wsm_fail:
    movq %rdx, %rcx                 # offending value -> RCX
    xorl %edx, %edx                 # condition.source_id = 0
    jmp wsm_fail_src

# ---------------------------------------------------------------------------
# void wsm_fail_src(RuntimeContext* ctx, uint32_t code, uint32_t source, Word value)
# Arguments: RDI = ctx, ESI = code, EDX = source, RCX = value
# Device/ABI failures carry a substrate source code so a transport/device
# failure is distinguishable from a Lisp semantic failure in the condition.
# ---------------------------------------------------------------------------
.globl wsm_fail_src
.type wsm_fail_src, @function
wsm_fail_src:
    movl %esi, 48(%rdi)             # condition.kind = code
    movl %edx, 52(%rdi)             # condition.source_id = source
    movq %rcx, 56(%rdi)             # condition.offending_value = value

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
    # Payload: (nonce << 16) | (instance << 3) | kind
    # Encoded word: (payload << 3) | 6
    movabsq $0x150434954346, %rax
    shlq $19, %rax
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

# ---------------------------------------------------------------------------
# Boot handoff: void wsm_boot_handoff(void)
# Reads the BootInfo pointer saved by entry.s, extracts the runtime
# physical-memory offset (Optional<u64> at BootInfo+0x58 tag / +0x60 value)
# and stores it in target state. Missing or None leaves offset = 0 so MMIO
# provisioning fails closed. See docs/TARGET-BOOT-HANDOFF-ABI.md.
# Argument: none (saved_boot_info is a symbol owned by entry.s)
# ---------------------------------------------------------------------------
.globl wsm_boot_handoff
.type wsm_boot_handoff, @function
wsm_boot_handoff:
    pushq %rbx
.ifdef WSM_FORCE_NO_PHYS_MAP
    # Test-only mutation (issue #40): force the "bootloader did not provide the
    # physical-memory mapping" state so the fail-closed MMIO path is witnessable
    # on the canonical pure-ASM target. Never defined in production builds; the
    # flag is injected by `as --defsym` from build-uefi-image.sh.
    movq $0, wsm_target_phys_mem_offset(%rip)
    call .Lprepare_dma_arena
    popq %rbx
    ret
.endif
    # Load saved boot info pointer
    movq saved_boot_info(%rip), %rbx
    testq %rbx, %rbx
    jz .Lhandoff_done_nooffset

    # Optional<u64> tag at +0x58: 0x00 == Some, 0x01 == None
    cmpb $0, 0x58(%rbx)
    jne .Lhandoff_done_nooffset

    # Value at +0x60 (u64, little endian)
    movq 0x60(%rbx), %rax
    movq %rax, wsm_target_phys_mem_offset(%rip)
    call .Lprepare_dma_arena
    popq %rbx
    ret

.Lhandoff_done_nooffset:
    movq $0, wsm_target_phys_mem_offset(%rip)
    call .Lprepare_dma_arena
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# Word wsm_mmio_capability(RuntimeContext* ctx)
# Returns a provisioned MMIO capability (tag 110) or fails closed.
#
# The substrate provisions the region once at target boot time by resolving
# the live VirtIO COMMON_CFG PCI capability: walk BARs, decode the memory
# BAR, verify the BAR physical address is covered by the bootloader's
# physical-memory mapping (page walk), then record the translated virtual
# base + length. Lisp/CML never sees physical addresses.
# ---------------------------------------------------------------------------
.globl wsm_mmio_capability
.type wsm_mmio_capability, @function
# Provision MMIO at cold boot (idempotent): perform the PCI discovery here so
# that wsm_mmio_capability returns a stable descriptor afterwards and no PCI
# scan occurs on every access.
.globl wsm_target_provision_mmio
.type wsm_target_provision_mmio, @function
wsm_target_provision_mmio:
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    subq $40, %rsp

    # Skip if already provisioned
    movq wsm_mmio_region_valid(%rip), %rax
    testq %rax, %rax
    jnz .Lprov_done

    # No physical memory offset -> fail closed
    movq wsm_target_phys_mem_offset(%rip), %r15
    testq %r15, %r15
    jz .Lprov_fail_nomap

    # Scan bus 0 for virtio-blk (vendor=0x1AF4, class=0x0104).
    # Returns dev in EAX (device<<3 | function), or 0 if not found.
    call .Lpci_scan_virtio_blk
    testl %eax, %eax
    jz .Lprov_fail_nodev
    movl %eax, %r12d          # store discovered BDF
    movl %r12d, wsm_virtio_blk_bdf(%rip)

    # ---- PCI status (config offset 0x04) bit 16 (status bit 4): cap list ----
    movl %r12d, %edi
    movl $0x04, %esi
    call .Lraw_pci_read32
    testl $0x00100000, %eax           # Status & (1 << 4) == capabilities list
    jz .Lprov_fail_nocap

    # ---- Capabilities pointer at PCI config offset 0x34 ----
    movl %r12d, %edi
    movl $0x34, %esi
    call .Lraw_pci_read32
    movl %eax, %r13d
    andl $0xFC, %r13d                 # cap_offset (dword-aligned)

.Lprov_cap_loop:
    cmpl $0x40, %r13d
    jl .Lprov_fail_nocap
    cmpl $0x100, %r13d
    jge .Lprov_fail_nocap

    # Dword at cap_offset:
    #   byte0 = cap_id, byte3 = cfg_type (VirtIO-specific)
    movl %r12d, %edi
    movl %r13d, %esi
    call .Lraw_pci_read32
    movl %eax, %r14d

    # VIRTIO_PCI_CAP_COMMON_CFG == 0x09 && cfg_type == 1
    movl %r14d, %eax
    andl $0xFF, %eax
    cmpl $0x09, %eax
    jne .Lprov_next_cap
    movl %r14d, %eax
    shrl $24, %eax
    cmpl $1, %eax
    jne .Lprov_next_cap

    # Found COMMON_CFG: byte4 = bar, dword+8 = offset_in_bar, dword+12 = length.
    # Read all three into callee-saved registers before calling helpers, which
    # clobber the argument registers.
    movl %r12d, %edi
    movl %r13d, %esi
    addl $4, %esi
    call .Lraw_pci_read32
    movzbl %al, %ebx                # bar_num

    movl %r12d, %edi
    movl %r13d, %esi
    addl $8, %esi
    call .Lraw_pci_read32
    movl %eax, %r14d                # offset_in_bar (zero-extended to %r14)

    movl %r12d, %edi
    movl %r13d, %esi
    addl $12, %esi
    call .Lraw_pci_read32
    movl %eax, %r13d                # length (zero-extended to %r13)

    # ---- Decode BAR physical address ----
    movl %r12d, %edi
    movl %ebx, %esi
    call .Lraw_bar_phys             # RAX = bar physical address (0 if I/O BAR)
    testq %rax, %rax
    jz .Lprov_fail_nobar

    # phys = bar_phys + offset_in_bar
    addq %r14, %rax
    movq %rax, %rbx                 # rbx = phys base of COMMON_CFG (preserved across call)
    movq %rbx, %rcx

    # ---- Verify BAR physical address is covered by the physical-memory
    #      mapping. Translated caller: virt = phys + phys_mem_offset.
    #      We walk the active page tables (CR3) to prove the mapping exists
    #      instead of assuming identity. ----
    movq %rcx, %rdi
    movq %r15, %rsi
    call .Lpage_walk_present        # RAX = 1 if phys (+ offset) is mapped
    testq %rax, %rax
    jz .Lprov_fail_notmapped

    # virt_base = phys + phys_mem_offset
    movq %rbx, %rcx
    addq %r15, %rcx
    movq %rcx, wsm_mmio_region_base(%rip)
    movq %r13, wsm_mmio_region_len(%rip)
    movq $1, wsm_mmio_region_valid(%rip)

    # #82 needs NOTIFY_CFG in addition to the historical COMMON_CFG slice.
    # Failure leaves COMMON_CFG valid for old MMIO witnesses but queue0 closed.
    call .Lprovision_virtio_notify

    jmp .Lprov_done

.Lprov_next_cap:
    # cap_next in byte1; next = cap_next & 0xFC
    movl %r14d, %eax
    shrl $8, %eax
    andl $0xFC, %eax
    testl %eax, %eax
    jz .Lprov_fail_nocap
    movl %eax, %r13d
    jmp .Lprov_cap_loop

# Provisioning outcome sentinels in wsm_mmio_region_valid:
#   0 = not yet provisioned (initial state)
#   1 = provisioned (only success value)
#   2 = no physical-memory offset (BootInfo missing/None)
#   3 = no capabilities list / no COMMON_CFG cap
#   4 = BAR decode failed (I/O BAR or missing)
#   5 = BAR phys not covered by physical-memory mapping
#   6 = virtio-blk device not found on PCI bus
# Any non-1 value is translated by wsm_mmio_capability into fail-closed.
.Lprov_fail_nomap:
    movq $2, wsm_mmio_region_valid(%rip)
    jmp .Lprov_done
.Lprov_fail_nodev:
    movq $6, wsm_mmio_region_valid(%rip)
    jmp .Lprov_done
.Lprov_fail_nocap:
    movq $3, wsm_mmio_region_valid(%rip)
    jmp .Lprov_done
.Lprov_fail_nobar:
    movq $4, wsm_mmio_region_valid(%rip)
    jmp .Lprov_done
.Lprov_fail_notmapped:
    movq $5, wsm_mmio_region_valid(%rip)
    jmp .Lprov_done

.Lprov_done:
    addq $40, %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    ret

# Error code for a capability request before provisioning succeeded.
# We encode a small sentinel: valid==2..4 means "failed provisioning".
# ---------------------------------------------------------------------------
.globl wsm_mmio_capability
.type wsm_mmio_capability, @function
wsm_mmio_capability:
    # Provision once (idempotent). Preserve RDI (ctx) across the call since
    # wsm_fail expects the context pointer in RDI.
    pushq %rdi
    call wsm_target_provision_mmio

    movq wsm_mmio_region_valid(%rip), %rax
    cmpq $1, %rax
    jne .Lcap_fail

    popq %rdi
    # Nonce 0x1A0495124347, kind 1 (Mmio), instance 0
    # Payload: (nonce << 16) | (instance << 3) | kind
    # Encoded word: (payload << 3) | 6
    movabsq $0x1A0495124347, %rax
    shlq $19, %rax
    orq $WSM_TAG_CAPABILITY, %rax
    ret

.Lcap_fail:
    popq %rdi
    # Fail closed: ABI violation (4); source = MMIO provisioning, and the
    # offending value is the provisioning sentinel (2..6) that records which
    # step failed (no offset / no cap / bad BAR / not mapped / no device).
    movq wsm_mmio_region_valid(%rip), %rcx
    movl $ERR_ABI, %esi
    movl $MMIO_ERR_PROVISIONING, %edx
    jmp wsm_fail_src

# ---------------------------------------------------------------------------
# Word wsm_mmio_read32(RuntimeContext* ctx, Word cap, Word offset)
# Reads 32-bit MMIO value from the provisioned region.
# Args: RDI = ctx, RSI = cap, RDX = offset (fixnum)
# ---------------------------------------------------------------------------
.globl wsm_mmio_read32
.type wsm_mmio_read32, @function
wsm_mmio_read32:
    # Validate capability identity first.
    pushq %rbx
    pushq %rdi                          # save ctx (caller-saved, clobbered below)
    movq %rsi, %rdi
    call .Ldecode_check_mmio_cap        # RAX = virt base, 0 invalid, -1 not provisioned
    testq %rax, %rax
    jz .Lmmio_cap_fail                  # stack still has [rbx, saved_ctx]
    js .Lmmio_notprov_fail
    movq %rax, %rbx
    popq %rdi                           # restore ctx
    # RDX holds offset fixnum; decode right-shift by 3.
    movq %rdx, %rax
    sarq $3, %rax
    # Bounds check: offset + 4 <= region_len
    movq wsm_mmio_region_len(%rip), %rcx
    movq %rax, %r10
    addq $4, %r10
    jc .Lmmio_overflow_fail
    cmpq %rcx, %r10
    ja .Lmmio_bounds_fail
    # Compute address = base + offset
    addq %rax, %rbx
    movl (%rbx), %eax
    shlq $3, %rax
    orq $WSM_TAG_FIXNUM, %rax
    popq %rbx
    ret

.Lmmio_overflow_fail:                   # read: offset + 4 wrapped
    popq %rbx
    movq $WSM_NIL, %rcx
    movl $ERR_ABI, %esi
    movl $MMIO_ERR_OVERFLOW_READ, %edx
    jmp wsm_fail_src
.Lmmio_bounds_fail:                     # read: offset outside region
    popq %rbx
    movq $WSM_NIL, %rcx
    movl $ERR_ABI, %esi
    movl $MMIO_ERR_CAPABILITY_READ, %edx
    jmp wsm_fail_src
.Lmmio_cap_fail:
    # Invalidate the capability usage: pop saved ctx, then the base save.
    popq %rdi
    popq %rbx
    movq $WSM_NIL, %rcx
    movl $ERR_ABI, %esi
    movl $MMIO_ERR_CAPABILITY_READ, %edx
    jmp wsm_fail_src
.Lmmio_notprov_fail:                    # read: region not provisioned
    popq %rdi
    popq %rbx
    movq $WSM_NIL, %rcx
    movl $ERR_ABI, %esi
    movl $MMIO_ERR_NOT_PROVISIONED_READ, %edx
    jmp wsm_fail_src

# ---------------------------------------------------------------------------
# Word wsm_mmio_write32(RuntimeContext* ctx, Word cap, Word offset, Word value)
# Writes 32-bit MMIO value into the provisioned region.
# Args: RDI = ctx, RSI = cap, RDX = offset (fixnum), RCX = value (fixnum)
# ---------------------------------------------------------------------------
.globl wsm_mmio_write32
.type wsm_mmio_write32, @function
wsm_mmio_write32:
    pushq %rbx
    pushq %r12
    pushq %rdi                          # save ctx (clobbered by the decode call)
    movq %rcx, %r12                     # save value: decode clobbers %rcx
    movq %rsi, %rdi
    call .Ldecode_check_mmio_cap
    testq %rax, %rax
    jz .Lmmio_cap_fail2                 # stack still has [r12, rbx, saved_ctx]
    js .Lmmio_notprov_fail2
    movq %rax, %rbx
    popq %rdi                           # restore ctx
    # RDX = offset (fixnum), decode
    movq %rdx, %rax
    sarq $3, %rax
    # Bounds: offset + 4 <= len  (addq sets CF on overflow)
    movq wsm_mmio_region_len(%rip), %r10
    movq %rax, %r11
    addq $4, %r11
    jc .Lmmio_overflow_fail2
    cmpq %r10, %r11
    ja .Lmmio_bounds_fail2
    # R12 = value (fixnum, saved before decode), decode
    sarq $3, %r12
    movl %r12d, (%rbx,%rax)           # volatile store
    popq %r12
    popq %rbx
    movq $WSM_CANONICAL_T, %rax
    ret

.Lmmio_overflow_fail2:                  # write: offset + 4 wrapped
    popq %r12
    popq %rbx
    movq $WSM_NIL, %rcx
    movl $ERR_ABI, %esi
    movl $MMIO_ERR_OVERFLOW_WRITE, %edx
    jmp wsm_fail_src
.Lmmio_bounds_fail2:                    # write: offset outside region
    popq %r12
    popq %rbx
    movq $WSM_NIL, %rcx
    movl $ERR_ABI, %esi
    movl $MMIO_ERR_CAPABILITY_WRITE, %edx
    jmp wsm_fail_src
.Lmmio_cap_fail2:
    # Invalidate the capability usage: pop saved ctx, then base+value saves.
    popq %rdi
    popq %r12
    popq %rbx
    movq $WSM_NIL, %rcx
    movl $ERR_ABI, %esi
    movl $MMIO_ERR_CAPABILITY_WRITE, %edx
    jmp wsm_fail_src
.Lmmio_notprov_fail2:                   # write: region not provisioned
    popq %rdi
    popq %r12
    popq %rbx
    movq $WSM_NIL, %rcx
    movl $ERR_ABI, %esi
    movl $MMIO_ERR_NOT_PROVISIONED_WRITE, %edx
    jmp wsm_fail_src

# ---------------------------------------------------------------------------
# Internal: validate a provisioned MMIO capability.
# In:  RDI = capability word
# Out: RAX = provisioned virtual base (≥1) when valid;
#      RAX = 0 when the capability is well-defined-looking but its identity is
#            wrong (tag mismatch / nonce mismatch);
#      RAX = -1 when the region was never provisioned.
#      The caller decides how to fail; no redirections to wsm_fail happen here
#      so stack unwinding stays in the caller.
# ---------------------------------------------------------------------------
.Ldecode_check_mmio_cap:
    movq wsm_mmio_region_valid(%rip), %rax
    cmpq $1, %rax
    jne .Lcap_decode_notprov
    # tag must be CAPABILITY
    movq %rdi, %rax
    andq $WSM_TAG_MASK, %rax
    cmpq $WSM_TAG_CAPABILITY, %rax
    jne .Lcap_decode_invalid
    # payload = cap >> 3 must equal (nonce << 16) ; kind==1 implied.
    movq %rdi, %rax
    shrq $3, %rax
    movabsq $0x1A0495124347, %rcx
    shlq $16, %rcx
    cmpq %rcx, %rax
    jne .Lcap_decode_invalid
    movq wsm_mmio_region_base(%rip), %rax
    ret

.Lcap_decode_notprov:
    movq $-1, %rax
    ret

.Lcap_decode_invalid:
    xorl %eax, %eax
    ret

# ---------------------------------------------------------------------------
# Internal: raw PCI config read32.
# In:  EDI = BDF encoded as (bus<<16) | (dev<<8) | func
#      ESI = config offset
# Out: EAX = 32-bit value at 0xCFC
# ---------------------------------------------------------------------------
.Lraw_pci_read32:
    # address = 0x80000000 | (bus<<16) | (dev<<11) | (func<<8) | (offset & 0xFC)
    movl %edi, %eax
    andl $0xFF0000, %eax          # bus<<16
    orl $0x80000000, %eax         # enable bit
    movl %edi, %edx
    andl $0xFF00, %edx            # dev<<8
    shll $3, %edx                 # dev<<11
    orl %edx, %eax
    movl %edi, %edx
    andl $0xFF, %edx              # func
    shll $8, %edx                 # func<<8
    orl %edx, %eax
    andl $0xFC, %esi
    orl %esi, %eax                # offset
    movw $0xCF8, %dx
    outl %eax, %dx
    movw $0xCFC, %dx
    inl %dx, %eax
    ret

# Enable PCI memory-space + bus-master for the discovered virtio-blk function.
# In: EDI = BDF encoded as (bus<<16)|(dev<<8)|func
# Out: EAX = 1 when command bits 1/2 read back set, otherwise 0.
.Lraw_pci_enable_mem_busmaster:
    pushq %rbx
    movl %edi, %ebx

    movl %ebx, %eax
    andl $0xFF0000, %eax
    orl $0x80000000, %eax
    movl %ebx, %edx
    andl $0xFF00, %edx
    shll $3, %edx
    orl %edx, %eax
    movl %ebx, %edx
    andl $0xFF, %edx
    shll $8, %edx
    orl %edx, %eax
    orl $0x04, %eax                # PCI Command/Status dword
    movw $0xCF8, %dx
    outl %eax, %dx

    movw $0xCFC, %dx
    inw %dx, %ax                   # Command register low 16 bits
    orw $0x0006, %ax               # MEMORY + BUS MASTER
    outw %ax, %dx

    # Read back command bits.
    movl %ebx, %eax
    andl $0xFF0000, %eax
    orl $0x80000000, %eax
    movl %ebx, %edx
    andl $0xFF00, %edx
    shll $3, %edx
    orl %edx, %eax
    movl %ebx, %edx
    andl $0xFF, %edx
    shll $8, %edx
    orl %edx, %eax
    orl $0x04, %eax
    movw $0xCF8, %dx
    outl %eax, %dx
    movw $0xCFC, %dx
    inw %dx, %ax
    andl $0x0006, %eax
    cmpl $0x0006, %eax
    sete %al
    movzbl %al, %eax
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# Internal: scan bus 0 and 1 for virtio-blk device.
# Out: EAX = dev (device<<3 | function) of virtio-blk, or 0 if not found.
# Scans bus 0 and 1 (q35 puts PCI devices on bus 1), all 32 devices,
# 8 functions each. Matches vendor=0x1AF4 (virtio) and device=0x1042
# (virtio-block).
# ---------------------------------------------------------------------------
.Lpci_scan_virtio_blk:
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    # r12 = bus (0-1), r13 = device (0-31), r14 = function (0-7)
    xorl %r12d, %r12d
.Lscan_bus_loop:
    cmpl $2, %r12d
    jge .Lscan_not_found
    xorl %r13d, %r13d
.Lscan_dev_loop:
    cmpl $32, %r13d
    jge .Lscan_next_bus
    xorl %r14d, %r14d
.Lscan_func_loop:
    cmpl $8, %r14d
    jge .Lscan_next_dev

    # Compose dev = (bus<<20) | (device<<15) | (function<<12) for .Lraw_pci_read32
    # But .Lraw_pci_read32 expects dev in EDI as (device<<3 | function) for bus 0.
    # For multi-bus, we need to construct the full config address.
    # Instead, we'll call a modified read that takes bus/dev/func separately.
    # Simpler: construct the full config address in EAX and use outl/inl directly.
    movl $0x80000000, %eax        # enable bit
    movl %r12d, %edx
    shll $16, %edx
    orl %edx, %eax                # bus in bits 23:16
    movl %r13d, %edx
    andl $0x1F, %edx
    shll $11, %edx
    orl %edx, %eax                # device in bits 15:11
    movl %r14d, %edx
    andl $0x07, %edx
    shll $8, %edx
    orl %edx, %eax                # function in bits 10:8
    # offset will be added per read

    # Read vendor/device at offset 0x00
    movl %eax, %ebx
    orl $0x00, %ebx
    movw $0xCF8, %dx
    xchgl %eax, %ebx
    outl %eax, %dx
    movw $0xCFC, %dx
    inl %dx, %eax
    xchgl %eax, %ebx
    # EBX: raw read value (low 16 = vendor, high 16 = device)
    movl %ebx, %edx               # save raw value
    andl $0xFFFF, %ebx            # vendor
    cmpl $0x1AF4, %ebx
    jne .Lscan_next_func
    shrl $16, %edx                # device from raw (not from masked vendor)
    andl $0xFFFF, %edx
    cmpl $0x1042, %edx
    je .Lscan_found

.Lscan_next_func:
    incl %r14d
    jmp .Lscan_func_loop

.Lscan_next_dev:
    incl %r13d
    jmp .Lscan_dev_loop

.Lscan_next_bus:
    incl %r12d
    jmp .Lscan_bus_loop

.Lscan_found:
    # Return dev encoding compatible with .Lraw_pci_read32: (bus<<20)|(dev<<15)|(func<<12)
    # But .Lraw_pci_read32 only uses dev<<11|func. We need a different approach.
    # Instead, return the full BDF encoded as bus<<16 | dev<<8 | func in EAX.
    # Caller will need to handle this.
    movl %r12d, %eax
    shll $16, %eax
    movl %r13d, %edx
    shll $8, %edx
    orl %edx, %eax
    movl %r14d, %edx
    orl %edx, %eax
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    ret

.Lscan_not_found:
    xorl %eax, %eax
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# Internal: decode PCI BAR physical address.
# In:  EDI = dev, ESI = bar_num
# Out: RAX = physical address (0 if I/O BAR)
# Clobbers volatile registers and preserves RBX/RBP.
# ---------------------------------------------------------------------------
.Lraw_bar_phys:
    pushq %rbx
    pushq %rbp
    # bar_offset = 0x10 + bar_num*4
    movl %edi, %ebp                 # save dev across the helper call
    movl %esi, %ecx
    shll $2, %ecx
    addl $0x10, %ecx                # ecx = bar_offset (survives read32: it only
                                    # clobbers EAX/EDI/ESI/EDX)

    # Read low dword of the BAR
    movl %ebp, %edi
    movl %ecx, %esi
    call .Lraw_pci_read32           # EAX = bar_low
    # I/O BAR detection: bit0 set -> skip entirely
    testl $1, %eax
    jz .Lbar_ok_not_io
    xorl %eax, %eax
    popq %rbp
    popq %rbx
    ret

.Lbar_ok_not_io:
    movl %eax, %ebx                 # bar_low (across the second read)
    # 64-bit BAR test: bits[2:1] of the ORIGINAL bar_low == 2
    movl %eax, %edx
    shrl $1, %edx
    andl $3, %edx
    cmpl $2, %edx
    jne .Lbar_32

    # 64-bit BAR: read high dword at bar_offset + 4
    movl %ebp, %edi
    leal 4(%rcx), %esi
    call .Lraw_pci_read32
    shlq $32, %rax
    movl %ebx, %ecx
    andl $0xFFFFFFF0, %ecx
    orq %rcx, %rax
    popq %rbp
    popq %rbx
    ret

.Lbar_32:
    # 32-bit BAR: base = bar_low & 0xFFFFFFF0
    movl %ebx, %eax
    andl $0xFFFFFFF0, %eax
    popq %rbp
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# Internal: verify a physical address is present in the active page tables.
# In:  RDI = physical address, RSI = physical-memory offset
# Out: RAX = 1 if a mapping exists (the translated virtual address resolves),
#       RAX = 0 otherwise.
# The bootloader maps physical memory at (phys + offset). We translate the
# given phys to a candidate virt and walk CR3.
# ---------------------------------------------------------------------------
.Lpage_walk_present:
    pushq %rbx
    pushq %r13
    pushq %r14
    # 64-bit immediate page-frame mask; andq needs the mask in a register.
    movabsq $0x000FFFFFFFFFF000, %rcx
    addq %rsi, %rdi                   # candidate virtual address

    movq %cr3, %r13                   # PML4 phys addr
    movq %rdi, %r14                   # vaddr

    # PML4 index = (vaddr >> 39) & 0x1FF
    movq %r14, %rax
    shrq $39, %rax
    andq $0x1FF, %rax
    leaq (%r13,%rax,8), %rbx          # entry phys address
    addq %rsi, %rbx                   # translate to virtual
    movq (%rbx), %rax
    testq $1, %rax                    # present bit
    jz .Lpw_fail
    # entry phys = page-frame bits
    movq %rax, %r13
    andq %rcx, %r13

    # PDPT index = (vaddr >> 30) & 0x1FF
    movq %r14, %rax
    shrq $30, %rax
    andq $0x1FF, %rax
    leaq (%r13,%rax,8), %rbx
    addq %rsi, %rbx
    movq (%rbx), %rax
    testq $1, %rax
    jz .Lpw_fail
    # Large page at PDPT (1 GiB)? bit7 == PS
    movq %rax, %r13
    testq $0x80, %r13
    jnz .Lpw_present
    andq %rcx, %r13

    # PD index = (vaddr >> 21) & 0x1FF
    movq %r14, %rax
    shrq $21, %rax
    andq $0x1FF, %rax
    leaq (%r13,%rax,8), %rbx
    addq %rsi, %rbx
    movq (%rbx), %rax
    testq $1, %rax
    jz .Lpw_fail
    movq %rax, %r13
    # Large page at PD (2 MiB)? bit7 == PS
    testq $0x80, %r13
    jnz .Lpw_present
    andq %rcx, %r13

    # PT index = (vaddr >> 12) & 0x1FF
    movq %r14, %rax
    shrq $12, %rax
    andq $0x1FF, %rax
    leaq (%r13,%rax,8), %rbx
    addq %rsi, %rbx
    movq (%rbx), %rax
    testq $1, %rax
    jz .Lpw_fail

.Lpw_present:
    movl $1, %eax
    popq %r14
    popq %r13
    popq %rbx
    ret

.Lpw_fail:
    xorl %eax, %eax
    popq %r14
    popq %r13
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# M2 / #82: provision VIRTIO_PCI_CAP_NOTIFY_CFG (cfg_type=2).
# ---------------------------------------------------------------------------
.Lprovision_virtio_notify:
    pushq %rbp
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    movq $0, wsm_virtio_notify_base(%rip)
    movq $0, wsm_virtio_notify_len(%rip)
    movq $0, wsm_virtio_notify_multiplier(%rip)
    movq $0, wsm_virtio_notify_valid(%rip)

    movl wsm_virtio_blk_bdf(%rip), %r12d
    testl %r12d, %r12d
    jz .Lnotify_fail_nocap

    movq wsm_target_phys_mem_offset(%rip), %r15
    testq %r15, %r15
    jz .Lnotify_fail_mapping

    movl %r12d, %edi
    movl $0x04, %esi
    call .Lraw_pci_read32
    testl $0x00100000, %eax
    jz .Lnotify_fail_nocap

    movl %r12d, %edi
    movl $0x34, %esi
    call .Lraw_pci_read32
    movl %eax, %r13d
    andl $0xFC, %r13d

.Lnotify_cap_loop:
    cmpl $0x40, %r13d
    jl .Lnotify_fail_nocap
    cmpl $0x100, %r13d
    jge .Lnotify_fail_nocap

    movl %r12d, %edi
    movl %r13d, %esi
    call .Lraw_pci_read32
    movl %eax, %r14d

    movl %r14d, %eax
    andl $0xFF, %eax
    cmpl $0x09, %eax
    jne .Lnotify_next_cap
    movl %r14d, %eax
    shrl $24, %eax
    cmpl $2, %eax
    jne .Lnotify_next_cap

    # Notify capability includes the 16-byte generic cap plus multiplier.
    movl %r14d, %eax
    shrl $16, %eax
    andl $0xFF, %eax
    cmpl $20, %eax
    jb .Lnotify_fail_geometry

    movl %r13d, %ebp                 # preserve matching cap offset

    movl %r12d, %edi
    leal 4(%rbp), %esi
    call .Lraw_pci_read32
    movzbl %al, %r14d                # BAR number

    movl %r12d, %edi
    leal 8(%rbp), %esi
    call .Lraw_pci_read32
    movl %eax, %r13d                 # offset within BAR

    movl %r12d, %edi
    leal 12(%rbp), %esi
    call .Lraw_pci_read32
    movl %eax, %eax
    cmpq $2, %rax
    jb .Lnotify_fail_geometry
    movq %rax, wsm_virtio_notify_len(%rip)

    movl %r12d, %edi
    leal 16(%rbp), %esi
    call .Lraw_pci_read32
    movl %eax, %eax
    movq %rax, wsm_virtio_notify_multiplier(%rip)

    # Without VIRTIO_F_NOTIFICATION_DATA the multiplier must be 0 or an even
    # power of two. The first #82 slice never negotiates notification-data.
    testq %rax, %rax
    jz .Lnotify_multiplier_ok
    testq $1, %rax
    jnz .Lnotify_fail_geometry
    movq %rax, %rcx
    decq %rcx
    testq %rcx, %rax
    jnz .Lnotify_fail_geometry
.Lnotify_multiplier_ok:

    movl %r12d, %edi
    movl %r14d, %esi
    call .Lraw_bar_phys
    testq %rax, %rax
    jz .Lnotify_fail_bar
    addq %r13, %rax
    jc .Lnotify_fail_bar
    movq %rax, %rbx                  # notify physical start

    # Prove both ends of the bounded notify capability are mapped.
    movq %rbx, %rdi
    movq %r15, %rsi
    call .Lpage_walk_present
    testq %rax, %rax
    jz .Lnotify_fail_mapping

    movq wsm_virtio_notify_len(%rip), %rcx
    decq %rcx
    addq %rbx, %rcx
    jc .Lnotify_fail_bar
    movq %rcx, %rdi
    movq %r15, %rsi
    call .Lpage_walk_present
    testq %rax, %rax
    jz .Lnotify_fail_mapping

    movq %rbx, %rax
    addq %r15, %rax
    jc .Lnotify_fail_bar
    movq %rax, wsm_virtio_notify_base(%rip)
    movq $1, wsm_virtio_notify_valid(%rip)
    jmp .Lnotify_done

.Lnotify_next_cap:
    movl %r14d, %eax
    shrl $8, %eax
    andl $0xFC, %eax
    testl %eax, %eax
    jz .Lnotify_fail_nocap
    movl %eax, %r13d
    jmp .Lnotify_cap_loop

.Lnotify_fail_nocap:
    movq $2, wsm_virtio_notify_valid(%rip)
    jmp .Lnotify_done
.Lnotify_fail_geometry:
    movq $3, wsm_virtio_notify_valid(%rip)
    jmp .Lnotify_done
.Lnotify_fail_bar:
    movq $4, wsm_virtio_notify_valid(%rip)
    jmp .Lnotify_done
.Lnotify_fail_mapping:
    movq $5, wsm_virtio_notify_valid(%rip)

.Lnotify_done:
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    popq %rbp
    ret

# ---------------------------------------------------------------------------
# M2 / #82: configure modern VirtIO block request queue 0 as a split ring.
#
# This owns transport mechanism only. It does not submit block requests yet.
# Returns raw RAX=1 on success, RAX=0 on fail-closed.
#
# COMMON_CFG offsets follow VirtIO 1.3:
#   status +20 u8, queue_select +22 u16, queue_size +24 u16,
#   queue_enable +28 u16, queue_notify_off +30 u16,
#   queue_desc +32 u64, queue_driver +40 u64, queue_device +48 u64.
# ---------------------------------------------------------------------------
.globl wsm_virtio_blk_prepare_queue0
.type wsm_virtio_blk_prepare_queue0, @function
wsm_virtio_blk_prepare_queue0:
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    movq $0, wsm_virtio_queue0_valid(%rip)
    movq $0, wsm_virtio_queue0_notify_addr(%rip)
    movq $0, wsm_virtio_queue0_size(%rip)
    movq $0, wsm_virtio_flush_supported(%rip)
    movq $0, wsm_virtio_block_completed_requests(%rip)

    call wsm_target_provision_mmio
    cmpq $1, wsm_mmio_region_valid(%rip)
    jne .Lqueue0_fail
    cmpq $1, wsm_virtio_notify_valid(%rip)
    jne .Lqueue0_fail
    cmpq $1, wsm_dma_arena_valid(%rip)
    jne .Lqueue0_fail

    movq wsm_mmio_region_len(%rip), %rax
    cmpq $56, %rax
    jb .Lqueue0_fail
    movq wsm_mmio_region_base(%rip), %rbx

    # Reset and bound the mandatory status readback.
    movb $0, 20(%rbx)
    movl $100000, %ecx
.Lqueue0_reset_wait:
    movzbl 20(%rbx), %eax
    testb %al, %al
    jz .Lqueue0_reset_ok
    pause
    loop .Lqueue0_reset_wait
    jmp .Lqueue0_fail_mark
.Lqueue0_reset_ok:
    movb $1, 20(%rbx)                # ACKNOWLEDGE
    movb $3, 20(%rbx)                # + DRIVER

    # Device feature bank 1: VIRTIO_F_VERSION_1 is bit 32 => bank1 bit0.
    movl $1, 0(%rbx)
    movl 4(%rbx), %eax
    testl $1, %eax
    jz .Lqueue0_fail_mark

    # Device feature bank 0: reject read-only; remember FLUSH support.
    movl $0, 0(%rbx)
    movl 4(%rbx), %r12d
    testl $0x20, %r12d               # VIRTIO_BLK_F_RO
    jnz .Lqueue0_fail_mark
    testl $0x200, %r12d              # VIRTIO_BLK_F_FLUSH
    jz .Lqueue0_no_flush
    movq $1, wsm_virtio_flush_supported(%rip)
.Lqueue0_no_flush:
.ifdef WSM_FORCE_VIRTIO_NO_FLUSH
    movq $0, wsm_virtio_flush_supported(%rip)
.endif

    # Driver accepts only VERSION_1 and, when offered, FLUSH.
    movl $1, 8(%rbx)
    movl $1, 12(%rbx)
    movl $0, 8(%rbx)
    xorl %eax, %eax
    testl $0x200, %r12d
    jz .Lqueue0_write_low_features
    movl $0x200, %eax
.Lqueue0_write_low_features:
    movl %eax, 12(%rbx)

    movb $11, 20(%rbx)               # ACK|DRIVER|FEATURES_OK
    movzbl 20(%rbx), %eax
    testb $8, %al
    jz .Lqueue0_fail_mark

    # Queue 0, split ring size 8.
    movw $0, 22(%rbx)
    movzwl 24(%rbx), %eax
.ifdef WSM_FORCE_VIRTIO_QUEUE_UNSUPPORTED
    xorl %eax, %eax
.endif
    cmpl $8, %eax
    jb .Lqueue0_fail_mark
    movw $8, 24(%rbx)
    movzwl 24(%rbx), %eax
    cmpl $8, %eax
    jne .Lqueue0_fail_mark
    movzwl 28(%rbx), %eax
    testl %eax, %eax
    jnz .Lqueue0_fail_mark
    movzwl 30(%rbx), %r13d           # queue_notify_off

    # Clear exactly one #84 page before publishing any queue addresses.
    leaq wsm_dma_arena(%rip), %rdi
    xorl %eax, %eax
    movl $512, %ecx
    cld
    rep stosq

    # Split ring geometry inside the proved contiguous page:
    # desc=+0 (128 B), avail=+128 (20 B), used=+148 (68 B).
    movq wsm_dma_arena_phys(%rip), %r12
    testq %r12, %r12
    jz .Lqueue0_fail_mark
    movq %r12, 32(%rbx)
    leaq 128(%r12), %r14
    movq %r14, 40(%rbx)
    leaq 148(%r12), %r15
    movq %r15, 48(%rbx)

    # Derive and bound the per-queue notify address.
    movq wsm_virtio_notify_multiplier(%rip), %r14
    movq %r13, %rax
    mulq %r14                         # RDX:RAX = notify_off * multiplier
    testq %rdx, %rdx
    jnz .Lqueue0_fail_mark
    movq %rax, %r13
    movq %r13, %rcx
    addq $2, %rcx
    jc .Lqueue0_fail_mark
    cmpq wsm_virtio_notify_len(%rip), %rcx
    ja .Lqueue0_fail_mark
    movq wsm_virtio_notify_base(%rip), %rax
    addq %r13, %rax
    jc .Lqueue0_fail_mark
    testq $1, %rax                    # 16-bit notify write requires alignment
    jnz .Lqueue0_fail_mark
    movq %rax, wsm_virtio_queue0_notify_addr(%rip)
.ifdef WSM_FORCE_VIRTIO_BAD_GEOMETRY
    orq $1, wsm_virtio_queue0_notify_addr(%rip)
    jmp .Lqueue0_fail_mark
.endif

    mfence
    movw $1, 28(%rbx)                 # queue_enable
    movzwl 28(%rbx), %eax
    cmpl $1, %eax
    jne .Lqueue0_fail_mark

    movb $15, 20(%rbx)                # + DRIVER_OK
    movzbl 20(%rbx), %eax
    andl $15, %eax
    cmpl $15, %eax
    jne .Lqueue0_fail_mark

    movq $8, wsm_virtio_queue0_size(%rip)
    movq $1, wsm_virtio_queue0_valid(%rip)
    movl $1, %eax
    jmp .Lqueue0_done

.Lqueue0_fail_mark:
    # Once COMMON_CFG is live, advertise driver failure explicitly.
    orb $0x80, 20(%rbx)
.Lqueue0_fail:
    xorl %eax, %eax

.Lqueue0_done:
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# M2 / #82: submit one sector-0 virtio-blk request through queue0.
#
# In: EDI = request type (0 IN, 1 OUT, 4 FLUSH)
# Out: EAX = 1 only after bounded used-ring completion + status byte == OK.
#
# Descriptor layout in the single #84 DMA page:
#   desc[0] @ +0   -> request header @ +256
#   desc[1] @ +16  -> data buffer    @ +512 (IN/OUT only)
#   desc[2] @ +32  -> status byte    @ +1024
# avail ring @ +128, used ring @ +148.
# ---------------------------------------------------------------------------
.Lvirtio_blk_submit_sector0:
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    movl %edi, %r12d
    cmpl $0, %r12d
    je .Lblk_type_ok
    cmpl $1, %r12d
    je .Lblk_type_ok
    cmpl $4, %r12d
    jne .Lblk_submit_fail
.Lblk_type_ok:
    cmpq $1, wsm_virtio_queue0_valid(%rip)
    jne .Lblk_submit_fail

    leaq wsm_dma_arena(%rip), %rbx
    movq wsm_dma_arena_phys(%rip), %r13
    testq %r13, %r13
    jz .Lblk_submit_fail

    # Header: type, reserved=0, sector=0.
    movl %r12d, 256(%rbx)
    movl $0, 260(%rbx)
    movq $0, 264(%rbx)
    movb $0xFF, 1024(%rbx)           # device must overwrite status

    # desc0 -> header, always NEXT.
    leaq 256(%r13), %rax
    movq %rax, 0(%rbx)
    movl $16, 8(%rbx)
    movw $1, 12(%rbx)                # VIRTQ_DESC_F_NEXT
    cmpl $4, %r12d
    je .Lblk_desc_flush
    movw $1, 14(%rbx)                # next = data desc1

    # desc1 -> 512-byte data. IN lets device write; OUT lets device read.
    leaq 512(%r13), %rax
    movq %rax, 16(%rbx)
    movl $512, 24(%rbx)
    movw $1, 28(%rbx)                # NEXT
    cmpl $0, %r12d
    jne .Lblk_desc_data_flags_done
    orw $2, 28(%rbx)                 # + VIRTQ_DESC_F_WRITE for IN
.Lblk_desc_data_flags_done:
    movw $2, 30(%rbx)                # next = status desc2
    jmp .Lblk_desc_status

.Lblk_desc_flush:
    # FLUSH has no data buffer: header jumps directly to status.
    movw $2, 14(%rbx)

.Lblk_desc_status:
    leaq 1024(%r13), %rax
    movq %rax, 32(%rbx)
    movl $1, 40(%rbx)
    movw $2, 44(%rbx)                # VIRTQ_DESC_F_WRITE
    movw $0, 46(%rbx)

    # Capture old used index and publish head descriptor 0 into the next
    # available slot. Requests are strictly sequential in this bounded witness.
    movzwl 150(%rbx), %r15d          # used.idx before request
    movzwl 130(%rbx), %r14d          # avail.idx before request
    movl %r14d, %eax
    andl $7, %eax
    movw $0, 132(%rbx,%rax,2)        # avail.ring[avail_idx % 8] = head 0
    mfence
    incl %r14d
    andl $0xFFFF, %r14d
    movw %r14w, 130(%rbx)
    mfence

    # Notification data was not negotiated: notify payload is queue index 0.
    movq wsm_virtio_queue0_notify_addr(%rip), %rax
    testq %rax, %rax
    jz .Lblk_submit_fail
    movw $0, (%rax)

.ifdef WSM_FORCE_VIRTIO_TIMEOUT
    # Test-only falsifier: exercise the same finite timeout outcome without
    # permitting a fast QEMU completion to race the mutation.
    movl $4096, %ecx
.Lblk_forced_timeout:
    pause
    loop .Lblk_forced_timeout
    jmp .Lblk_submit_fail
.endif

    # Bounded completion wait. Expected used.idx = previous + 1 modulo u16.
    movl %r15d, %r14d
    incl %r14d
    andl $0xFFFF, %r14d
    movl $1000000, %ecx
.Lblk_wait_used:
    movzwl 150(%rbx), %eax
    cmpl %r14d, %eax
    je .Lblk_used_ready
    pause
    loop .Lblk_wait_used
    jmp .Lblk_submit_fail

.Lblk_used_ready:
    lfence
    # Device must report the head descriptor id in the used-ring slot that was
    # current before this request.
    movl %r15d, %eax
    andl $7, %eax
    leaq 152(%rbx,%rax,8), %rdx
    cmpl $0, 0(%rdx)
    jne .Lblk_submit_fail

    # Virtio block status byte: 0 == VIRTIO_BLK_S_OK.
.ifdef WSM_FORCE_VIRTIO_BAD_STATUS
    movb $1, 1024(%rbx)
.endif
    cmpb $0, 1024(%rbx)
    jne .Lblk_submit_fail

    incq wsm_virtio_block_completed_requests(%rip)
    movl $1, %eax
    jmp .Lblk_submit_done

.Lblk_submit_fail:
    xorl %eax, %eax
.Lblk_submit_done:
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# M2 / #82: real sector-0 read -> write -> flush -> read round trip.
#
# Fresh raw disk must read as zero. The write payload is exactly
# b"SENSM2V1" repeated 64 times (512 bytes). The second read must return the
# same bytes. Host-side CI also hashes sector 0 after QEMU exits.
# ---------------------------------------------------------------------------
.globl wsm_virtio_blk_sector0_roundtrip
.type wsm_virtio_blk_sector0_roundtrip, @function
wsm_virtio_blk_sector0_roundtrip:
    pushq %rbx
    pushq %r12
    pushq %r13

    movq $0, wsm_virtio_block_roundtrip_stage(%rip)
    movq $0, wsm_virtio_block_completed_requests(%rip)

    # DMA requires PCI bus-master + memory-space command bits.
    movl wsm_virtio_blk_bdf(%rip), %edi
    testl %edi, %edi
    jnz .Lblk_have_bdf
    # Provision once to discover the BDF before enabling bus mastering.
    call wsm_target_provision_mmio
    movl wsm_virtio_blk_bdf(%rip), %edi
.Lblk_have_bdf:
    testl %edi, %edi
    jz .Lblk_roundtrip_fail
    call .Lraw_pci_enable_mem_busmaster
    cmpl $1, %eax
    jne .Lblk_roundtrip_fail

    call wsm_virtio_blk_prepare_queue0
    cmpl $1, %eax
    jne .Lblk_roundtrip_fail
    movq $1, wsm_virtio_block_roundtrip_stage(%rip)

    # Persistence witness requires an actual negotiated FLUSH.
    cmpq $1, wsm_virtio_flush_supported(%rip)
    jne .Lblk_roundtrip_fail

    # IN sector 0 on a fresh truncated raw image.
    movl $0, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lblk_roundtrip_fail
    movq $2, wsm_virtio_block_roundtrip_stage(%rip)

    # Classify fresh sector as all-zero.
    leaq wsm_dma_arena+512(%rip), %rbx
    movl $64, %ecx
.Lblk_zero_check:
    cmpq $0, (%rbx)
    jne .Lblk_roundtrip_fail
    addq $8, %rbx
    loop .Lblk_zero_check

    # Fill exact 512-byte deterministic payload: ASCII "SENSM2V1" repeated.
    leaq wsm_dma_arena+512(%rip), %rdi
    movabsq $0x3156324D534E4553, %rax
    movl $64, %ecx
    cld
    rep stosq

    # OUT sector 0.
    movl $1, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lblk_roundtrip_fail
    movq $3, wsm_virtio_block_roundtrip_stage(%rip)

    # FLUSH: sector=0, no data descriptor.
    movl $4, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lblk_roundtrip_fail
    movq $4, wsm_virtio_block_roundtrip_stage(%rip)

    # Clear buffer so the final IN cannot pass from stale guest bytes.
    leaq wsm_dma_arena+512(%rip), %rdi
    xorl %eax, %eax
    movl $64, %ecx
    cld
    rep stosq

    movl $0, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lblk_roundtrip_fail
    movq $5, wsm_virtio_block_roundtrip_stage(%rip)

    # Compare final read against the exact deterministic payload.
    leaq wsm_dma_arena+512(%rip), %rbx
    movabsq $0x3156324D534E4553, %r12
    movl $64, %ecx
.Lblk_pattern_check:
    cmpq %r12, (%rbx)
    jne .Lblk_roundtrip_fail
    addq $8, %rbx
    loop .Lblk_pattern_check

    movq $6, wsm_virtio_block_roundtrip_stage(%rip)
    movl $1, %eax
    jmp .Lblk_roundtrip_done

.Lblk_roundtrip_fail:
    xorl %eax, %eax
.Lblk_roundtrip_done:
    popq %r13
    popq %r12
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# M2 / #77: boot-A persistence writer over the already-proved #82 transport.
#
# Fresh sector0 -> OUT deterministic 512-byte payload -> FLUSH -> success.
# Returns raw EAX=1/0 to a mechanism-only fixture. No filesystem semantics.
# ---------------------------------------------------------------------------
.globl wsm_virtio_blk_persist_sector0_write
.type wsm_virtio_blk_persist_sector0_write, @function
wsm_virtio_blk_persist_sector0_write:
    pushq %rbx
    pushq %r12

    movq $0, wsm_virtio_persistence_stage(%rip)

    # Discover the device before enabling DMA bus mastering.
    movl wsm_virtio_blk_bdf(%rip), %edi
    testl %edi, %edi
    jnz .Lpersist_write_have_bdf
    call wsm_target_provision_mmio
    movl wsm_virtio_blk_bdf(%rip), %edi
.Lpersist_write_have_bdf:
    testl %edi, %edi
    jz .Lpersist_write_fail
    call .Lraw_pci_enable_mem_busmaster
    cmpl $1, %eax
    jne .Lpersist_write_fail

    call wsm_virtio_blk_prepare_queue0
    cmpl $1, %eax
    jne .Lpersist_write_fail
    cmpq $1, wsm_virtio_flush_supported(%rip)
    jne .Lpersist_write_fail
    movq $1, wsm_virtio_persistence_stage(%rip)

    # Fresh persistence image must begin with an all-zero admitted sector.
    movl $0, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lpersist_write_fail
    leaq wsm_dma_arena+512(%rip), %rbx
    movl $64, %ecx
.Lpersist_write_zero_check:
    cmpq $0, (%rbx)
    jne .Lpersist_write_fail
    addq $8, %rbx
    loop .Lpersist_write_zero_check

    # Exact first persisted payload: b"SENSM2V1" * 64.
    leaq wsm_dma_arena+512(%rip), %rdi
    movabsq $0x3156324D534E4553, %rax
    movl $64, %ecx
    cld
    rep stosq

    movl $1, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lpersist_write_fail
    movq $2, wsm_virtio_persistence_stage(%rip)

    movl $4, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lpersist_write_fail
    movq $3, wsm_virtio_persistence_stage(%rip)

    movl $1, %eax
    jmp .Lpersist_write_done

.Lpersist_write_fail:
    xorl %eax, %eax
.Lpersist_write_done:
    popq %r12
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# M2 / #77: boot-B verifier over the same host raw-disk path/image.
#
# A new QEMU boot creates a new runtime/queue, reads sector0 once and succeeds
# only when the exact boot-A payload survived the clean restart.
# ---------------------------------------------------------------------------
.globl wsm_virtio_blk_persist_sector0_verify
.type wsm_virtio_blk_persist_sector0_verify, @function
wsm_virtio_blk_persist_sector0_verify:
    pushq %rbx
    pushq %r12

    movq $0, wsm_virtio_persistence_stage(%rip)

    movl wsm_virtio_blk_bdf(%rip), %edi
    testl %edi, %edi
    jnz .Lpersist_verify_have_bdf
    call wsm_target_provision_mmio
    movl wsm_virtio_blk_bdf(%rip), %edi
.Lpersist_verify_have_bdf:
    testl %edi, %edi
    jz .Lpersist_verify_fail
    call .Lraw_pci_enable_mem_busmaster
    cmpl $1, %eax
    jne .Lpersist_verify_fail

    call wsm_virtio_blk_prepare_queue0
    cmpl $1, %eax
    jne .Lpersist_verify_fail

    # Destroy stale guest bytes before the read witness.
    leaq wsm_dma_arena+512(%rip), %rdi
    xorl %eax, %eax
    movl $64, %ecx
    cld
    rep stosq

    movl $0, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lpersist_verify_fail

    leaq wsm_dma_arena+512(%rip), %rbx
    movabsq $0x3156324D534E4553, %r12
    movl $64, %ecx
.Lpersist_verify_pattern:
    cmpq %r12, (%rbx)
    jne .Lpersist_verify_fail
    addq $8, %rbx
    loop .Lpersist_verify_pattern

    movq $1, wsm_virtio_persistence_stage(%rip)
    movl $1, %eax
    jmp .Lpersist_verify_done

.Lpersist_verify_fail:
    xorl %eax, %eax
.Lpersist_verify_done:
    popq %r12
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# M2 / #95: canonical one-sector persistence envelope.
#
# Layout (all integers little-endian):
#   +0   u8[8] magic = "WSMENV01"
#   +8   u32   version = 1
#   +12  u32   header_len = 32
#   +16  u32   payload_len <= 480
#   +20  u32   FNV-1a32(payload)
#   +24  u64   reserved = 0
#   +32  bytes payload, then zero padding through byte 511
#
# FNV-1a is the in-format corruption checksum only. CI records SHA-256 as
# external artifact identity. These helpers assign no SENS meaning to payload.
# ---------------------------------------------------------------------------

# In: RDI=bytes, ECX=len. Out: EAX=FNV-1a32.
.Lm2_fnv1a32:
    movl $0x811C9DC5, %eax
    testl %ecx, %ecx
    jz .Lm2_fnv_done
.Lm2_fnv_loop:
    movzbl (%rdi), %edx
    xorl %edx, %eax
    imull $0x01000193, %eax, %eax
    incq %rdi
    decl %ecx
    jnz .Lm2_fnv_loop
.Lm2_fnv_done:
    ret

# In: RDI=512-byte buffer. Builds the first canonical #95 frame.
.Lm2_envelope_build:
    pushq %rbx
    movq %rdi, %rbx

    xorl %eax, %eax
    movl $64, %ecx
    cld
    rep stosq

    movabsq $0x3130564E454D5357, %rax  # ASCII "WSMENV01"
    movq %rax, 0(%rbx)
    movl $1, 8(%rbx)
    movl $32, 12(%rbx)
    movl $16, 16(%rbx)
    movq $0, 24(%rbx)

    # Exact first admitted opaque payload: ASCII "SENS-Q6B-PAYLOAD".
    movabsq $0x4236512D534E4553, %rax
    movq %rax, 32(%rbx)
    movabsq $0x44414F4C5941502D, %rax
    movq %rax, 40(%rbx)

    leaq 32(%rbx), %rdi
    movl $16, %ecx
    call .Lm2_fnv1a32
    movl %eax, 20(%rbx)

    popq %rbx
    ret

# In: RDI=512-byte buffer. Out: EAX=1 iff framing/checksum is valid.
.Lm2_envelope_validate:
    pushq %rbx
    pushq %r12
    movq %rdi, %rbx

    movabsq $0x3130564E454D5357, %rax
    cmpq %rax, 0(%rbx)
    jne .Lm2_env_invalid
    cmpl $1, 8(%rbx)
    jne .Lm2_env_invalid
    cmpl $32, 12(%rbx)
    jne .Lm2_env_invalid

    movl 16(%rbx), %ecx
    cmpl $480, %ecx
    ja .Lm2_env_invalid
    cmpq $0, 24(%rbx)
    jne .Lm2_env_invalid

    movl 20(%rbx), %r12d
    leaq 32(%rbx), %rdi
    call .Lm2_fnv1a32
    cmpl %r12d, %eax
    jne .Lm2_env_invalid

    movl $1, %eax
    jmp .Lm2_env_validate_done
.Lm2_env_invalid:
    xorl %eax, %eax
.Lm2_env_validate_done:
    popq %r12
    popq %rbx
    ret

# Boot A: fresh sector -> canonical frame -> OUT -> FLUSH.
.globl wsm_virtio_blk_persist_envelope_write
.type wsm_virtio_blk_persist_envelope_write, @function
wsm_virtio_blk_persist_envelope_write:
    pushq %rbx
    movq $0, wsm_virtio_persistence_stage(%rip)
    movq $0, wsm_virtio_block_completed_requests(%rip)

    movl wsm_virtio_blk_bdf(%rip), %edi
    testl %edi, %edi
    jnz .Lm2_env_write_have_bdf
    call wsm_target_provision_mmio
    movl wsm_virtio_blk_bdf(%rip), %edi
.Lm2_env_write_have_bdf:
    testl %edi, %edi
    jz .Lm2_env_write_fail
    call .Lraw_pci_enable_mem_busmaster
    cmpl $1, %eax
    jne .Lm2_env_write_fail

    call wsm_virtio_blk_prepare_queue0
    cmpl $1, %eax
    jne .Lm2_env_write_fail
    cmpq $1, wsm_virtio_flush_supported(%rip)
    jne .Lm2_env_write_fail
    movq $10, wsm_virtio_persistence_stage(%rip)

    movl $0, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lm2_env_write_fail

    leaq wsm_dma_arena+512(%rip), %rbx
    movl $64, %ecx
.Lm2_env_zero_check:
    cmpq $0, (%rbx)
    jne .Lm2_env_write_fail
    addq $8, %rbx
    loop .Lm2_env_zero_check

    leaq wsm_dma_arena+512(%rip), %rdi
    call .Lm2_envelope_build
    movq $11, wsm_virtio_persistence_stage(%rip)

    movl $1, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lm2_env_write_fail

    movl $4, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lm2_env_write_fail

    movq $12, wsm_virtio_persistence_stage(%rip)
    movl $1, %eax
    jmp .Lm2_env_write_done
.Lm2_env_write_fail:
    xorl %eax, %eax
.Lm2_env_write_done:
    popq %rbx
    ret

# Boot B: fresh runtime/queue -> IN -> frame/checksum -> exact first payload.
.globl wsm_virtio_blk_persist_envelope_verify
.type wsm_virtio_blk_persist_envelope_verify, @function
wsm_virtio_blk_persist_envelope_verify:
    pushq %rbx
    movq $0, wsm_virtio_persistence_stage(%rip)
    movq $0, wsm_virtio_block_completed_requests(%rip)

    movl wsm_virtio_blk_bdf(%rip), %edi
    testl %edi, %edi
    jnz .Lm2_env_verify_have_bdf
    call wsm_target_provision_mmio
    movl wsm_virtio_blk_bdf(%rip), %edi
.Lm2_env_verify_have_bdf:
    testl %edi, %edi
    jz .Lm2_env_verify_fail
    call .Lraw_pci_enable_mem_busmaster
    cmpl $1, %eax
    jne .Lm2_env_verify_fail
    call wsm_virtio_blk_prepare_queue0
    cmpl $1, %eax
    jne .Lm2_env_verify_fail

    leaq wsm_dma_arena+512(%rip), %rdi
    xorl %eax, %eax
    movl $64, %ecx
    cld
    rep stosq

    movl $0, %edi
    call .Lvirtio_blk_submit_sector0
    cmpl $1, %eax
    jne .Lm2_env_verify_fail

    leaq wsm_dma_arena+512(%rip), %rdi
    call .Lm2_envelope_validate
    cmpl $1, %eax
    jne .Lm2_env_verify_fail

    leaq wsm_dma_arena+512(%rip), %rbx
    cmpl $16, 16(%rbx)
    jne .Lm2_env_verify_fail
    movabsq $0x4236512D534E4553, %rax
    cmpq %rax, 32(%rbx)
    jne .Lm2_env_verify_fail
    movabsq $0x44414F4C5941502D, %rax
    cmpq %rax, 40(%rbx)
    jne .Lm2_env_verify_fail

    movq $20, wsm_virtio_persistence_stage(%rip)
    movl $1, %eax
    jmp .Lm2_env_verify_done
.Lm2_env_verify_fail:
    xorl %eax, %eax
.Lm2_env_verify_done:
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# M2 / #84: translate one mapped kernel virtual address to guest physical.
#
# In:  RDI = virtual address
#      RSI = bootloader physical-memory direct-map offset
# Out: RAX = guest physical address, or 0 when the mapping cannot be proved.
#
# Page-table pages themselves are addressed through the already-proved
# physical-memory direct map.  This is the reverse direction of
# .Lpage_walk_present: CPU->device MMIO mapping and device->guest DMA mapping
# remain separate proofs.  1 GiB, 2 MiB and 4 KiB leaves are handled.
# ---------------------------------------------------------------------------
.Lvirtual_to_physical:
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    testq %rsi, %rsi
    jz .Lv2p_fail

    movq %rdi, %r14                   # virtual address
    movq %rsi, %r12                   # direct-map offset
    movabsq $0x000FFFFFFFFFF000, %r15 # ordinary page-frame mask

    movq %cr3, %r13
    andq %r15, %r13                   # PML4 guest-physical base

    # PML4
    movq %r14, %rax
    shrq $39, %rax
    andq $0x1FF, %rax
    leaq (%r13,%rax,8), %rbx
    addq %r12, %rbx
    jc .Lv2p_fail
    movq (%rbx), %rax
    testq $1, %rax
    jz .Lv2p_fail
    movq %rax, %r13
    andq %r15, %r13

    # PDPT
    movq %r14, %rax
    shrq $30, %rax
    andq $0x1FF, %rax
    leaq (%r13,%rax,8), %rbx
    addq %r12, %rbx
    jc .Lv2p_fail
    movq (%rbx), %rax
    testq $1, %rax
    jz .Lv2p_fail
    testq $0x80, %rax
    jnz .Lv2p_1g
    movq %rax, %r13
    andq %r15, %r13

    # PD
    movq %r14, %rax
    shrq $21, %rax
    andq $0x1FF, %rax
    leaq (%r13,%rax,8), %rbx
    addq %r12, %rbx
    jc .Lv2p_fail
    movq (%rbx), %rax
    testq $1, %rax
    jz .Lv2p_fail
    testq $0x80, %rax
    jnz .Lv2p_2m
    movq %rax, %r13
    andq %r15, %r13

    # PT / 4 KiB leaf
    movq %r14, %rax
    shrq $12, %rax
    andq $0x1FF, %rax
    leaq (%r13,%rax,8), %rbx
    addq %r12, %rbx
    jc .Lv2p_fail
    movq (%rbx), %rax
    testq $1, %rax
    jz .Lv2p_fail
    andq %r15, %rax
    movq %r14, %rdx
    andq $0xFFF, %rdx
    addq %rdx, %rax
    jc .Lv2p_fail
    jmp .Lv2p_done

.Lv2p_2m:
    movabsq $0x000FFFFFFFE00000, %rbx
    andq %rbx, %rax
    movq %r14, %rdx
    andq $0x1FFFFF, %rdx
    addq %rdx, %rax
    jc .Lv2p_fail
    jmp .Lv2p_done

.Lv2p_1g:
    movabsq $0x000FFFFFC0000000, %rbx
    andq %rbx, %rax
    movq %r14, %rdx
    andq $0x3FFFFFFF, %rdx
    addq %rdx, %rax
    jc .Lv2p_fail
    jmp .Lv2p_done

.Lv2p_fail:
    xorq %rax, %rax

.Lv2p_done:
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    ret

# ---------------------------------------------------------------------------
# M2 / #84: prove exactly one page-aligned, physically contiguous DMA arena.
#
# State:
#   valid=0 not attempted
#   valid=1 proved
#   valid=2 physical-memory map unavailable
#   valid=3 virtual->physical translation failed
#   valid=4 physical alignment invalid
#   valid=5 page not physically contiguous
#   valid=6 address arithmetic overflow
#
# The physical address is target-only evidence.  It is not a language value.
# ---------------------------------------------------------------------------
.Lprepare_dma_arena:
    pushq %rbx
    pushq %r12
    pushq %r13

    movq $0, wsm_dma_arena_phys(%rip)
    movq $0, wsm_dma_arena_valid(%rip)

    movq wsm_target_phys_mem_offset(%rip), %r13
    testq %r13, %r13
    jz .Ldma_no_map

.ifdef WSM_FORCE_DMA_TRANSLATION_FAIL
    jmp .Ldma_translate_fail
.endif

.ifdef WSM_FORCE_DMA_MISALIGN
    leaq wsm_dma_arena+1(%rip), %rdi
.else
    leaq wsm_dma_arena(%rip), %rdi
.endif
    testq $0xFFF, %rdi
    jnz .Ldma_bad_alignment
    movq %r13, %rsi
    call .Lvirtual_to_physical
.ifdef WSM_FORCE_DMA_ZERO_PHYS
    xorq %rax, %rax
.endif
    testq %rax, %rax
    jz .Ldma_translate_fail
    movq %rax, %r12
    testq $0xFFF, %r12
    jnz .Ldma_bad_alignment

    leaq wsm_dma_arena+4095(%rip), %rdi
    movq %r13, %rsi
    call .Lvirtual_to_physical
    testq %rax, %rax
    jz .Ldma_translate_fail
.ifdef WSM_FORCE_DMA_NONCONTIGUOUS
    addq $4096, %rax
.endif

    movq %r12, %rbx
    addq $4095, %rbx
    jc .Ldma_overflow
    cmpq %rbx, %rax
    jne .Ldma_noncontiguous

    movq %r12, wsm_dma_arena_phys(%rip)
    movq $1, wsm_dma_arena_valid(%rip)
    jmp .Ldma_done

.Ldma_no_map:
    movq $2, wsm_dma_arena_valid(%rip)
    jmp .Ldma_done
.Ldma_translate_fail:
    movq $3, wsm_dma_arena_valid(%rip)
    jmp .Ldma_done
.Ldma_bad_alignment:
    movq $4, wsm_dma_arena_valid(%rip)
    jmp .Ldma_done
.Ldma_noncontiguous:
    movq $5, wsm_dma_arena_valid(%rip)
    jmp .Ldma_done
.Ldma_overflow:
    movq $6, wsm_dma_arena_valid(%rip)

.Ldma_done:
    popq %r13
    popq %r12
    popq %rbx
    ret

.section .note.GNU-stack,"",@progbits
