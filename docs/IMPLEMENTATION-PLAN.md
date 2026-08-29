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
  -> TARGET-CONTRACT-PASS
  -> ASM-CODEGEN-PASS
  -> HOST-LINK-PARITY
  -> QEMU-BOOT-PASS
  -> WSM-EVAL-PASS
  -> ORACLE-PARITY
  -> REAL-HARDWARE-PASS
```

No state implies the next. In particular, `QEMU-BOOT-PASS` is not physical
hardware evidence.

## M0 — pin authority and define the target ABI

### Work

- record exact `my-lisp`, CML and `fpga-lisp` contract commits;
- add a machine-readable target manifest with architecture, byte order,
  pointer width and contract versions;
- specify tags, ownership, alignment, calling convention and runtime symbols;
- pin the first admitted CML IR subset;
- pin one oracle expression and expected canonical result;
- shortlist boot substrates without adding one yet.

### Decision criteria

- target constants have one machine-readable source;
- generated code contains no Rust-layout assumptions;
- unsupported IR has a named fail-closed path;
- ABI works in both a hosted harness and the later freestanding image.

### Done when

Target contract, first IR subset and oracle fixture are committed. No emitter
uses numeric tag/ABI constants before this gate.

## M1 — CML x86_64-freestanding assembly backend

### Work

- add the backend to CML, not `wsm-os`;
- consume existing admitted CML IR;
- emit deterministic GNU x86_64 assembly;
- use the target contract rather than duplicated numeric constants;
- reject unsupported IR before partial assembly is returned;
- assemble emitted `.s` and inspect undefined symbols;
- add golden fixtures and exact my-lisp oracle expectations.

### Required evidence

```text
IR admission -> deterministic .s -> object file
```

- repeated emission is byte-identical;
- object code has only versioned `wsm_*` runtime imports;
- no libc, process or filesystem symbols enter generated program code.

## M2 — shared freestanding runtime and hosted parity harness

### Work

- implement only `nil`, true, signed integer, symbol and cons;
- add a deterministic bump allocator with explicit heap bounds;
- return a structured out-of-memory error rather than corrupting memory;
- implement the versioned `wsm_*` runtime calls used by M1;
- link the same emitted object into a small hosted test harness;
- compare result/error against canonical my-lisp;
- keep all host startup/I/O outside the emitted object and runtime core.

### Required evidence

- encode/decode round trips for every admitted value;
- exact heap-boundary and OOM fixtures;
- `()` remains the empty-list spelling at the WSM boundary;
- only `()`/nil is false, matching the pinned language contract.

## M3 — minimal boot and serial witness

### Work

- complete the boot-substrate license/NOTICE decision;
- create a freestanding kernel crate;
- provide UEFI entry, panic handler and serial writer;
- boot under QEMU and print exactly one versioned line;
- terminate through a test-only exit device or bounded timeout;
- add a lightweight CI job.

```text
WSM-OS BOOT schema=1 arch=x86_64 status=ok
```

- image exists;
- QEMU process exits as expected;
- transcript matches exactly;
- malformed/panic path is distinguishable from success.

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
- link the exact M1 object and M2 runtime into the M3 image;
- boot the image and print a versioned result record;
- compare value and error class, not merely process exit code.

### Required evidence

```text
WSM-OS RESULT schema=1 value=(A . B) status=ok
```

The committed test stores the expression, oracle result, contract SHAs and
serial transcript together.

### Verified evidence (2026-08-30)

`84ccad4` links the exact committed compiler object (SHA-256
`c116f6d8b42c91ad176239642ccd0b8965a276d13e86a09767058c4b2fde8293`)
into the freestanding kernel with the M2 runtime. Local Guix QEMU 10.2.1 and
GitHub Actions run `33280152276` both emitted the committed two-record
transcript and reached the structured success exit. This establishes
`QEMU-BOOT-PARITY`; it is not physical-hardware evidence.

## M5 — small conformance ladder

Expand one semantic obligation at a time:

1. `()` truth and conditional branch;
2. integer and symbol identity;
3. `car`/`cdr`/`cons`;
4. nested lists and canonical printer;
5. named type/arity/OOM errors;
6. preserve tail position explicitly in CML metadata and the x86 calling path;
7. prove a 100,000-deep first-order self-tail-call with bounded native stack;
8. one closure only after environment layout and active-frame rules are ratified.

Every addition requires:

```text
my-lisp oracle
  == CML admitted meaning
  == QEMU observable result
```

Do not add keyboard, disk, network or GUI work during this milestone.

Tail-call behavior is a language obligation, not a host optimization. A small
fixture passing with ordinary nested x86 `call` instructions is insufficient:
the generated target must preserve the `my-lisp` constant-host-stack guarantee
for tail recursion. The first proof may use a first-order self call; general
closures and continuations remain later work.

## M5 metadata seams — preserve before the system becomes opaque

After first QEMU parity, add three bounded architectural seams without turning
them into a live environment prematurely:

1. **Definition capsule:** extend the deterministic compiler artifact with a
   stable definition ID, source digest/map, contract versions and revisions,
   generator/toolchain identity, code range/entry, literal/symbol table,
   dependency/import list and explicitly named digest algorithms. CI must
   regenerate the bundle twice, require byte-identical outputs, compare every
   committed artifact with its capsule digest and reject a mismatched section.
   The hosted-generated assembly and kernel-linked committed object must be
   proven to describe the same definition. This is metadata only; it does not
   authorize hot replacement.
2. **Semantic trace:** define a small versioned event vocabulary shared by the
   oracle, hosted x86, QEMU and later FPGA paths. Compare logical operations
   and stable object IDs, never raw addresses or target instruction traces.
3. **Immutable literal-space decision:** decide whether quoted cons graphs may
   reside in a relocatable read-only image section. The current target ABI
   admits cons pointers only from the active heap, so no backend may silently
   emit read-only cons pointers before that ownership rule is ratified.

Structured conditions should extend the opaque `RuntimeContext`: retain the
small `wsm_fail(context, code)` boot ABI while allowing a later condition
record containing operation, values, definition/source identity and explicit
restart capabilities. A condition record alone does not imply resumability.

### Verified definition capsule evidence (2026-08-30)

Commits `0435cb9` and `5a9dc7e` establish definition capsule v1 and a
cross-toolchain deterministic ELF bundle. GitHub Actions run `33281082120`
proved double regeneration, byte identity with committed artifacts, recomputed
section validation, deliberate mismatch rejection, hosted parity and QEMU
parity. The capsule remains inspectable metadata only.

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

Before physical serial evidence, the COM1 writer must use bounded transmitter-
ready polling and distinguish UART timeout from semantic failure. This does not
change the validity of the existing QEMU witness.

Each becomes a separate milestone only after the previous semantic evidence is
green.

## Immediate execution order

```text
1. BOOT-SUBSTRATE-REALIGN
2. REPRODUCIBLE-BOOT-TOOLCHAIN
3. INDEPENDENT-M2-ORACLE-EVIDENCE
4. SERIAL-BOOT-WITNESS
5. FIRST-WSM-ORACLE-PARITY
6. FIXNUM-AND-BRANCH-SLICE
7. TAIL-POSITION-AND-STACK-SAFETY
8. DEFINITION-CAPSULE
9. CROSS-SUBSTRATE-SEMANTIC-TRACE
10. IMMUTABLE-LITERAL-SPACE-DECISION
```

M0–M2 and the compiler-owned M4 artifact bundle already have pushed evidence.
The current critical path is boot-substrate realignment, pinned tool discovery,
independent oracle evidence and then the first QEMU parity witness. No later
metadata or language task may be used to bypass that chain.
