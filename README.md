# wsm-os

Research and executable prototypes for a WSM-native Lisp machine on real
hardware.

The project starts with a narrow claim: boot a minimal target, establish a
typed host boundary, and execute one verified WSM expression. It does not yet
claim to be an operating system, a `no_std` port of all of my-lisp, or a
bare-metal CUDA runtime.

## Goal

The primary bare-metal target is the owner's own physical machine
(Gigabyte H170-Gaming 3, Intel Core i5-6400, Skylake-class UEFI x86_64 --
see [docs/OWNER-HARDWARE-PROFILE.md](docs/OWNER-HARDWARE-PROFILE.md) for
the full, privacy-scrubbed profile). QEMU stays the proof gate before any
physical run, per [docs/QEMU-LOCAL-RUN.md](docs/QEMU-LOCAL-RUN.md); a
physical boot is a distinct, not-yet-claimed evidence class.

That one machine is the target, not the boundary of the driver
architecture. [ADR-003](docs/ADR-003-RUST-LISP-MECHANISM-POLICY.md)'s
capability model (bounded PCI/MMIO/DMA primitives, substrate mechanism
below, WSM-owned device policy above) is deliberately not specialized to
this one board or this one CPU generation: a driver written against that
capability boundary should have no reason to assume Skylake, H170, or any
detail specific to the owner's machine. Writing a driver for a different
device or a different physical machine is expected to mean supplying a
different capability provisioning at boot, not rewriting the driver's own
WSM logic.

For the longer-range architectural picture beyond this bounded goal (a
full WSM-native operating system, WSM on bare metal via a bootstrap-to-
self-hosting path, GPU compute as a separate frontier), see
[docs/VISION.md](docs/VISION.md) -- explicitly aspiration, not evidence,
and kept separate from this section on purpose.

## Authority boundaries

- `my-lisp` owns WSM language semantics and remains the reference oracle.
- `cml` owns portable lowering and target admission.
- `fpga-lisp` owns the bounded FPGA Lisp-machine implementation.
- `wsm-os` owns boot, platform services, and bare-metal integration evidence.

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

## Про wsm-os / About wsm-os (Ukrainian)

Дослідження та виконувані прототипи WSM-нативної Lisp-машини на реальному
обладнанні.

Проєкт починається з вузької мети: завантажити мінімальний таргет, встановити
типізовану межу хоста та виконати один верифікований WSM-вираз. Наразі він не
претендує на статус повноцінної операційної системи, порту всього my-lisp на
базі `no_std`, чи bare-metal середовища для CUDA.

## Ціль

Основна bare-metal ціль — власна фізична машина власника (Gigabyte
H170-Gaming 3, Intel Core i5-6400, Skylake-класу UEFI x86_64 — повний,
очищений від приватних даних профіль у
[docs/OWNER-HARDWARE-PROFILE.md](docs/OWNER-HARDWARE-PROFILE.md)). QEMU
лишається обов'язковим воротом доказу перед будь-яким фізичним запуском,
per [docs/QEMU-LOCAL-RUN.md](docs/QEMU-LOCAL-RUN.md); фізичний бут —
окремий, ще не заявлений клас доказу.

Ця одна машина — ціль, а не межа драйверної архітектури.
Capability-модель [ADR-003](docs/ADR-003-RUST-LISP-MECHANISM-POLICY.md)
(обмежені PCI/MMIO/DMA примітиви, substrate-механізм внизу,
WSM-політика пристроїв нагорі) свідомо не спеціалізована під цю плату чи
це покоління CPU: драйвер, написаний проти цієї capability-межі, не
повинен мати причин припускати Skylake, H170 чи будь-яку деталь, властиву
саме машині власника. Написання драйвера для іншого пристрою чи іншої
фізичної машини має означати інше provisioning capability при завантаженні,
а не переписування власної WSM-логіки драйвера.

Ширшу архітектурну картину поза цією обмеженою ціллю (повноцінна
WSM-native операційна система, WSM на bare metal через шлях
bootstrap-до-self-hosting, GPU compute як окремий фронтир) дивись
[docs/VISION.md](docs/VISION.md) — явно прагнення, не доказ, і навмисно
тримається окремо від цього розділу.

## Межі відповідальності

- `my-lisp` володіє семантикою мови WSM і залишається еталонним оракулом.
- `cml` відповідає за переносиме перетворення (lowering) та допуск до таргетів.
- `fpga-lisp` володіє реалізацією Lisp-машини, обмеженої можливостями FPGA.
- `wsm-os` володіє завантаженням (boot), платформеними сервісами та доказами
  bare-metal інтеграції.

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
