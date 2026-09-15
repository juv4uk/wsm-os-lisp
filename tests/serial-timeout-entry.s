# PHYSICAL-SERIAL-GATE-1 (issue #31): forced never-ready COM1 execution harness.
#
# Assembles the real src/entry.s with the single LSR read (`inb %dx,%al` inside
# serial_putc) overridden to always return a THRE-clear status byte. Under QEMU
# the real bounded serial_putc must therefore exhaust its finite poll bound and
# terminate through serial_transport_failure (isa-debug-exit val 0x13 -> 39),
# never through kernel_failure / a runtime condition / an infinite spin.
#
# The marker emission in serial_transport_failure uses real `outb`, so on a live
# QEMU UART the "WSM-OS SERIAL-TRANSPORT-FAIL" line is captured in the log while
# no normal BOOT/RESULT transcript is produced.

.macro inb port, dest
  movb $0x00, \dest
.endm

.include "src/entry.s"
