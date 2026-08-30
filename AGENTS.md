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

---
# Зона відповідальності агента wsm-os (Ukrainian)

Прочитай `/home/agents/ecosystem/AGENTS.md`, профіль власника, resource
policy, [`docs/ADR-001-COMPILER-FIRST.md`](docs/ADR-001-COMPILER-FIRST.md) і
[`tasks.my`](tasks.my) перед будь-якою зміною коду.

- `my-lisp` володіє семантикою мови-джерела.
- CML володіє синтаксичним розбором, семантичним доступом, IR і асемблерною
  емісією.
- `wsm-os` володіє своїм цільовим ABI, рантаймом, boot-образом і доказами
  платформи.
- Claim/complete через swarm; після завершення транслюй SHA у шину.
- Ніколи не записуй, не розбивай і не форматуй фізичний диск у межах
  тестування.
- QEMU/host/фізичні докази — різні стани.
