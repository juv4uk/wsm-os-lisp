# wsm-os-lisp

> [!IMPORTANT]
> **ROLE IN ECOSYSTEM (MY-LISP EXECUTION QUARTET):**  
> `wsm-os-lisp` is the **bare-metal control execution target** for the `my-lisp` lineage (`my-lisp` oracle → `cml` lowering → `wsm-os-lisp` freestanding UEFI target).  
> **DO NOT MODERNIZE INTO `wsm-os`:** `wsm-os` (`juv4uk/wsm-os`) is a separate, independent physical-platform research laboratory for `juv4uk/wsm`. `wsm-os-lisp` owns its existing Lisp-machine target ABI/runtime, UEFI image, QEMU execution evidence, and the parity ledger for that pinned artifact. See `ecosystem/decisions/2026-09-05-my-lisp-execution-quartet-and-wsm-os-lisp-role.md`.

Research and executable prototypes for a WSM-native Lisp machine control target.

The project starts with a narrow claim: boot a minimal target, establish a
typed host boundary, and execute one verified WSM expression. It does not yet
claim to be an operating system, a `no_std` port of all of my-lisp, or a
bare-metal CUDA runtime.

## Goal

The graduation machine for this control target is the owner's own physical
machine (Gigabyte H170-Gaming 3, Intel Core i5-6400, Skylake-class UEFI x86_64 --
see [docs/OWNER-HARDWARE-PROFILE.md](docs/OWNER-HARDWARE-PROFILE.md) for
the full, privacy-scrubbed profile). QEMU stays the proof gate before any
physical run, per [docs/QEMU-LOCAL-RUN.md](docs/QEMU-LOCAL-RUN.md); a
physical boot is a distinct, not-yet-claimed evidence class for the same
pinned artifact. Hardware/platform research and evolution belong to the
separate `wsm-os` project, not to this repository.

That one machine is a graduation target, not the boundary of the driver
architecture. [ADR-003](docs/ADR-003-RUST-LISP-MECHANISM-POLICY.md)'s
capability model (bounded PCI/MMIO/DMA primitives, substrate mechanism
below, WSM-owned device policy above) is deliberately not specialized to
this one board or this one CPU generation: a driver written against that
capability boundary should have no reason to assume Skylake, H170, or any
detail specific to the owner's machine. A different physical platform may
require different capability provisioning, but platform-research changes are
owned by the separate `wsm-os` lab rather than folded back into this control
target as new WSM semantics.

For the longer-range architectural picture beyond this bounded goal (a
full WSM-native operating system, WSM on bare metal via a bootstrap-to-
self-hosting path, GPU compute as a separate frontier), see
[docs/VISION.md](docs/VISION.md) -- explicitly aspiration, not evidence,
and kept separate from this section on purpose.

## Authority boundaries

- `my-lisp` owns WSM language semantics and remains the reference oracle.
- `cml` owns portable lowering, semantic admission, and target code generation.
- `wsm-os-lisp` owns this lineage's x86_64 target ABI/runtime, boot image,
  bounded QEMU execution evidence, and the parity ledger for a pinned artifact.
- `wsm-os` owns separate physical-platform research for `juv4uk/wsm`; it does
  **not** own or redefine `wsm-os-lisp`'s target ABI, boot image, or WSM meaning.
- `fpga-lisp` owns the bounded FPGA Lisp-machine implementation.

A later physical run of an already-pinned `wsm-os-lisp` artifact may promote
its evidence from `QEMU-BOOT-PARITY` to `PHYSICAL-HARDWARE-PARITY`. That is an
evidence graduation, not transfer of platform-research authority back into
this repository.

## First milestone

```text
QEMU x86_64 boot
  -> serial output
  -> bounded allocator
  -> minimal WSM execution/runtime boundary
  -> evaluate a frozen expression
  -> compare result with canonical my-lisp
```

See [docs/BOOTSTRAP-PLAN.md](docs/BOOTSTRAP-PLAN.md).

