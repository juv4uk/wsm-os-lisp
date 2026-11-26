# wsm-os-lisp

> [!IMPORTANT]
> **ROLE IN ECOSYSTEM:**  
> `wsm-os-lisp` is the **Lisp-owned OS/kernel/system line** and bare-metal execution target for the SENS-based Lisp Machine. It owns Lisp system policy, irreducible x86-64 assembly mechanisms, target ABI/runtime, UEFI image, reproducible QEMU evidence, and a separately gated physical-hardware graduation path.  
> **KEEP REPOSITORIES DISTINCT:** `wsm-os` (`juv4uk/wsm-os`) remains a separate physical-platform research laboratory for `juv4uk/wsm`; this repository does not absorb or redefine that project's scope. `wsm-os-lisp` continues its own OS/kernel roadmap under issue [#12](https://github.com/juv4uk/wsm-os-lisp/issues/12).

Research and executable prototypes for a WSM-native Lisp machine control target.
The architecture is strictly **Pure Lisp + x86-64 Assembly (Zero Rust, Zero C in production)** per [ADR-004](docs/ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md).

The project starts with a clear, verified baseline: boot on UEFI, establish a
minimal System V AMD64 assembly runtime (`src/runtime.s`), execute compiled WSM expressions,
and prove execution parity against canonical SENS-owned semantic witnesses in QEMU and on real hardware.


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
architecture. [ADR-004](docs/ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md)'s
pure Lisp + x86-64 assembly model (irreducible machine primitives in ASM
below, pure Lisp system semantics & device policy above, zero Rust in production)
is deliberately not specialized to this one board or this one CPU generation:
a driver written against that capability boundary should have no reason to
assume Skylake, H170, or any detail specific to the owner's machine. A
different physical platform may require different capability provisioning, but
platform-research changes are owned by the separate `wsm-os` lab rather than
folded back into this control target as new WSM semantics.

For the longer-range architectural picture beyond this bounded goal (a
full WSM-native operating system, WSM on bare metal via a bootstrap-to-
self-hosting path, GPU compute as a separate frontier), see
[docs/VISION.md](docs/VISION.md) -- explicitly aspiration, not evidence,
and kept separate from this section on purpose.

## Authority boundaries

- `sens` owns WSM/SENS language semantics and canonical semantic witnesses; this repository consumes that authority without duplicating it.
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
  -> compare result with the pinned upstream SENS witness
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

The trust-boundary decision is proposed (not accepted) in
[docs/ADR-005-TRUST-BOUNDARY-ARBITER-NOT-KERNELLESS.md](docs/ADR-005-TRUST-BOUNDARY-ARBITER-NOT-KERNELLESS.md);
its prior-art survey is
[docs/research/PRIOR-ART-NO-KERNEL-2026-11-26.md](docs/research/PRIOR-ART-NO-KERNEL-2026-11-26.md),
and the branch state it depends on is
[docs/BRANCH-INVENTORY-2026-11-26.md](docs/BRANCH-INVENTORY-2026-11-26.md).

The enforceable-policy registry that ADR-005 requires is
[`policy-enforcement.lisp`](policy-enforcement.lisp): a policy is citable only
with an enforcement point, a witness and a CI gate, and
`scripts/check-policy-enforcement.py` re-checks each record against the tree.

Executable swarm work is tracked in [`tasks.lisp`](tasks.lisp).

The first machine-readable ABI and its generated WSM projection are documented
in [`docs/TARGET-ABI.md`](docs/TARGET-ABI.md).

The versioned identity and reproducibility boundary for compiled definitions
is documented in [`docs/DEFINITION-CAPSULE.md`](docs/DEFINITION-CAPSULE.md).

## Current evidence

The frozen `(cons (quote A) (quote B))` fixture now passes the complete first
execution chain: pinned upstream semantic witness, CML-generated object, hosted runtime,
freestanding UEFI image, and bounded QEMU execution all agree on `(A . B)`.
This is `QEMU-BOOT-PARITY`, not a physical-hardware claim.

---

## Про wsm-os-lisp / About wsm-os-lisp (Ukrainian)

