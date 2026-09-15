# Banyan OS research log

Status: **ACTIVE RESEARCH — KEEP OPEN**
Issue: #41

This file is a living research log. It is not an ADR and does not replace the current WSM OS Lisp roadmap or ADR-004.

## Research rule

The Banyan metaphor is useful only if it produces falsifiable architectural distinctions. We therefore compare it against existing OS mechanisms and actively try to reduce it to known patterns.

## Iteration 1 — nearest known relatives

### seL4 / capability microkernels

Relevant mechanism:
- resources are controlled through unforgeable capabilities;
- most device drivers run in user mode;
- device memory can be mapped to a driver and IRQs can be delivered through kernel-mediated mechanisms;
- resource authority can be partitioned and delegated.

Banyan correspondence:
- a **root** looks very much like a bounded capability to a physical or kernel-managed resource;
- a **branch** resembles a user-space component that owns only the capabilities granted to it.

Difference still worth testing:
- Banyan proposes dynamic, reversible *rooting* as an architectural operation while preserving one high-level Lisp policy contract.

References:
- https://docs.sel4.systems/Tutorials/capabilities.html
- https://sel4.systems/About/FAQ.html

### Exokernel

Relevant mechanism:
- a small kernel protects and multiplexes physical resources;
- management policy moves to application/library level;
- secure bindings separate authorization from later resource use.

Banyan correspondence:
- the trunk could protect and grant resources while branches manage them;
- a root can be interpreted as a secure binding from a branch to a physical resource.

Difference still worth testing:
- Banyan is not only application-level resource management; the hypothesis is that roots can appear/disappear dynamically and become part of a changing system topology.

Reference:
- https://pdos.csail.mit.edu/6.828/2008/readings/engler95exokernel.pdf

### Arrakis

This is currently the closest precedent found.

Relevant mechanism:
- kernel becomes primarily a control plane;
- applications can access virtualized I/O devices directly on the data plane;
- hardware virtualization enforces allowed paths so ordinary I/O can bypass repeated kernel mediation.

Banyan correspondence:
- **trunk** ~= control plane;
- **root** ~= authorized direct data path to a hardware resource;
- **branch** ~= service/application that owns the path.

Research consequence:
- Banyan OS should not claim novelty merely for “direct bounded hardware access”. Arrakis already demonstrates that principle.
- The potentially distinct question is **dynamic/reversible rooting plus delegation while preserving the same Lisp policy contract**.

References:
- https://www.usenix.org/conference/osdi14/technical-sessions/presentation/peter
- https://arrakis.cs.washington.edu/wp-content/uploads/2013/04/arrakis-tr.pdf

### Dune

Relevant mechanism:
- processes gain safe direct access to normally privileged CPU mechanisms using hardware virtualization while preserving the host process abstraction.

Banyan correspondence:
- a branch may gain a narrow “root” not only to a device but to CPU facilities such as page tables or protection mechanisms.

Reference:
- https://mast.stanford.edu/pubs/dune/

### Barrelfish / multikernel

Relevant mechanism:
- treats a multicore machine more like a distributed system;
- OS state and coordination are decentralized and communicated explicitly.

Banyan correspondence:
- warns us that one central trunk may be the wrong topology on many-core hardware;
- Banyan may need multiple trunks or replicated control state rather than one root hierarchy.

Reference:
- https://www.microsoft.com/en-us/research/project/barrelfish/publications/

## First refinement of the hypothesis

The useful hypothesis is no longer:

> “an OS can give services direct access to hardware.”

That is already well explored.

The stronger and falsifiable version is:

> A service may keep the **same Lisp-side policy contract** while the system dynamically changes its placement from a mediated path to a narrowly rooted path, and later revokes that root, without leaking unrestricted hardware authority or requiring semantic changes in the service.

Sketch:

```text
                 same Lisp policy
                       |
              +--------+--------+
              |                 |
        mediated mode       rooted mode
              |                 |
          service path      bounded root cap
              |                 |
              +--------+--------+
                       |
                    hardware
```

If the high-level policy must be rewritten when the path changes, the hypothesis weakens substantially.

## Topology finding: probably not a tree

A literal tree is likely too weak because:
- one device/resource may be shared by multiple services;
- one branch may depend on several independent resources;
- delegated authority creates cross-links;
- interrupt, DMA and memory authority can have different ownership relations.

Provisional model: **dynamic capability DAG** with a banyan-like growth metaphor.

The metaphor remains useful because a branch can acquire new downward resource edges and later become a support point for child services, but the formal graph should not be forced to remain a tree.

## Candidate vocabulary

- **trunk** — smallest globally trusted control/protection mechanism;
- **branch** — Lisp/system policy component with no implicit physical authority;
- **root capability** — explicit bounded authority connecting a branch to a concrete machine resource;
- **rooting** — grant/install a usable resource path;
- **unrooting** — revoke/remove that path and return to a mediated or unavailable state;
- **sub-root** — delegated subset of authority; it must never exceed the parent capability;
- **root path** — actual data/mechanism route used after authorization.

These are research terms, not yet canonical architecture terms.

## First experiment target

Reuse the existing PCI/BAR/MMIO capability work from #32/#40.

Two modes must expose the same Lisp-side policy contract:

```text
A. mediated
Lisp policy -> service boundary -> bounded physical mechanism -> device

B. rooted
same Lisp policy -> root capability -> bounded physical mechanism -> device
```

Measure:
- context/authority crossings;
- latency distribution;
- code added to trusted computing base;
- revocation latency and determinism;
- crash/fault containment;
- whether addresses/raw device authority leak into Lisp policy;
- whether the same policy source can run unchanged in both modes.

## Required attacks

Before accepting any positive result, test:
- stale root after revocation;
- branch crash while rooted;
- out-of-bounds MMIO;
- DMA outside granted memory;
- IRQ arriving after revocation;
- delegation beyond owned authority;
- shared device between two branches;
- no measurable performance benefit despite higher complexity.

## Current epistemic state

`partial`

Reason: the metaphor maps cleanly onto known capability/control-plane ideas, especially Arrakis and exokernel work. Its value is not yet established as a new architecture class. The research should now focus on whether **dynamic reversible rooting + unchanged Lisp policy + bounded delegation** creates a useful and measurable design distinction.
