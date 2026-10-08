# M3 timer/IRQ substrate (#78 Phase A)

This is the first mechanism-only slice of the task scheduler milestone.

## What is proved

On the existing QEMU `q35` machine profile, the pure x86-64 runtime:

1. installs one bounded IDT interrupt gate at vector 32 using the current code selector;
2. remaps the legacy 8259 PIC and unmasks only IRQ0;
3. programs PIT channel 0 in mode 3 with divisor 1193 (~1000 Hz);
4. enables interrupts;
5. receives at least eight real IRQ0 entries;
6. acknowledges every IRQ0 with a master-PIC EOI;
7. records a deterministic logical 0/1 slot alternation per tick;
8. disables interrupts and restores the previously observed PIC masks;
9. fails closed under a test-only mutation that masks IRQ0.

The wait loop is finite. QEMU’s outer deadline remains an independent hang guard.

## What is NOT proved

This slice does **not** claim:
- task context save/restore;
- independent task stacks;
- preemption;
- Lisp scheduler policy;
- final SENS oracle parity.

The logical slot counter is only timer evidence for the next slice. It must not be described as a task switch.

## Boundary

PIC/PIT/IDT/EOI are substrate mechanism. They add no D2/SENS control identity. The next slice may build scheduler policy above this clock only after a real saved-context contract exists.
