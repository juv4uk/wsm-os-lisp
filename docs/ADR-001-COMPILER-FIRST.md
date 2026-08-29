# ADR-001: compiler-first WSM machine path

**Status:** ACCEPTED  
**Date:** 2026-08-29

## Decision

Build the first `wsm-os` executable through the existing CML compiler
pipeline before attempting a full `no_std` port of the Rust interpreter.

```text
WSM source
  -> CML parser + macro expansion + fail-closed semantic admission
  -> shared CML IR
  -> new x86_64-freestanding assembly backend
  -> wsm-os target ABI/runtime
  -> hosted link witness
  -> QEMU boot image
  -> my-lisp oracle comparison
```

The new backend belongs in `cml`. Boot, memory, target ABI and platform
services belong in `wsm-os`.

## Why this avoids duplicate work

CML already owns:

- WSM parsing and macro expansion;
- a fail-closed semantic admission pass;
- backend-neutral `Ir`;
- an FPGA backend;
- a hosted C backend with closures/environment implementation evidence.

Creating another parser, AST, lowering pass or compiler inside `wsm-os` would
fork those responsibilities. Converting all of `my-lisp` to `no_std` before a
boot witness would instead pull reader, evaluator, capability registry and
host-oriented values into the critical path.

The compiler-first path reuses CML while the canonical `my-lisp` remains the
oracle. A later interactive interpreter is still possible; it is not required
to prove AOT WSM execution.

## Ownership boundary

| Concern | Authority |
|---|---|
| WSM meaning, truth, errors and canonical output | `my-lisp` contract/oracle |
| Parse, macro expansion, semantic admission and IR | CML |
| x86_64 assembly emission from admitted IR | CML |
| Target value representation and calling convention | `wsm-os` target contract |
| Heap, OOM, serial, panic, boot and image layout | `wsm-os` |
| Hardware evidence | `wsm-os` QEMU/physical test ledger |

## Assembly and calling convention

The first backend emits deterministic GNU assembler x86_64 (`.s`). Generated
functions use the integer-register portion of the System V AMD64 calling
convention.

This convention is a register/stack ABI, not an operating-system dependency.
It permits one emitted object to be:

1. called by a bounded hosted test harness; and
2. linked unchanged into the freestanding image.

Generated program code may call only the versioned WSM runtime ABI, initially:

```text
wsm_cons  wsm_car  wsm_cdr  wsm_eq  wsm_atom  wsm_fail
```

Serial printing and boot functions are not language primitives and remain
outside compiled program semantics.

## Target value representation

`wsm-os` defines its own machine-readable target contract. It does not import
Rust enum layout or blindly reuse `my-lisp::layout::NanBox`.

The inspected `NanBox` is useful evidence but contains host pointers and
representations for strings, TCP values, closures and reference-counted
objects. Some encodings are explicitly unowned layout witnesses. They are not
a safe freestanding ownership contract.

The first target admits only:

```text
nil | true | signed fixnum | interned symbol | cons pointer
```

Tag width, alignment, pointer ownership, heap bounds, overflow and OOM behavior
must be specified before the emitter uses numeric constants.

## Contract gap

CML currently claims my-lisp contract 2.0 while observing contract 3.0. Its IR
also has known, fail-closed limitations. Therefore:

- the x86 backend may implement a named, tested subset;
- every admitted form must have oracle fixtures;
- unsupported forms fail before assembly emission;
- `CML x86 backend exists` must not be reported as `my-lisp 3.0 compiled`;
- contract 3.0 error categories require separate backend conformance evidence.

The first fixture `(cons (quote A) (quote B))` avoids the known 3.0 error-kind
gap, but its value and output still require oracle comparison.

## Reuse from existing implementations

- CML C backend: closure/environment/runtime design reference, not emitted
  freestanding code.
- CML FPGA backend: fail-closed target validation and deterministic emission
  pattern, not x86 register allocation.
- McCarthy x86_64 prototype: tagged-value and cons-allocation experiment, not
  language authority or bare-metal runtime.
- fpga-lisp: machine-readable target contract and evidence discipline, not
  instruction encoding.

## Verification ladder

```text
IR-ADMISSION-PASS
  -> ASM-GOLDEN-PASS
  -> ASSEMBLE-PASS
  -> NO-UNRESOLVED-HOST-SYMBOLS
  -> HOST-RUNTIME-PARITY
  -> QEMU-BOOT-PARITY
  -> PHYSICAL-HARDWARE-PARITY
```

Hosted parity is deliberately retained: it localizes compiler/runtime bugs
before boot integration. It does not count as bare-metal evidence.

## Rejected alternatives

### Put an x86 compiler in `wsm-os`

Rejected because it duplicates CML parsing, IR and backend admission.

### Port all of `my-lisp` to `no_std` first

Deferred because it makes global registry, time/stdin, allocation and the full
reader/evaluator prerequisites for the first boot witness.

### Compile through hosted C

Useful as an oracle, rejected as the final path because libc/startup leakage
can be hidden and the owner explicitly wants inspectable assembly.

### Hand-write the first Lisp program in assembly

Rejected as product architecture. Handwritten runtime functions are allowed;
program semantics must come from CML IR so later WSM programs do not require
manual assembly edits.
