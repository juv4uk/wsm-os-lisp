# M3 / #78 first timer/IRQ substrate probe.
# This proves real IRQ0 delivery and bounded acknowledgement only.
.text
.globl wsm_entry
.type wsm_entry, @function
.extern wsm_m3_timer_irq_witness
.extern wsm_m3_timer_ticks
.extern wsm_m3_logical_alternations

wsm_entry:
    call wsm_m3_timer_irq_witness
    cmpl $1, %eax
    jne .Lfail
    cmpq $8, wsm_m3_timer_ticks(%rip)
    jb .Lfail
    cmpq $8, wsm_m3_logical_alternations(%rip)
    jb .Lfail
    movq $11, %rax                  # target fixnum 1
    ret
.Lfail:
    movq $3, %rax                   # target fixnum 0
    ret
