# Banyan OS Architecture Hypothesis

**Date:** 2026-09-16  
**Status:** research hypothesis / non-normative  
**Repository:** `juv4uk/wsm-os-lisp`

> This note records an architectural intuition for research. It is **not** an ADR, not a replacement for ADR-004, and not authority to redesign the current kernel before evidence exists.

## Origin of the idea

A banyan does not grow only as one trunk from the ground upward. Branches extend outward; aerial roots descend from those branches, reach the ground, and can become supporting trunks while remaining part of one organism.

The OS analogy is:

```text
                 primary trunk
                      |
          +-----------+-----------+
          |           |           |
       branch       branch       branch
          |           |           |
          v           v           v
       root        root        root
          |           |           |
       device      memory      device
```

A service begins as a logical branch of the system. If evidence shows that it needs stronger locality, lower latency, or direct ownership of a bounded physical resource, it may be allowed to grow a controlled "root" downward toward that resource.

The branch remains part of the same operating system; gaining a root must not mean gaining unrestricted machine authority.

## Core hypothesis

Instead of defining privilege mainly by one global vertical boundary such as `kernel space` versus `user space`, explore a topology where authority is described by **which bounded roots/capabilities a branch owns**.

```text
branch / service
      |
      +-- ordinary communication with the rest of the system
      |
      +-- bounded root capability
              |
              v
       concrete resource
       (MMIO / IRQ / DMA / CPU / memory / device)
```

A possible dynamic lifecycle:

```text
new service
   |
ordinary branch
   |
measurement shows a concrete need
   |
receives a narrowly-scoped capability
   |
grows a root toward one resource
   |
local autonomy / lower crossing cost
```

The inverse operation should also be considered: revoke or detach the root and return the branch to mediated service without changing its higher-level meaning.

## Why this may fit WSM OS Lisp

The current project already prefers a boundary of the form:

```text
Lisp policy
    |
bounded capability
    |
minimal physical mechanism
    |
hardware
```

The banyan hypothesis asks whether that same boundary can become a **system topology**, not only a driver API.

Example:

```text
Lisp graphics policy
        |
        +---- normal system communication
        |
        +---- GPU root capability
                    |
              bounded MMIO / IRQ / DMA
                    |
                   GPU
```

The key direction remains unchanged:

- Lisp/system policy may decide **what** a service does;
- the capability describes **which physical resource and operations** are permitted;
- minimal machine mechanism performs the irreducible access;
- raw physical authority must not leak upward merely because a branch is "rooted".

## Relationship to microkernel and hybrid-kernel thinking

This hypothesis does **not** claim that a banyan topology is already a new kernel class.

A useful research path is:

```text
small trusted nucleus
        |
services outside the nucleus
        |
explicit communication + isolation
        |
measured need appears
        |
selected service gains a bounded direct root
        |
result may become selectively hybrid
```

So the microkernel-like state can be treated as a clean baseline. Hybridization is then earned by evidence rather than assumed in advance.

## What must not be assumed

The metaphor is useful only if it survives engineering pressure. In particular, do **not** assume that:

- the runtime topology must literally be a tree;
- one branch has only one root;
- direct device access is automatically faster overall;
- fewer kernel crossings automatically means better latency under contention;
- dynamic rooting is safe without IOMMU, IRQ ownership, DMA isolation and accounting;
- the model is novel merely because the metaphor is novel;
- a capability name is enough to prove isolation;
- every performance-sensitive service should become rooted;
- rooted services belong in one monolithic privileged address space.

The actual structure may turn out to be a DAG or another graph while retaining the useful banyan property: **logical branches can acquire and release bounded physical roots**.

## Research questions

1. **Minimal trunk:** what is the smallest trusted mechanism that must remain globally central?
2. **Root grant:** who may create a root, and what evidence/authority permits it?
3. **Root representation:** is a root best represented as an opaque capability, endpoint, address-space grant, page mapping, device queue, or composition of these?
4. **Revocation:** can a root be revoked deterministically without rebooting or corrupting the branch?
5. **Fault containment:** what happens if a rooted service crashes while owning IRQ/MMIO/DMA state?
6. **DMA isolation:** what hardware support is required before a device root can safely perform DMA?
7. **IRQ ownership:** can interrupts be routed to a rooted branch without creating a new global authority leak?
8. **Scheduling/accounting:** how are CPU time, memory, queue depth and device bandwidth accounted across rooted branches?
9. **Communication:** does a rooted branch still use ordinary IPC/capability calls for everything outside its root?
10. **Promotion/demotion:** can the same service run mediated, then rooted, then mediated again with unchanged high-level contract?
11. **Performance:** which crossing costs actually dominate on the target i5-6400, and which disappear only on paper?
12. **Topology:** tree, DAG, forest, or dynamic graph — which model matches real ownership and sharing?
13. **Security:** can one compromised rooted branch affect only its granted roots and explicit communication peers?
14. **Composability:** can a rooted branch become a supporting trunk for child services without minting authority it does not own?
15. **Existing work:** which parts are already known under microkernels, capability systems, exokernels, user-mode drivers, multikernels, library OSes or hardware partitioning?

## Falsification criteria

The hypothesis should be weakened or rejected if experiments show that one or more of these are fundamental rather than implementation accidents:

- safe root grant/revocation requires a central mechanism so large that the topology collapses back into a conventional monolith;
- direct roots provide no useful latency/throughput benefit for realistic WSM workloads;
- required isolation costs exceed the crossings they remove;
- device state cannot be transferred/recovered cleanly enough for promotion/demotion;
- the model cannot express shared devices/resources without uncontrolled authority aliasing;
- the concept reduces exactly to an existing architecture with no useful new engineering distinction.

## First research slice — no production redesign

The first experiment should be intentionally small and reversible.

Choose one already-provisioned simple capability path (prefer the existing PCI/BAR/MMIO work) and compare two forms of the **same Lisp policy contract**:

```text
A. mediated path
Lisp policy -> service/capability boundary -> mechanism -> device

B. rooted path
same Lisp policy -> narrower direct resource capability -> mechanism -> device
```

Measure at least:

- number of authority crossings;
- latency distribution, not only average latency;
- code/TCB growth;
- failure containment;
- revocation behavior;
- whether high-level Lisp policy remains identical;
- whether raw physical addresses or device-global authority leak upward.

The first goal is **not** to prove the banyan architecture. It is to discover whether one branch can safely acquire and release one bounded root while preserving its higher-level contract.

## Research principle

> Start from a small trunk. Let a branch grow a root only when a concrete experiment earns it.

Or, in the project's existing evidence discipline:

```text
architectural intuition
        |
small falsifiable claim
        |
RED witness / baseline
        |
bounded experiment
        |
measurement + adversarial failure tests
        |
keep / weaken / reject the idea
```
