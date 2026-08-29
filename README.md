# wsm-os

Research and executable prototypes for a WSM-native Lisp machine on real
hardware.

The project starts with a narrow claim: boot a minimal target, establish a
typed host boundary, and execute one verified WSM expression. It does not yet
claim to be an operating system, a `no_std` port of all of my-lisp, or a
bare-metal CUDA runtime.

## Authority boundaries

- `my-lisp` owns WSM language semantics and remains the reference oracle.
- `cml` owns portable lowering and target admission.
- `fpga-lisp` owns the bounded FPGA Lisp-machine implementation.
- `wsm-os` owns boot, platform services, and bare-metal integration evidence.

## First milestone

```text
QEMU x86_64 boot
  -> serial output
  -> bounded allocator
  -> minimal WSM evaluator boundary
  -> evaluate a frozen expression
  -> compare result with canonical my-lisp
```

See [docs/BOOTSTRAP-PLAN.md](docs/BOOTSTRAP-PLAN.md).

The inspected, commit-pinned reuse decisions are recorded in
[docs/ECOSYSTEM-REUSE-MAP.md](docs/ECOSYSTEM-REUSE-MAP.md).