> [!IMPORTANT]
> **РОЛЬ В ЕКОСИСТЕМІ:**  
> `wsm-os-lisp` — це **лінія Lisp-власної ОС/ядра/системи** та bare-metal таргет виконання для Lisp-машини на основі SENS. Репозиторій володіє системною політикою Lisp, незвідними механізмами x86-64 Assembly, target ABI/runtime, UEFI-образом, відтворюваними доказами в QEMU та окремим воротом graduation для фізичного обладнання.  
> **РЕПОЗИТОРІЇ ЗАЛИШАЮТЬСЯ ОКРЕМИМИ:** `wsm-os` (`juv4uk/wsm-os`) залишається окремою лабораторією дослідження фізичної платформи для `juv4uk/wsm`; цей репозиторій не поглинає й не перевизначає її межі. Власний roadmap ОС/ядра `wsm-os-lisp` ведеться в issue [#12](https://github.com/juv4uk/wsm-os-lisp/issues/12).

Дослідження та виконувані прототипи контрольного таргета WSM-нативної Lisp-машини.
Архітектура є виключно **Чистий Lisp + x86-64 асемблер (нуль Rust, нуль C у production)** згідно з [ADR-004](docs/ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md).

Проєкт починається з чіткого верифікованого фундаменту: завантаження через UEFI,
встановлення мінімального асемблерного рантайму System V AMD64 (`src/runtime.s`), виконання
скомпільованих виразів WSM та доведення відповідності закріпленим семантичним свідкам SENS
у QEMU та на реальному залізі.


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
Модель чистого Lisp + x86-64 асемблера [ADR-004](docs/ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md)
(незвідні машинні примітиви в асемблері внизу, системна семантика та політика
драйверів у Lisp нагорі, нуль Rust у production) свідомо не спеціалізована
під цю плату чи це покоління CPU: драйвер, написаний проти цієї capability-межі,
не повинен мати причин припускати Skylake, H170 чи будь-яку деталь, властиву
саме машині власника. Інша фізична платформа може вимагати іншого
capability provisioning, але platform-research зміни мають жити в окремій
лабораторії `wsm-os`, а не повертатися сюди як нова семантика WSM.

Ширшу архітектурну картину поза цією обмеженою ціллю (повноцінна
WSM-native операційна система, WSM на bare metal через шлях
bootstrap-до-self-hosting, GPU compute як окремий фронтир) дивись
[docs/VISION.md](docs/VISION.md) — явно прагнення, не доказ, і навмисно
тримається окремо від цього розділу.

## Межі відповідальності

- `sens` володіє семантикою мови SENS/WSM та канонічними семантичними свідками; цей репозиторій споживає цю владу, не дублюючи її.
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
  -> порівняння результату із закріпленим свідком SENS
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

Рішення про межу довіри **запропоновано** (не прийнято) у
[docs/ADR-005-TRUST-BOUNDARY-ARBITER-NOT-KERNELLESS.md](docs/ADR-005-TRUST-BOUNDARY-ARBITER-NOT-KERNELLESS.md);
огляд попереднього доробку — у
[docs/research/PRIOR-ART-NO-KERNEL-2026-11-26.md](docs/research/PRIOR-ART-NO-KERNEL-2026-11-26.md),
а стан гілок, від якого він залежить, — у
[docs/BRANCH-INVENTORY-2026-11-26.md](docs/BRANCH-INVENTORY-2026-11-26.md).

Реєстр політик, якого вимагає ADR-005, — це
[`policy-enforcement.lisp`](policy-enforcement.lisp): політику можна цитувати лише
з точкою примусу, свідком і гейтом у CI, а `scripts/check-policy-enforcement.py`
повторно перевіряє кожен запис проти дерева.

Робота рою агентів над виконуваними завданнями відстежується у [`tasks.lisp`](tasks.lisp).

Перший машинно-зчитуваний ABI та його згенерована WSM-проекція задокументовані
у [`docs/TARGET-ABI.md`](docs/TARGET-ABI.md).

Версіонована ідентичність та межа відтворюваності для скомпільованих
визначень задокументована у [`docs/DEFINITION-CAPSULE.md`](docs/DEFINITION-CAPSULE.md).

## Поточні докази

Заморожений тестовий вираз `(cons (quote A) (quote B))` тепер проходить повний
перший ланцюжок виконання: зафіксований семантичний свідок SENS, CML-згенерований
об'єкт, hosted-середовище виконання, автономний (freestanding) UEFI-образ
та обмежене виконання в QEMU погоджуються щодо результату `(A . B)`.
Це `QEMU-BOOT-PARITY`, а не твердження про роботу на фізичному обладнанні.

## Ліцензія

Цей твір поширюється під [ВОЛЬНІСТЮ](LICENSE) — простим словом про свободу творити, пам'ятаючи про волю іншого.