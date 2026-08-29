# wsm-os agent scope

Read `/home/agents/ecosystem/AGENTS.md`, the owner profile, resource policy,
[`docs/ADR-001-COMPILER-FIRST.md`](docs/ADR-001-COMPILER-FIRST.md) and
[`tasks.my`](tasks.my) before changing code.

- `my-lisp` owns language semantics.
- CML owns parsing, semantic admission, IR and assembly emission.
- `wsm-os` owns its target ABI, runtime, boot image and platform evidence.
- Claim/complete through the swarm and broadcast pushed SHA on completion.
- Never write, partition or format a physical disk as part of testing.
- QEMU/host/physical evidence are distinct states.
