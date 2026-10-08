# M2 / #95 Boot-B canonical envelope validator.
.text
.globl wsm_entry
.type wsm_entry, @function
.extern wsm_virtio_blk_persist_envelope_verify
.extern wsm_virtio_persistence_stage
.extern wsm_virtio_block_completed_requests

wsm_entry:
    call wsm_virtio_blk_persist_envelope_verify
    cmpl $1, %eax
    jne .Lfail
    cmpq $20, wsm_virtio_persistence_stage(%rip)
    jne .Lfail
    cmpq $1, wsm_virtio_block_completed_requests(%rip)
    jne .Lfail
    movq $11, %rax
    ret
.Lfail:
    movq $3, %rax
    ret
