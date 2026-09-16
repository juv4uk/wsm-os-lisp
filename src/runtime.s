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
    popq %rbx
    ret

.Lhandoff_done_nooffset:
    movq $0, wsm_target_phys_mem_offset(%rip)
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
    movl %eax, %r12d          # store discovered dev

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
    # Fail closed: ABI violation (4) with offending value = nil.
    movq $ERR_ABI, %rsi
    movq $WSM_NIL, %rdx
    jmp wsm_fail

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
    call .Ldecode_check_mmio_cap        # RAX = virt base, or 0 if invalid
    testq %rax, %rax
    jz .Lmmio_cap_fail                  # stack still has [rbx, saved_ctx]
    movq %rax, %rbx
    popq %rdi                           # restore ctx
    # RDX holds offset fixnum; decode right-shift by 3.
    movq %rdx, %rax
    sarq $3, %rax
    # Bounds check: offset + 4 <= region_len
    movq wsm_mmio_region_len(%rip), %rcx
    movq %rax, %r10
    addq $4, %r10
    jc .Lmmio_bounds_fail
    cmpq %rcx, %r10
    ja .Lmmio_bounds_fail
    # Compute address = base + offset
    addq %rax, %rbx
    movl (%rbx), %eax
    shlq $3, %rax
    orq $WSM_TAG_FIXNUM, %rax
    popq %rbx
    ret

.Lmmio_bounds_fail:
    popq %rbx
    jmp .Lmmio_fail_common
.Lmmio_cap_fail:
    # Invalidate the capability usage: pop saved ctx, then the base save.
    popq %rdi
    popq %rbx
.Lmmio_fail_common:
    movq $ERR_ABI, %rsi
    movq $WSM_NIL, %rdx
    jmp wsm_fail

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
    movq %rsi, %rdi
    call .Ldecode_check_mmio_cap
    testq %rax, %rax
    jz .Lmmio_cap_fail2                 # stack still has [r12, rbx, saved_ctx]
    movq %rax, %rbx
    popq %rdi                           # restore ctx
    # RDX = offset (fixnum), decode
    movq %rdx, %rax
    sarq $3, %rax
    # Bounds: offset + 4 <= len  (addq sets CF on overflow)
    movq wsm_mmio_region_len(%rip), %r10
    movq %rax, %r11
    addq $4, %r11
    jc .Lmmio_bounds_fail2
    cmpq %r10, %r11
    ja .Lmmio_bounds_fail2
    # RCX = value (fixnum), decode
    movq %rcx, %r12
    sarq $3, %r12
    movl %r12d, (%rbx,%rax)           # volatile store
    popq %r12
    popq %rbx
    movq $WSM_CANONICAL_T, %rax
    ret

.Lmmio_bounds_fail2:
    popq %r12
    popq %rbx
    jmp .Lmmio_fail_common2
.Lmmio_cap_fail2:
    # Invalidate the capability usage: pop saved ctx, then base+value saves.
    popq %rdi
    popq %r12
    popq %rbx
.Lmmio_fail_common2:
    movq $ERR_ABI, %rsi
    movq $WSM_NIL, %rdx
    jmp wsm_fail

# ---------------------------------------------------------------------------
# Internal: validate a provisioned MMIO capability.
# In:  RDI = capability word
# Out: RAX = provisioned virtual base (≥1), or 0 if the capability is invalid
#      (not provisioned / tag mismatch / nonce mismatch). The caller decides
#      how to fail; no redirections to wsm_fail happen here so stack unwinding
#      stays in the caller.
# ---------------------------------------------------------------------------
.Ldecode_check_mmio_cap:
    movq wsm_mmio_region_valid(%rip), %rax
    cmpq $1, %rax
    jne .Lcap_decode_invalid
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

.section .note.GNU-stack,"",@progbits
