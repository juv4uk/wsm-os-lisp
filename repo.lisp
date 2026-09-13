; repo.my — Swarm Contract v0.1 scope declaration for wsm-os-lisp.
; Renamed 2026-09-02 from wsm-os: the owner started a new, independent
; clean-slate physical-platform lab (`juv4uk/wsm-os`) for `juv4uk/wsm`.
; This repository remains the my-lisp-lineage control target that owns the
; freestanding x86_64 ABI/runtime/boot image and its execution evidence.

(repository
  (id wsm-os-lisp)
  (role my-lisp-bare-metal-control-target)
  (exports x86_64-target-contract boot-runtime boot-image qemu-execution-evidence physical-parity-ledger)
  (imports language-semantics compiler-middle-end cml-ir)
  (capabilities x86_64 assembly rust compiler boot qemu testing proof)
  (authorities target-abi boot-runtime boot-image qemu-execution-evidence physical-parity-ledger)
  (non-authorities language-semantics cml-ir fpga-isa cuda-runtime physical-platform-research))