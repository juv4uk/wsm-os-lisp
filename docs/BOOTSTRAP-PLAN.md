# Bootstrap plan

## Evidence ladder

`DESIGNED -> BOOTED -> WSM-EVAL-PASS -> ORACLE-PARITY -> REAL-HARDWARE-PASS`

Each state requires its own evidence. QEMU boot does not prove real-hardware
support, and a host-side WSM result does not prove bare-metal execution.

## Phase 0 — inventory before porting

1. Split my-lisp dependencies into semantic core and host services.
2. Classify each `std` dependency: replace with `core`/`alloc`, inject through
   a platform trait, or keep host-only.
3. Record graph/cycle semantics explicitly. `Rc` releases acyclic ownership;
   it is not a tracing collector and does not collect reference cycles.
4. Choose the smallest evaluator slice that can execute without filesystem,
   TCP, subprocesses, threads, or wall-clock services.

## Phase 1 — boot witness

- x86_64 UEFI/QEMU first; no direct install on the owner's machine.
- serial console as the initial observable interface.
- deterministic panic report and bounded allocator.
- CI boots the image under a timeout and matches a fixed serial transcript.

## Phase 2 — WSM semantic witness

- expose platform services behind an explicit boundary;
- execute one frozen WSM expression;
- compare value and error behavior with the canonical my-lisp oracle;
- expand only after parity is green.

## Deferred until evidence exists

- GUI, keyboard REPL, disk image persistence and networking;
- live image mutation and recovery semantics;
- AVX2/BMI2 lowering (only after profiling ordinary scalar code);
- NVIDIA GPU support. GTX 1050 Ti requires a driver/runtime strategy; CUDA is
  not treated as a direct bare-metal primitive;
- physical boot on owner hardware.

## First decision required

Choose between:

1. a small `no_std` semantic-core extraction from my-lisp; or
2. a CML-compiled WSM subset linked into the boot image.

The decision follows a dependency inventory and one executable spike, not an
up-front rewrite of my-lisp.
