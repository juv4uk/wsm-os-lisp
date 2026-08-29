# Ecosystem reuse map

**Observed:** 2026-08-29. Links below pin the inspected commits so future
changes do not silently strengthen these claims.

## Recommended architecture

```text
WSM source
   | semantic oracle / conformance
   v
my-lisp ------------------------------+
   | admitted subset                  |
   v                                  | compare value + error
CML IR -> future freestanding backend |
   |                                  |
   v                                  |
wsm-os boot/runtime ------------------+
```

`wsm-os` should own platform boot and services. It should not fork WSM
semantics, CML lowering rules, or the FPGA ISA.

## Reuse now

| Source | Reuse in `wsm-os` | Status and limit |
|---|---|---|
| [`my-lisp/language-contract.my`](https://github.com/juv4uk/my-lisp/blob/667b587394dc8d3fc8dadff7c925e5bce68ed887/language-contract.my) | Semantic authority and version gate | Direct contract reuse; not machine code |
| [`my-lisp` conformance fixtures](https://github.com/juv4uk/my-lisp/tree/667b587394dc8d3fc8dadff7c925e5bce68ed887/tests/fixtures) | Oracle-parity inputs and expected behavior | Reuse test data selectively; preserve exact contract tier |
| [`canonical-serialization.md`](https://github.com/juv4uk/my-lisp/blob/667b587394dc8d3fc8dadff7c925e5bce68ed887/docs/canonical-serialization.md) | Stable serial/boot transcript representation | Direct specification reuse |
| [`syntax::fasl`](https://github.com/juv4uk/my-lisp/blob/667b587394dc8d3fc8dadff7c925e5bce68ed887/crates/my-lisp/src/syntax.rs) | Pre-parsed, source-hash-bound program image pattern | Reuse format/code only after `alloc` portability audit |
| [`CML Ir`](https://github.com/juv4uk/cml/blob/bfb0cac3ab3938924a58e749d99eec6ca06a8a88/src/ir.rs) and [`lower`](https://github.com/juv4uk/cml/blob/bfb0cac3ab3938924a58e749d99eec6ca06a8a88/src/lower.rs) | Front-end-independent AOT boundary | Best starting point for a freestanding target; CML coverage is narrower than current my-lisp |
| [`CML C backend`](https://github.com/juv4uk/cml/blob/bfb0cac3ab3938924a58e749d99eec6ca06a8a88/src/c_backend.rs) | Reference for closures, environments and emitted runtime layout | Design/code reference; current output is hosted C, not freestanding C |
| [`fpga-lisp/isa-contract.my`](https://github.com/juv4uk/fpga-lisp/blob/80e2fc170650b391f128353985445291da493957/isa-contract.my) | Example of a machine-readable target contract | Reuse the contract pattern, not its 32-bit FPGA encoding |
| [`fpga-lisp` testing contract](https://github.com/juv4uk/fpga-lisp/blob/80e2fc170650b391f128353985445291da493957/docs/testing.md) | Boot-image -> execute -> stable observable result evidence shape | Direct methodology reuse |

All three source repositories are MIT at the inspected commits. Linking does
not copy code; any later copied source must retain the applicable license and
notice.

## Adapt after a bounded extraction

### `my-lisp` core

[`crates/my-lisp`](https://github.com/juv4uk/my-lisp/tree/667b587394dc8d3fc8dadff7c925e5bce68ed887/crates/my-lisp)
has no normal Cargo dependencies and already separates filesystem, process and
TCP capabilities into
[`my-lisp-host`](https://github.com/juv4uk/my-lisp/tree/667b587394dc8d3fc8dadff7c925e5bce68ed887/crates/my-lisp-host).
That is the strongest reuse seam in the ecosystem.

It is **not yet `no_std`**. The inspected core still imports:

- `std::rc::Rc`, `RefCell`, `HashMap`, `HashSet` and formatting;
- `std::sync::{Arc, OnceLock, RwLock}` for buffers/capability registry;
- `std::time::Instant` for timing primitives;
- `std::io::stdin` for the line reader;
- `std::error::Error` for the host error trait.

Most containers can move to `alloc`/`core`. Timing, stdin and the global
capability registry require explicit platform decisions. Therefore the first
code change should be a feature-gated portability inventory, not adding
`#![no_std]` to the whole crate.

### FASL rather than a text reader in the first image

The first boot witness should embed a source-hash-bound FASL expression. This
avoids pulling the complete text reader, file loading and standard library into
the boot image before the evaluator boundary works. Text REPL support remains
a later platform capability.

## Reference only

### McCarthy x86_64 kernel

The ecosystem's
[`mccarthy_eval_x86_64`](https://github.com/juv4uk/ecosystem/tree/7060d6fd6d2fdc48d75b830083775a49d60beff2/prototypes/mccarthy_eval_x86_64)
is real executing assembly and proves tagged values, cons allocation,
reader/eval/apply and recursive Lisp on this CPU family.

It is not a boot kernel:

- it has its own reduced Lisp semantics, not the my-lisp contract;
- it is assembled and linked as a hosted Linux program;
- it uses process startup, `argv`, libc file I/O and OS-provided memory;
- several runtime and recovery obligations differ from `wsm-os`.

Reuse its experiments and fixtures as an x86 implementation reference. Do not
make it the semantic or boot authority.

### FPGA Lisp machine

[`fpga-lisp`](https://github.com/juv4uk/fpga-lisp/tree/80e2fc170650b391f128353985445291da493957)
already proves a true independent Lisp machine with tagged words, heap, ISA,
UART bootloader and assembler. Its reusable contribution to `wsm-os` is the
discipline:

```text
machine-readable ISA
-> deterministic image
-> simulated boot path
-> observable result
-> synthesis evidence
-> physical evidence
```

The instruction encoding, BRAM layout and UART implementation are FPGA-owned
and must not be copied into an x86 target merely for uniformity.

## Do not reuse as assumed facts

- `Rc` is not a tracing garbage collector and does not reclaim cycles.
- A dependency-free Rust crate is not automatically `no_std`.
- C output is not automatically freestanding or bootable.
- AVX2/BMI2 should follow profiling; it is not the first correctness seam.
- GTX 1050 Ti CUDA requires a driver/runtime strategy and is not a bare-metal
  primitive of the Lisp machine.
- QEMU evidence does not imply owner-hardware boot evidence.

## First executable reuse spike

1. Pin one Tier-1 WSM expression and expected value/error from my-lisp.
2. Lower the admitted form through CML IR.
3. Add a tiny freestanding emitter/runtime in `wsm-os` for only the needed IR
   nodes.
4. Boot it in QEMU and emit a canonical result over serial.
5. Compare the serial result against the canonical my-lisp oracle.

This route reuses the most mature boundaries without requiring an immediate
`no_std` conversion of the full interpreter.
