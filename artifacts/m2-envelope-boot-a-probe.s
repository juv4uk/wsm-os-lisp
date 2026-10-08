# M2 / #95 Boot-A canonical envelope writer.
.text
.globl wsm_entry
.type wsm_entry, @function
.extern wsm_virtio_blk_persist_envelope_write
.extern wsm_virtio_persistence_stage
.extern wsm_virtio_block_completed_requests

wsm_entry:
    call wsm_virtio_blk_persist_envelope_write
    cmpl $1, %eax
    jne .Lfail
    cmpq $12, wsm_virtio_persistence_stage(%rip)
    jne .Lfail
    cmpq $3, wsm_virtio_block_completed_requests(%rip)
    jne .Lfail
    movq $11, %rax
    ret
.Lfail:
    movq $3, %rax
    ret
