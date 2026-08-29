# Lisp-machine features worth carrying into wsm-os

**Research date:** 2026-08-29  
**Status:** design input, not an implementation contract  
**Scope:** historical manuals, current implementations, and practitioner
discussions; no third-party source code copied

## Executive conclusion

The important property of a Lisp machine was not merely “an OS written in
Lisp” or a special CPU. It was the short, inspectable feedback loop across the
whole system:

```text
named definition
  -> compile one definition
  -> install it in the running world
  -> inspect live objects and callers
  -> encounter a structured condition
  -> repair/restart without discarding the computation
```

For `wsm-os`, the best near-term lesson is therefore **metadata and recovery
before GUI and drivers**. The current compiler-first route is correct: preserve
definition identity, source locations, object identity, structured failure and
deterministic snapshots while the system is still small. A custom filesystem,
window system, GC, scheduler or microcoded CPU should not enter v0.1.

## Evidence boundary

Sources have different authority:

| Class | Use here |
|---|---|
| Symbolics/MIT manuals | Primary evidence for historical mechanisms |
| Mezzano repository | Primary evidence for a current open Lisp OS |
| Practitioner forum reports | Experience reports and design leads, not contracts |
| Our repositories | Authority only for what the current ecosystem implements |

Forum enthusiasm is not proof that an old mechanism is efficient or safe on
modern hardware. Conversely, the absence of a modern commercial Lisp machine
does not show that its interaction model lacked value.

## 1. Definition-centric incremental compilation

### Historical mechanism

Genera operated on individual named definitions rather than treating the file
as the smallest compilation unit. The compiler/editor maintained definition
and caller information; a programmer could compile one function, install it,
and immediately test it. A practitioner describing Open Genera highlights the
same per-function sub-second edit/compile/load loop.

### What we already have

- `my-lisp` has parser/evaluator sessions, FASL parse snapshots and LSP symbol
  discovery.
- CML has a backend-neutral IR and deterministic target emitters.
- The swarm already records content identity, commits and evidence.

### Adopt

Make the future WSM image format definition-centric:

```text
definition-id
source-content-id
contract-version
code-range
literal/symbol table
source map
callers/dependencies
```

Do not implement hot replacement yet. First require CML to preserve this
metadata beside each emitted function. Hot replacement becomes safe only after
calling convention, closure environment and active-frame rules are explicit.

**Priority:** high, after first QEMU parity.  
**Why:** difficult to retrofit after code addresses and images become opaque.

## 2. Conditions, restarts and repairable execution

### Historical mechanism

Genera used a condition system throughout the OS and applications. The
debugger could inspect frames and values, continue using a provided restart,
return a replacement value, alter an argument and reinvoke a function, or edit
and recompile before retrying. The Symbolics debugger manual groups commands
around stack inspection, continuation, breakpoints and source/code display.

### Adopt in layers

1. Keep the current small numeric `wsm_fail` ABI for boot evidence.
2. Add a structured failure record later:

   ```text
   condition-kind
   operation
   offending-values
   source-definition-id
   source-span
   available-restart-ids
   ```

3. Initially support only deterministic restarts such as `abort-task`,
   `use-value`, and `retry-definition`.
4. A restart is an explicit continuation capability, not an arbitrary jump to
   a stale stack address.

This fits the project’s epistemic discipline: an error should carry why the
runtime believes it failed and what transitions are actually permitted.

**Priority:** high design seam; implementation after stack-frame metadata.  
**Do not do now:** pretend contract-3.0 `ErrorKind` already implies resumable
conditions.

## 3. A self-revealing system and live object inspector

### Historical mechanism

Genera described itself as “self-revealing”: status, source, callers, object
slots, processes and memory regions were inspectable symbolically. The
Inspector showed named slots rather than raw addresses. Practitioners remember
screen output as live presentations connected to the underlying objects.

### Adopt

Before a graphical inspector, define a serial/IPC inspection protocol:

```text
(inspect value-id)
(describe-definition definition-id)
(backtrace task-id)
(heap-summary)
(disassemble definition-id)
```

Responses must contain stable IDs, type tags and bounded fields. Raw pointers
may be diagnostic fields but never durable identities. The same protocol can
serve serial QEMU, the semantic oracle, LSP and a later Tauri presentation UI.

