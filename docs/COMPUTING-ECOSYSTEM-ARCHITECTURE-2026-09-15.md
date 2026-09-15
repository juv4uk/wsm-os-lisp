# Computing Ecosystem — Architecture, Dependencies and Flow (2026-09-15)

![My Computing Ecosystem — Architecture, Dependencies and Flow](architecture/computing-ecosystem-architecture.png)

Owner-authored architecture diagram of the full stack, from Lisp semantics
down to hardware. This repository (`wsm-os-lisp`) is the **Target Runtime /
OS** layer on the diagram: it implements the ABI (`wsm_mmio_*`,
`wsm_pci_*`, `wsm_*` syscalls) that `CML` emits calls to, owns the runtime
system (memory, GC, threads), the OS interface (processes, I/O, devices),
drivers/devices (PCI, MMIO, virtio), and platform support — and it owns
the concrete device access, not `my-lisp` or `CML`. Per ADR-004, production
kernel/system behavior is Lisp; the irreducible physical mechanism is
x86-64 assembly — no C/Rust evaluator/runtime in the canonical target
unless separately re-ratified.

Full stack, top to bottom: User/Developer → **my-lisp** (Language &
Semantics, owns Canon/meaning) → **CML** (Compiler for My Lisp, consumes
Lisp semantics + verified CPU profiles, never redefines meaning) →
**Target Runtime / OS** (this repo) → Hardware (x86-64 CPU, devices, FPGA).

This diagram is a snapshot of intent, not itself an authority document —
`juv4uk/ecosystem#7` (the living cross-repo map) remains the authoritative,
updated-in-place source of truth about current ownership and boundaries.
