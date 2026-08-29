# wsm-os implementation plan

**Status:** ACTIVE  
**Target:** x86_64 UEFI/QEMU first  
**First proof:** one CML-admitted WSM expression boots and produces the same
canonical result as `my-lisp`.

The concrete target and build constraints are pinned in
[`OWNER-HARDWARE-PROFILE.md`](OWNER-HARDWARE-PROFILE.md).

## Definition of the first release

`v0.1` is not a general operating system. It is a reproducible boot image that:

1. starts under QEMU with no host process after boot;
2. owns a bounded heap;
3. executes one compiled WSM fixture;
4. writes a canonical result and structured failure to the serial port;
5. matches the pinned `my-lisp` oracle;
6. is built and tested automatically under a timeout.

## Evidence states

```text
DESIGNED
  -> HOST-BUILD-PASS
  -> QEMU-BOOT-PASS
  -> WSM-EVAL-PASS
  -> ORACLE-PARITY
  -> REAL-HARDWARE-PASS
```

No state implies the next. In particular, `QEMU-BOOT-PASS` is not physical
hardware evidence.

## M0 — pin authority and choose the boot substrate

### Work

- record exact `my-lisp`, CML and `fpga-lisp` contract commits;
- add a machine-readable target manifest with architecture, byte order,
  pointer width and contract versions;
- compare the smallest viable x86_64 boot substrates;
- check license and NOTICE obligations before adding any dependency;
- choose one QEMU invocation and one serial success marker.

### Decision criteria

- UEFI/QEMU support on the existing WSL host and GitHub runner;
- maintained Rust target support;
- no hidden network or host filesystem dependency at runtime;
- license compatible with this repository;
- deterministic non-interactive test path.

### Done when

The chosen boot dependency/version, license, target triple and QEMU command are
committed. No boot framework is added before this gate.

## M1 — minimal boot and serial witness

### Work

- create a freestanding Rust kernel crate;
- provide `_start`/UEFI entry, panic handler and serial writer;
- boot under QEMU and print exactly one versioned line;
- terminate QEMU through a test-only exit device or bounded timeout;
- add a lightweight CI job.

### Required evidence

```text
WSM-OS BOOT schema=1 arch=x86_64 status=ok
```

- image exists;
- QEMU process exits as expected;
- transcript matches exactly;
- malformed/panic path is distinguishable from success.

## M2 — target contract, values and bounded memory

### Work

- define a machine-readable `wsm-os` target contract;
- start with only `nil`, true, signed integer, symbol and cons;
- define tag bits, alignment, endianness and canonical output;
- add a deterministic bump allocator with explicit heap bounds;
- return a structured out-of-memory error rather than corrupting memory;
- keep target layout independent from Rust's internal `Value` layout.

### Required evidence

- encode/decode round trips for every admitted value;
- exact heap-boundary and OOM fixtures;
- `()` remains the empty-list spelling at the WSM boundary;
- only `()`/nil is false, matching the pinned language contract.

## M3 — CML freestanding x86_64 seam

### Work

- select the smallest CML IR subset needed by the first expression;
- keep WSM parsing and semantic admission in CML on the build host;
- emit deterministic freestanding assembly or object code for the target ABI;
- reject unsupported IR nodes with named errors;
- do not route through hosted libc or silently fall back to the C backend;
- preserve CML ownership of lowering and `wsm-os` ownership of target ABI.

### First admitted subset

```text
Int | Nil | True | Quote(Symbol) | Cons | Car | Cdr | Eq | Atom
```

This is a ceiling, not a promise that every node enters the first patch.

### Required evidence

- same input produces byte-identical generated artifact;
- unsupported input fails before image construction;
- generated code has no unresolved libc/OS symbols;
- host-side unit tests cover emitted control and data layout.

## M4 — first WSM execution witness

### Frozen fixture

```lisp
(cons (quote A) (quote B))
```

Expected canonical result:

```text
(A . B)
```

### Work

- evaluate the fixture with pinned canonical `my-lisp`;
- lower it through CML;
- link it with the M1/M2 runtime;
- boot the image and print a versioned result record;
- compare value and error class, not merely process exit code.

### Required evidence

```text
WSM-OS RESULT schema=1 value=(A . B) status=ok
```

The committed test stores the expression, oracle result, contract SHAs and
serial transcript together.

## M5 — small conformance ladder

Expand one semantic obligation at a time:

1. `()` truth and conditional branch;
2. integer and symbol identity;
3. `car`/`cdr`/`cons`;
4. nested lists and canonical printer;
5. named type/arity/OOM errors;
6. one closure only after environment layout is ratified.

Every addition requires:

```text
my-lisp oracle
  == CML admitted meaning
  == QEMU observable result
```

Do not add keyboard, disk, network or GUI work during this milestone.

## M6 — decide full interpreter portability

Only after M4 is green, inventory a possible `my-lisp` core reuse:

- replace eligible `std` containers with `alloc`/`core` imports;
- make time, stdin and global capability registry optional platform services;
- test `no_std + alloc` compilation separately from the hosted crate;
- decide whether the complete evaluator is smaller and safer than continuing
  the CML AOT subset.

This is a measured decision. The project may retain both:

- AOT images for bounded/reproducible programs;
- an interactive interpreter for a later Lisp-machine environment.

## Deferred projects

- keyboard REPL and graphical interface;
- persistent Lisp image and recovery;
- FAT/network stack;
- SMP and preemptive scheduling;
- AVX2/BMI2 optimization;
- CUDA integration;
- direct boot on the owner's physical machine.

Each becomes a separate milestone only after the previous semantic evidence is
green.

## Immediate execution order

```text
1. BOOT-SUBSTRATE-DECISION
2. SERIAL-BOOT-WITNESS
3. TARGET-VALUE-CONTRACT
4. BOUNDED-ALLOCATOR
5. CML-FREESTANDING-X86-SEAM
6. FIRST-WSM-ORACLE-PARITY
```

The next implementation action is `BOOT-SUBSTRATE-DECISION`; it is the only
item allowed to introduce a third-party boot dependency.