This is the strongest bridge to `my-idea`: the GUI should present runtime
objects returned by one inspection protocol, not reimplement runtime
semantics.

**Priority:** high after M4; text/serial first, Tauri later.

## 4. Presentation-based UI: output retains meaning

### Historical mechanism

Dynamic Windows/CLIM presentations associated displayed text or graphics with
typed objects and applicable commands. Forum accounts describe directory
entries and other output as directly inspectable/actionable objects rather
than dead terminal text.

### Adopt as a protocol, not a window system

Represent observable output as:

```text
presentation-id
kind
canonical-text
object-id
allowed-actions
provenance
```

The serial renderer may print only `canonical-text`; Tauri can make the same
record interactive. This reuses the ecosystem’s claim/evidence/provenance
work and prevents GUI-specific semantics.

**Priority:** medium.  
**Do not do now:** build a custom compositor or port CLIM before a stable
inspection record exists.

## 5. World images and restartable state

### Historical mechanism

Genera’s “world” contained the initialized software environment and its Lisp
objects. Current discussion still identifies saving the state of running
programs as a defining attraction. Mezzano similarly builds and boots system
images.

### What not to confuse

- Current `core.my.fasl` is a source-hash-verified parser-output cache, not a
  live heap image.
- `world.my` is immutable knowledge/history state, not an OS memory dump.
- A RAM dump with host pointers is not a reproducible image.

### Adopt

Design a future logical image as relocatable sections:

```text
header + contract SHAs
interned symbols
immutable values
definitions/code metadata
mutable heap graph
roots
capability rebind requests
content digest
```

External capabilities (disk, clock, network, GPU, devices) must be rebound on
restore and must never be serialized as trusted pointers. Keep source/FASL and
an event journal sufficient to reconstruct or audit the image.

**Priority:** medium/late, but record the identity rules early.

## 6. Stack groups and suspended computations

### Historical mechanism

The MIT Lisp Machine manual describes stack groups as Lisp objects containing
the control stack, environment bindings and resumption state, used for
coroutines, generators, scheduling and error handling.

### Adopt narrowly

Do not copy machine stacks. First create explicit scheduler tasks whose state
is described by managed frames:

```text
task-id
definition-id + instruction offset
value stack
environment/roots
state: runnable | waiting | condition | stopped
```

This can later support cooperative agents, debugger suspension and resumable
conditions. Native-stack capture should remain out of scope until the compiler
owns complete frame maps.

**Priority:** medium/late.  
**Risk:** a continuation holding raw stack/register addresses cannot survive
image relocation or code replacement.

## 7. Tagged values and hardware assistance

### Historical mechanism

Historical Lisp machines attached type information to words and used hardware
checks for types, bounds and memory safety. Architecture discussions also note
that modern stock CPUs can implement tagging efficiently, so special hardware
is not automatically the right first move.

### Our position

`wsm-os-target` already defines a 64-bit, low-three-bit tagged ABI. That is the
correct x86_64 starting point. Keep:

- one target contract as numeric authority;
- runtime range/ownership checks in addition to tag checks;
- deterministic symbol IDs;
- separate FPGA representation contracts;
- profiling evidence before AVX2/BMI2 or custom instructions.

Later, `fpga-lisp` can test which checks or primitives deserve hardware. The
x86 path should not imitate a historical microcoded CPU for aesthetic reasons.

**Priority:** already adopted at M0/M1.

## 8. Garbage collection and recoverable machine faults

### Evidence

Genera used an ephemeral collector; Mezzano reports generational collection,
weak objects, improved allocation visibility, unboxed slots and recoverable
stack-overflow/memory-fault handling. Practitioners also remember long GC
pauses as a real weakness of older machines.

### Adopt later, with metrics

The bounded bump heap remains correct for v0.1 because it makes exhaustion
deterministic. The next collector should be chosen only after traces show
allocation lifetime and root behavior. Reuse the existing `my-lisp` GC design
work instead of inventing another collector in `wsm-os`.

Required evidence before a generational collector:

