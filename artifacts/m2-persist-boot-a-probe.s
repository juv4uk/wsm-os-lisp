# M2 / #77 boot-A persistence probe.
.text
.globl wsm_entry
.type wsm_entry, @function
.extern wsm_virtio_blk_persist_sector0_write
.extern wsm_virtio_persistence_stage
.extern wsm_virtio_block_completed_requests

wsm_entry:
    call wsm_virtio_blk_persist_sector0_write
    cmpl $1, %eax
    jne .Lfail
    cmpq $3, wsm_virtio_persistence_stage(%rip)
    jne .Lfail
    cmpq $3, wsm_virtio_block_completed_requests(%rip)
    jne .Lfail
    movq $11, %rax
    ret
.Lfail:
    movq $3, %rax
    ret
