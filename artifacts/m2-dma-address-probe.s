# M2 / #84 mechanism-only probe.
# Returns fixnum 1 only when the runtime proved a non-zero, page-aligned,
# physically contiguous one-page DMA arena. Returns fixnum 0 otherwise.
# Raw virtual/physical addresses are never returned through the language
# observer.
.text
.globl wsm_entry
.type wsm_entry, @function
.extern wsm_dma_arena_valid
.extern wsm_dma_arena_phys

wsm_entry:
    movq wsm_dma_arena_valid(%rip), %rax
    cmpq $1, %rax
    jne .Ldma_probe_fail

    movq wsm_dma_arena_phys(%rip), %rcx
    testq %rcx, %rcx
    jz .Ldma_probe_fail
    testq $0xFFF, %rcx
    jnz .Ldma_probe_fail

    movq $11, %rax                   # exact target fixnum 1: (1 << 3) | 3
    ret

.Ldma_probe_fail:
    movq $3, %rax                    # exact target fixnum 0: (0 << 3) | 3
    ret
