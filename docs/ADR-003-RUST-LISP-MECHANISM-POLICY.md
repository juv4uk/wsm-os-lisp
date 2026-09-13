# ADR-003: Machine Mechanism Below, WSM Logic Above
*ADR-003: Машинний механізм внизу, логіка WSM нагорі*

**Date/Дата**: 2026-08-31
**Status/Статус**: SUPERSEDED by ADR-004 (2026-09-14) / ЗАМІНЕНО на ADR-004 (2026-09-14)
**Context/Контекст**: The ecosystem requires a clear capability and architectural boundary between the underlying execution layer and the high-level orchestration/semantic layer. We need to ratify the division of responsibilities to avoid overlapping abstractions. / Екосистемі потрібна чітка межа можливостей та архітектури між базовим рівнем виконання та високорівневим рівнем оркестрації/семантики. Нам потрібно затвердити розподіл обов'язків, щоб уникнути дублювання абстракцій.

> [!CAUTION]
> **SUPERSEDED / ЗАМІНЕНО (2026-09-14):**
> This ADR is superseded by [ADR-004](ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md).
> The owner directive mandates: **LISP + x86-64 ASSEMBLER. RUST = 0.**
> All provisions permitting a Rust substrate, bootstrap, runtime, or reference driver are revoked.
> / Цей ADR замінено на [ADR-004](ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md).
> Директива власника встановлює: **LISP + x86-64 ASSEMBLER. RUST = 0.**
> Усі положення, що дозволяли субстрат, bootstrap, runtime або драйвери на Rust, скасовано.

> [!IMPORTANT]
> **Repository-role amendment / Уточнення ролі репозиторію (2026-09-11):**
> this ADR governs the machine-mechanism boundary implemented by
> `wsm-os-lisp`, the bare-metal control target for the `my-lisp` lineage.
> The separate `juv4uk/wsm-os` repository owns physical-platform research for
> `juv4uk/wsm`; it does not own the ABI/runtime/boot-image described here.
> / Цей ADR керує межею машинного механізму, реалізованою в `wsm-os-lisp` —
> контрольному bare-metal таргеті лінії `my-lisp`. Окремий `juv4uk/wsm-os`
> володіє дослідженням фізичної платформи для `juv4uk/wsm` і не володіє
> ABI/runtime/boot-образом, описаними тут.

## 1. The Core Split / Базовий розподіл

**Machine substrate (Mechanism / Механізм):**
Assembly and the tiny target runtime (`src/runtime.s`, `src/entry.s`, `src/drivers.s`)
own privileged instructions, interrupt entry/exit, page and physical-memory
primitives, I/O ports (`in`/`out`), memory fences, and capability gating.
Under ADR-004, Rust is completely eliminated (RUST = 0). The machine substrate is
written strictly in pure x86-64 assembly.

*Асемблер і мінімальний цільовий runtime (`src/runtime.s`, `src/entry.s`, `src/drivers.s`)
володіють привілейованими інструкціями, входом/виходом переривань, примітивами
сторінок і фізичної пам'яті, портами вводу-виводу (`in`/`out`), memory fence та
перевіркою capabilities. Згідно з ADR-004, Rust повністю вилучено (RUST = 0). Машинний
субстрат реалізовано виключно на чистому x86-64 асемблері.*

**WSM/Lisp (Semantics, policy and drivers / Семантика, політика і драйвери):**
WSM owns system meaning and, where the admitted target profile is sufficient,
device discovery, register protocols, queue/descriptor construction, request
state machines, retries, timeout policy and error interpretation. A driver is
ordinary compiled WSM over bounded assembly capabilities; there is no hidden
runtime or foreign daemon beneath Lisp policy.

*WSM володіє сенсом системи, а коли допущеного target-profile достатньо —
виявленням пристроїв, register-протоколами, побудовою черг/дескрипторів,
state machine запитів, повторами, timeout-policy та тлумаченням помилок.
Драйвер є звичайним скомпільованим WSM над обмеженими асемблерними capabilities;
під Lisp-політикою немає жодного прихованого чужого демона чи стороннього рантайму.*

## 2. Capability boundary / Межа capabilities

The bare-metal driver boundary grows only when an executable WSM fixture earns
a general mechanism. The expected primitive classes are:

- bounded PCI configuration reads/writes;
- bounded MMIO reads/writes;
- pinned DMA allocation and physical-address projection;
- interrupt wait/acknowledgement;
- explicit memory barriers and page mapping.

The exact names, widths and error records are versioned in the target ABI only
when their first fixture is admitted. The first planned primitive is a bounded
16-bit PCI configuration read; `virtio-blk`-specific operations do not belong
in this boundary.