- exact root maps for compiled frames;
- independent reachability oracle;
- stress mode and metamorphic “GC changes no observable semantics” tests;
- pause time, allocation rate and retained-size measurements;
- write-barrier contract if generations are introduced.

**Priority:** deferred; do not block first boot.

## 9. History as a first-class debugging primitive

### Historical mechanism

Genera maintained histories for commands, output, processes and windows. This
made investigation part of the environment rather than an afterthought.

### Adopt

Add bounded, typed event rings—not unrestricted logging—to the future runtime:

```text
sequence
event-kind
task/definition-id
logical timestamp
small payload
```

For deterministic tests, use logical counters rather than wall-clock time.
Expose the ring through the inspector and include it in failure evidence. The
existing swarm append-only journal demonstrates the value of replayable state,
but OS execution events require a separate bounded schema.

**Priority:** high for debugging, after serial output.

## 10. Files and versions

Forum discussion and manuals show that Lisp machines still used hierarchical
files and directories; versioned files were useful, but there is no evidence
that replacing the file abstraction itself was their central advantage.

For `wsm-os`:

- keep source and artifacts content-addressed and Git-backed on the host;
- use embedded read-only image sections first;
- add FAT only when physical boot requires it;
- do not invent a novel filesystem before the object/image model exists.

**Priority:** low.

## What the forums warn us not to do

1. **“Written in Lisp” does not remove modern hardware complexity.** USB,
   GPUs, networks and heterogeneous devices remain difficult.
2. **One address space is not automatically safe.** Modern isolation or
   capability boundaries still matter; tagged values alone do not authorize
   device access.
3. **Nostalgia is not a product requirement.** Open Genera is valuable for
   study, but practitioners caution that its old environment is not by itself
   practical for modern daily work.
4. **Special hardware is not automatically faster.** Caches, stock x86_64 and
   good compiler metadata may beat recreating historical microcode.
5. **A full Lisp OS is a long-lived ecosystem.** Mezzano’s thousands of
   commits and continuing hardware work are evidence against promising a
   complete OS from the first boot witness.

## Recommended roadmap impact

### Add to early architecture, without expanding v0.1

1. CML definition IDs and source maps.
2. Runtime object IDs distinct from raw addresses.
3. Structured condition records while retaining the small boot error ABI.
4. A versioned serial inspector protocol.
5. A bounded logical event ring.

### Prototype after first QEMU oracle parity

6. Definition-level replacement with active-frame safety rules.
7. Presentation records consumed by Tauri.
8. Relocatable logical image format with capability rebinding.
9. Managed task frames as the path toward stack groups/restarts.

### Keep deferred

10. Generational GC, GUI compositor, filesystem, networking, SMP, custom
    microcode and physical-device drivers.

## Sources

Primary and project sources:

- [Symbolics Genera Concepts](https://www.chai.uni-hamburg.de/~moeller/symbolics-info/genera/genera.html)
- [Symbolics Common Lisp Language Concepts](https://bitsavers.org/pdf/symbolics/software/genera_8/Symbolics_Common_Lisp_Language_Concepts.pdf)
- [Symbolics Program Development Utilities](https://bitsavers.org/pdf/symbolics/software/genera_8/Program_Development_Utilities.pdf)
- [Preliminary Lisp Machine Manual — stack groups](https://www.bitsavers.org/pdf/mit/cadr/Weinreb_Moon-Lisp_Machine_Manual_Jan_1979.pdf)
- [Mezzano repository and current feature record](https://github.com/froggey/Mezzano)

Practitioner discussions (anecdotal evidence, used as leads):

- [Running Open Genera 2.0 on Linux — Hacker News](https://news.ycombinator.com/item?id=39040697)
- [Genera and Interlisp-D differences — Hacker News](https://news.ycombinator.com/item?id=36713595)
- [Lisp Machine user experience — Reddit](https://www.reddit.com/r/lisp/comments/n94vl9/)
- [Why we need Lisp machines — Reddit](https://www.reddit.com/r/lisp/comments/tml3mb/)
- [Architecture of Lisp Machines discussion — Hacker News](https://news.ycombinator.com/item?id=27715043)
- [Modern Lisp OS discussion — Reddit](https://www.reddit.com/r/lisp/comments/1luw79t/)
