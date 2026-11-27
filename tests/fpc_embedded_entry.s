.section .text
.global _start
.extern wsm_fpc_embedded_probe

_start:
    movl $40, %edi
    movl $2, %esi
    call wsm_fpc_embedded_probe
1:
    hlt
    jmp 1b
