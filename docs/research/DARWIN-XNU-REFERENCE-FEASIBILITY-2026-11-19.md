# Darwin/XNU as a reference for wsm-os-lisp

**Date:** 2026-11-19  
**Status:** preliminary sourced feasibility note; research only, not an architecture decision.  
**Related:** [#41 hybrid-kernel/Banyan research](https://github.com/juv4uk/wsm-os-lisp/issues/41), [#12 OS roadmap](https://github.com/juv4uk/wsm-os-lisp/issues/12), [ADR-004](../ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md).

## Executive finding

Darwin/XNU is a useful **hybrid-kernel case study**, but current evidence does not justify replacing the existing wsm-os-lisp substrate with XNU or importing the XNU tree wholesale.

The best near-term use is to study and selectively borrow architectural mechanisms—especially message-oriented IPC, memory-object/VM boundaries, service decomposition and driver isolation—while preserving the current Lisp-owned system policy and minimal x86-64 assembly mechanism. Any source-code reuse is a separate decision requiring a per-component dependency, platform and license audit.

## What XNU actually is

Apple's current open-source XNU README describes XNU as a hybrid kernel combining:
- Mach kernel subsystems;
- components from FreeBSD;
- IOKit, a C++ driver API/framework.

The source tree makes those boundaries visible: Mach-oriented code is under `osfmk`, BSD subsystems under `bsd`, IOKit-related code under `libkern`, startup/bootstrap code under `libsa`, and platform-specific mechanisms under `pexpert`. XNU supports x86_64 and ARM64 in the published source tree.

This is not equivalent to taking a clean, standalone Mach microkernel and placing arbitrary user-space servers around it. XNU is an integrated kernel with several substantial subsystems and their interactions.

Sources:
- [Apple OSS XNU README — architecture and source tree](https://github.com/apple-oss-distributions/xnu/blob/main/README.md)
- [Apple archived Kernel Architecture Overview](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/KernelProgramming/Architecture/Architecture.html)

## Mechanisms worth studying

| XNU/Mach area | Potential value to wsm-os-lisp | Boundary to preserve |
|---|---|---|
| Mach IPC ports/messages | A disciplined request/reply transport between Lisp services | Message transport is not SENS meaning; define exact SENS-owned message schemas and capability validation |
| Mach VM / memory objects | Explicit memory ownership, mapping and sharing mechanisms | VM is not garbage collection; physical/virtual address facts remain substrate-owned |
| Mach tasks/threads and scheduling | A reference for execution contexts and isolation | Scheduler policy remains WSM/Lisp-owned; do not copy Mach object identities into SENS domains |
| BSD subsystem | Reference for mature VFS/network/process services | Do not import POSIX compatibility as a project goal unless independently required |
| IOKit | Reference for driver matching, object lifetimes and device-service structure | Current ADR-004 keeps production mechanisms in minimal ASM and policy in Lisp; importing C++ IOKit changes that boundary |

Apple's archived guide describes Mach as providing processor/memory management, scheduling, memory protection, IPC/RPC, virtual memory and pagers, while BSD provides OS-personality services such as filesystems and networking. Treat this as an architectural overview, not a current API specification.

## Build and boot feasibility

The upstream XNU README documents an x86_64 development build using an SDK root (for example, `SDKROOT=macosx.internal`) and `ARCH_CONFIGS=X86_64`. It also states that testing requires a kernelcache that links the kernel and kexts into a bootable image. Its documented target-machine boot flow uses Apple's iBoot and kernelcache configuration mechanisms.

Consequences:
1. x86_64 source support is real; it is not proof of a generic PC/UEFI boot path.
2. A buildable XNU kernel is not by itself a complete bootable system: kernelcache, extensions/drivers, platform support and boot integration matter.
3. The existing wsm-os-lisp UEFI/QEMU boot path is a separate proven path. Replacing it would discard working evidence and create a new boot/platform integration project.
4. A minimal feasibility experiment must first prove a reproducible build and a safe QEMU boot route before any production integration is proposed.

Source: [XNU README — build, kernelcache and target boot instructions](https://github.com/apple-oss-distributions/xnu/blob/main/README.md).

## Licensing and source-reuse boundary

The XNU source repository includes the Apple Public Source License (APSL) 2.0. The license permits use and modification subject to conditions. For modified covered source, the license requires preservation of notices, prominent modification notices and dates, and—when modifications are externally deployed—availability of the source of those modifications under APSL terms. Executable-only external deployment also carries source-availability notice requirements.

This is not a blanket statement that every Darwin component has the same license. Before copying any code:
- inspect the exact file's license and notices;
- inspect third-party headers and embedded dependencies;
- preserve attribution and license text;
- determine whether external deployment triggers source publication duties;
- review patent and third-party rights separately.

Sources:
- [XNU APPLE_LICENSE](https://github.com/apple/darwin-xnu/blob/main/APPLE_LICENSE)
- [Open Source Initiative — APSL 2.0](https://opensource.org/license/APSL-2.0)

This note is a technical project assessment, not legal advice.

## Options against the current wsm-os-lisp baseline

### A. Keep the current Lisp + x86-64 ASM substrate (recommended baseline)

Continue the current UEFI/QEMU path. Lisp owns system policy, services and drivers; ASM owns irreducible boot/interrupt/port/MMIO/ABI mechanisms. Evolve service boundaries and resource capabilities using the evidence already established for PCI, MMIO, DMA, VirtIO and block I/O.

**Advantages:** preserves working boot and device evidence; smallest migration; SENS authority remains explicit; no imported kernel dependency.

**Risk:** isolation and IPC must be deliberately designed and proved rather than inherited from an existing kernel.

### B. Borrow selected Mach ideas, implement them natively

Prototype a bounded message/port model and explicit memory-object or mapping grants within the current substrate. Compare mediated service calls with narrowly rooted resource capabilities under the existing [Banyan experiment #41](https://github.com/juv4uk/wsm-os-lisp/issues/41).

**Advantages:** gains useful architectural ideas without adopting XNU's boot chain, BSD layer or IOKit runtime.

**Risk:** a new IPC/object model can expand the trusted computing base and become an accidental second semantic system unless its messages and capabilities remain mechanism-only.

### C. Reuse or port XNU source

Treat as a high-cost research option only. It requires a component-level dependency closure, compatible toolchain/SDK, bootloader/platform path, driver plan, license review and a proof that XNU mechanisms can coexist with—not replace—SENS authority and the Lisp system model.

**Advantages:** potential reuse of mature kernel subsystems.

**Risks:** substantial platform/build dependencies; possible mismatch with the existing UEFI path; C/C++ kernel and IOKit integration conflicts with the current Pure Lisp + ASM production architecture; APSL and third-party licensing obligations; large integration and maintenance cost.

## Preliminary recommendation

1. Do **not** replace the current kernel/runtime with XNU.
2. Do **not** add XNU source dependencies to production.
3. Use XNU/Mach as a comparative design reference.
4. First complete the existing useful-machine ladder (#76–#79) and the SENS Contract 12.0 target migration (#109).
5. Within #41, test whether a small Mach-inspired IPC/memory-grant mechanism improves the current Lisp service/capability model. Measure crossings, latency, TCB size, revocation and failure containment.
6. Only propose an ADR if the experiment beats the current mediated/rooted baseline and keeps SENS as the sole language-semantic authority.

## Open questions for the next research pass

- Which Mach IPC concepts can be reduced to a small, typed, capability-checked message protocol without importing Mach port semantics wholesale?
- Does the current target need separate tasks/address spaces before it needs a full Mach-like object model?
- What is the smallest memory-object abstraction that can support safe sharing and revocation?
- Can Lisp-owned device policy remain unchanged across mediated and directly rooted capability paths?
- What measurable result would justify the complexity of a hybrid boundary over the current minimal substrate?