The inspected, commit-pinned reuse decisions are recorded in
[docs/ECOSYSTEM-REUSE-MAP.md](docs/ECOSYSTEM-REUSE-MAP.md).

The executable milestone sequence and evidence gates are in
[docs/IMPLEMENTATION-PLAN.md](docs/IMPLEMENTATION-PLAN.md).

The privacy-scrubbed physical and WSL target inventory is in
[docs/OWNER-HARDWARE-PROFILE.md](docs/OWNER-HARDWARE-PROFILE.md).

The compiler-first ownership decision is recorded in
[docs/ADR-001-COMPILER-FIRST.md](docs/ADR-001-COMPILER-FIRST.md).

Executable swarm work is tracked in [`tasks.my`](tasks.my).

The first machine-readable ABI and its generated WSM projection are documented
in [`docs/TARGET-ABI.md`](docs/TARGET-ABI.md).

The versioned identity and reproducibility boundary for compiled definitions
is documented in [`docs/DEFINITION-CAPSULE.md`](docs/DEFINITION-CAPSULE.md).

## Current evidence

The frozen `(cons (quote A) (quote B))` fixture now passes the complete first
execution chain: pinned my-lisp oracle, CML-generated object, hosted runtime,
freestanding UEFI image, and bounded QEMU execution all agree on `(A . B)`.
This is `QEMU-BOOT-PARITY`, not a physical-hardware claim.

---

## Про wsm-os-lisp / About wsm-os-lisp (Ukrainian)

> [!IMPORTANT]
> **РОЛЬ В ЕКОСИСТЕМІ (КВАРТЕТ ВИКОНАННЯ MY-LISP):**  
> `wsm-os-lisp` є **контрольним bare-metal таргетом виконання** для лінії `my-lisp` (`my-lisp` оракул → `cml` lowering → `wsm-os-lisp` автономний UEFI таргет).  
> **НЕ МОДЕРНІЗУВАТИ В `wsm-os`:** `wsm-os` (`juv4uk/wsm-os`) є окремою незалежною лабораторією дослідження фізичної платформи для `juv4uk/wsm`. `wsm-os-lisp` володіє своїм наявним target ABI/runtime, UEFI-образом, QEMU-доказами виконання та ledger-ом parity для зафіксованого артефакту. Див. `ecosystem/decisions/2026-09-05-my-lisp-execution-quartet-and-wsm-os-lisp-role.md`.

Дослідження та виконувані прототипи контрольного таргета WSM-нативної
Lisp-машини.

Проєкт починається з вузької мети: завантажити мінімальний таргет, встановити
типізовану межу хоста та виконати один верифікований WSM-вираз. Наразі він не
претендує на статус повноцінної операційної системи, порту всього my-lisp на
базі `no_std`, чи bare-metal середовища для CUDA.

## Ціль

Машина для фінального graduation цього контрольного таргета — власна фізична
машина власника (Gigabyte H170-Gaming 3, Intel Core i5-6400, Skylake-класу
UEFI x86_64 — повний, очищений від приватних даних профіль у
[docs/OWNER-HARDWARE-PROFILE.md](docs/OWNER-HARDWARE-PROFILE.md)). QEMU
лишається обов'язковим воротом доказу перед будь-яким фізичним запуском,
per [docs/QEMU-LOCAL-RUN.md](docs/QEMU-LOCAL-RUN.md); фізичний бут — окремий,
ще не заявлений клас доказу для того самого зафіксованого артефакту.
Дослідження й розвиток фізичної платформи належать окремому проєкту `wsm-os`,
а не цьому репозиторію.

Ця одна машина — graduation-ціль, а не межа драйверної архітектури.
Capability-модель [ADR-003](docs/ADR-003-RUST-LISP-MECHANISM-POLICY.md)
(обмежені PCI/MMIO/DMA примітиви, substrate-механізм внизу,
WSM-політика пристроїв нагорі) свідомо не спеціалізована під цю плату чи
це покоління CPU: драйвер, написаний проти цієї capability-межі, не
повинен мати причин припускати Skylake, H170 чи будь-яку деталь, властиву
саме машині власника. Інша фізична платформа може вимагати іншого
capability provisioning, але platform-research зміни мають жити в окремій
лабораторії `wsm-os`, а не повертатися сюди як нова семантика WSM.

