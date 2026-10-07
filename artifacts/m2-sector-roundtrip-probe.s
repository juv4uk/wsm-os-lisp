# M2 / #82 real sector I/O probe.
# Returns target fixnum 1 only after:
# fresh IN(0)==zero -> OUT deterministic 512B -> FLUSH -> IN(0)==payload.
.text
.globl wsm_entry
.type wsm_entry, @function
.extern wsm_virtio_blk_sector0_roundtrip
.extern wsm_virtio_block_roundtrip_stage
.extern wsm_virtio_block_completed_requests

wsm_entry:
    call wsm_virtio_blk_sector0_roundtrip
    cmpl $1, %eax
    jne .Lsector_probe_fail
    cmpq $6, wsm_virtio_block_roundtrip_stage(%rip)
    jne .Lsector_probe_fail
    cmpq $4, wsm_virtio_block_completed_requests(%rip)
    jne .Lsector_probe_fail
    movq $11, %rax                   # target fixnum 1
    ret

.Lsector_probe_fail:
    movq $3, %rax                    # target fixnum 0
    ret