*Bare-metal межа драйвера росте лише тоді, коли executable WSM-fixture
обґрунтовує загальний механізм. Очікувані класи примітивів: bounded PCI
configuration read/write, bounded MMIO read/write, pinned DMA allocation і
проєкція фізичної адреси, очікування/підтвердження переривань, явні memory
barriers та page mapping. Точні назви, ширини й error-records версіонуються в
target ABI лише разом із першим допущеним fixture. Першим запланованим
примітивом є bounded 16-bit PCI configuration read; `virtio-blk`-специфічним
операціям у цій межі не місце.*

Hosted services such as `spawn`, `send`/`receive`, `schedule` and
`write-state`/`read-state` remain a separate hosted capability profile; their
existence does not make them bare-metal language primitives.

*Hosted-сервіси `spawn`, `send`/`receive`, `schedule` та
`write-state`/`read-state` лишаються окремим hosted capability profile; їхня
наявність не робить їх bare-metal примітивами мови.*

## 3. Binding to Existing Contracts / Зв'язок із наявними контрактами

This mechanism-policy split anchors to existing `wsm-os-lisp` foundations:
*Цей розподіл механізм-політика спирається на наявні фундаменти `wsm-os-lisp`:*
- **TARGET-ABI.md**: The `wsm-os-lisp` ABI remains the strict System V AMD64 scalar interface. Lisp compiles down to interactions through this ABI.
- **CML IR**: WSM program and driver logic are admitted and lowered by CML;
  target capability calls become versioned ABI imports in pure assembly.
- **ADR-004 (Pure Lisp + Assembly Architecture)**: pure assembly bootstrap (`src/entry.s`,
  `src/runtime.s`) provides the boot substrate, while compiled WSM owns admitted driver logic. Rust is 0.

## 4. Explicit Lisp Prohibitions / Явні заборони для Lisp

To guarantee isolation, the WSM/Lisp layer **MAY NOT**:
*Для гарантування ізоляції, шару WSM/Lisp **СУВОРО ЗАБОРОНЕНО**:*
1. **Raw Pointers**: Access or manipulate raw memory addresses outside verified bounds.
2. **Unchecked Device Access**: Forge physical addresses or access a device
   outside an opaque, bounded capability issued by the machine substrate.
3. **Ambient Side Effects**: Execute unverified low-level instructions bypassing the capability gate.

This does not prohibit WSM drivers. It prohibits ambient authority. The WSM
driver may perform the allowed register protocol through its capability, while
the assembly substrate validates width, range, lifetime and ownership.

*Це не забороняє WSM-драйвери. Це забороняє ambient authority. WSM-драйвер
може виконувати дозволений register-протокол через capability, тоді як
асемблерний субстрат перевіряє ширину, діапазон, lifetime і ownership.*

## 5. Driver evidence ladder / Сходинка доказів драйвера

```text
pure WSM device logic
  -> canonical my-lisp oracle
  -> CML admission
  -> assembly lowering (src/runtime.s + emitted .s)
  -> WSM driver over capability ABI on QEMU device
  -> identical sector/checksum observation
  -> later physical-hardware evidence
```

QEMU and physical hardware remain distinct claims. A later physical run may graduate
evidence for an already pinned `wsm-os-lisp` artifact; new physical-platform research itself belongs to the separate `wsm-os` lab.


*QEMU та фізичне залізо лишаються різними твердженнями. Пізніший фізичний запуск
може підвищити клас доказу вже зафіксованого артефакту `wsm-os-lisp`; саме нове
дослідження фізичної платформи належить окремій лабораторії `wsm-os`.*

## 6. Architectural Evolution / Архітектурна еволюція: Lisp + Assembly

Historically, early exploration considered combinations like Python orchestration,
then Rust substrates. In accordance with the owner's directive and ADR-004, all
intermediaries have been eliminated:

```text
Lisp (WSM)
  ↓
CML (Compiler / Lowering)
  ↓
x86-64 Assembly (GNU as / ld)
  ↓
Bare Metal CPU
```

- **No C, No Rust:** C is an unnecessary intermediate abstraction, and Rust's toolchain
  and runtime layers are entirely removed from production.
- **Why Pure Lisp + Assembly?** Lisp provides an auditable, formally checkable symbolic
  model for drivers, data, and system logic. Assembly provides exact, cycle-accurate,
  irreducible machine control. Together they form a complete, freestanding Lisp machine.

*Історично ранні дослідження розглядали комбінації з Python, згодом — субстрати на Rust.
Відповідно до директиви власника та ADR-004, усіх посередників усунуто: мова — Lisp,
машинний рівень — чистий x86-64 асемблер. Жодного C чи Rust у production runtime.*