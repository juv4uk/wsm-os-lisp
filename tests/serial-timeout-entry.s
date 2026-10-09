# Historical #37 (#31) QEMU fault-injection harness.
# Entry source is unmodified. Only the single COM1 line-status inb is replaced.
.macro inb port, dest
  movb $0x00, \dest
.endm

.include "src/entry.s"
