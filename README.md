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
  -> minimal WSM execution/runtime boundary
  -> evaluate a frozen expression
  -> compare result with canonical my-lisp
```

See [docs/BOOTSTRAP-PLAN.md](docs/BOOTSTRAP-PLAN.md).

The inspected, commit-pinned reuse decisions are recorded in
[docs/ECOSYSTEM-REUSE-MAP.md](docs/ECOSYSTEM-REUSE-MAP.md).

The executable milestone sequence and evidence gates are in
[docs/IMPLEMENTATION-PLAN.md](docs/IMPLEMENTATION-PLAN.md).

The privacy-scrubbed physical and WSL target inventory is in
[docs/OWNER-HARDWARE-PROFILE.md](docs/OWNER-HARDWARE-PROFILE.md).

The compiler-first ownership decision is recorded in
[docs/ADR-001-COMPILER-FIRST.md](docs/ADR-001-COMPILER-FIRST.md).

Executable swarm work is tracked in [`tasks.my`](tasks.my).

The first machine-readable ABI and its generated WSM projection are documented
in [`docs/TARGET-ABI.md`](docs/TARGET-ABI.md).

The versioned identity and reproducibility boundary for compiled definitions
is documented in [`docs/DEFINITION-CAPSULE.md`](docs/DEFINITION-CAPSULE.md).

## Current evidence

The frozen `(cons (quote A) (quote B))` fixture now passes the complete first
execution chain: pinned my-lisp oracle, CML-generated object, hosted runtime,
freestanding UEFI image, and bounded QEMU execution all agree on `(A . B)`.
This is `QEMU-BOOT-PARITY`, not a physical-hardware claim.