Ширшу архітектурну картину поза цією обмеженою ціллю (повноцінна
WSM-native операційна система, WSM на bare metal через шлях
bootstrap-до-self-hosting, GPU compute як окремий фронтир) дивись
[docs/VISION.md](docs/VISION.md) — явно прагнення, не доказ, і навмисно
тримається окремо від цього розділу.

## Межі відповідальності

- `my-lisp` володіє семантикою мови WSM і залишається еталонним оракулом.
- `cml` відповідає за переносиме lowering, семантичний допуск і генерацію
  target-коду.
- `wsm-os-lisp` володіє x86_64 target ABI/runtime цієї лінії, boot-образом,
  bounded QEMU-доказами виконання та parity-ledger зафіксованого артефакту.
- `wsm-os` володіє окремим дослідженням фізичної платформи для `juv4uk/wsm`;
  він **не** володіє і не перевизначає target ABI, boot-образ чи семантику WSM
  цього репозиторію.
- `fpga-lisp` володіє реалізацією Lisp-машини, обмеженої можливостями FPGA.

Пізніший фізичний запуск уже зафіксованого артефакту `wsm-os-lisp` може
підвищити клас доказу з `QEMU-BOOT-PARITY` до `PHYSICAL-HARDWARE-PARITY`.
Це graduation доказу, а не повернення authority над дослідженням платформи
цьому репозиторію.

## Перший етап

```text
QEMU x86_64 boot
  -> serial вивід
  -> bounded (обмежений) алокатор
  -> мінімальна межа виконання/середовища виконання WSM
  -> обчислення замороженого виразу
  -> порівняння результату з канонічним my-lisp
```

Дивіться [docs/BOOTSTRAP-PLAN.md](docs/BOOTSTRAP-PLAN.md).

Перевірені та зафіксовані (через хеші комітів) рішення щодо повторного
використання коду задокументовані у [docs/ECOSYSTEM-REUSE-MAP.md](docs/ECOSYSTEM-REUSE-MAP.md).

Послідовність виконання етапів та їхні критерії доказів знаходяться у
[docs/IMPLEMENTATION-PLAN.md](docs/IMPLEMENTATION-PLAN.md).

Очищений від приватної інформації інвентар фізичного обладнання та WSL
знаходиться у [docs/OWNER-HARDWARE-PROFILE.md](docs/OWNER-HARDWARE-PROFILE.md).

Рішення розпочати з побудови компілятора зафіксовано у
[docs/ADR-001-COMPILER-FIRST.md](docs/ADR-001-COMPILER-FIRST.md).

Робота рою агентів над виконуваними завданнями відстежується у [`tasks.my`](tasks.my).

Перший машинно-зчитуваний ABI та його згенерована WSM-проекція задокументовані
у [`docs/TARGET-ABI.md`](docs/TARGET-ABI.md).

Версіонована ідентичність та межа відтворюваності для скомпільованих
визначень задокументована у [`docs/DEFINITION-CAPSULE.md`](docs/DEFINITION-CAPSULE.md).

## Поточні докази

Заморожений тестовий вираз `(cons (quote A) (quote B))` тепер проходить повний
перший ланцюжок виконання: зафіксований оракул my-lisp, CML-згенерований
об'єкт, hosted-середовище виконання, автономний (freestanding) UEFI-образ
та обмежене виконання в QEMU погоджуються щодо результату `(A . B)`.
Це `QEMU-BOOT-PARITY`, а не твердження про роботу на фізичному обладнанні.

## Ліцензія

Цей твір поширюється під [ВОЛЬНІСТЮ](LICENSE) — простим словом про свободу творити, пам'ятаючи про волю іншого.