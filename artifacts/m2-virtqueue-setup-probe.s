# M2 / #82 queue0 setup probe.
# Returns target fixnum 1 only when modern virtio-blk queue0 is fully enabled
# over the #84 DMA arena and a bounded notify address was derived.
.text
.globl wsm_entry
.type wsm_entry, @function
.extern wsm_virtio_blk_prepare_queue0
.extern wsm_virtio_queue0_valid
.extern wsm_virtio_queue0_size
.extern wsm_virtio_queue0_notify_addr

wsm_entry:
    call wsm_virtio_blk_prepare_queue0
    cmpl $1, %eax
    jne .Lqueue_probe_fail
    cmpq $1, wsm_virtio_queue0_valid(%rip)
    jne .Lqueue_probe_fail
    cmpq $8, wsm_virtio_queue0_size(%rip)
    jne .Lqueue_probe_fail
    movq wsm_virtio_queue0_notify_addr(%rip), %rcx
    testq %rcx, %rcx
    jz .Lqueue_probe_fail
    testq $1, %rcx
    jnz .Lqueue_probe_fail

    movq $11, %rax                   # target fixnum 1
    ret

.Lqueue_probe_fail:
    movq $3, %rax                    # target fixnum 0
    ret
