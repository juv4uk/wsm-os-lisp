# ADR-003: Machine Mechanism Below, WSM Logic Above
*ADR-003: Машинний механізм внизу, логіка WSM нагорі*

**Date/Дата**: 2026-08-31
**Status/Статус**: Accepted, owner-amended 2026-09-01 / Прийнято, змінено власником 2026-09-01
**Context/Контекст**: The ecosystem requires a clear capability and architectural boundary between the underlying execution layer and the high-level orchestration/semantic layer. We need to ratify the division of responsibilities to avoid overlapping abstractions. / Екосистемі потрібна чітка межа можливостей та архітектури між базовим рівнем виконання та високорівневим рівнем оркестрації/семантики. Нам потрібно затвердити розподіл обов'язків, щоб уникнути дублювання абстракцій.

## 1. The Core Split / Базовий розподіл

**Machine substrate (Mechanism / Механізм):**
Assembly and the tiny target runtime own privileged instructions, interrupt
entry/exit, page and physical-memory primitives, memory fences, and the
authenticity and bounds of capabilities. Rust may implement this substrate,
bootstrap code, a reference driver, or a test harness; Rust is not the
semantic owner of production device-driver logic.

*Асемблер і малий цільовий runtime володіють привілейованими інструкціями,
входом/виходом переривань, примітивами сторінок і фізичної пам'яті, memory
fence, а також справжністю та межами capabilities. Rust може реалізовувати
цей substrate, bootstrap-код, еталонний драйвер або test harness; Rust не є
семантичним власником логіки production-драйвера.*

**WSM/Lisp (Semantics, policy and drivers / Семантика, політика і драйвери):**
WSM owns system meaning and, where the admitted target profile is sufficient,
device discovery, register protocols, queue/descriptor construction, request
state machines, retries, timeout policy and error interpretation. A driver is
ordinary compiled WSM over bounded capabilities; it is not a privileged Rust
object hidden beneath Lisp policy.

*WSM володіє сенсом системи, а коли допущеного target-profile достатньо —
виявленням пристроїв, register-протоколами, побудовою черг/дескрипторів,
state machine запитів, повторами, timeout-policy та тлумаченням помилок.
Драйвер є звичайним скомпільованим WSM над bounded capabilities, а не
привілейованим Rust-об'єктом, прихованим під Lisp-політикою.*

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

This mechanism-policy split anchors to existing wsm-os foundations:
*Цей розподіл механізм-політика спирається на наявні фундаменти wsm-os:*
- **TARGET-ABI.md**: The `wsm-os` ABI remains the strict C-compatible or standard scalar interface. Lisp compiles down to interactions through this ABI.
- **CML IR**: WSM program and driver logic are admitted and lowered by CML;
  target capability calls become versioned ABI imports rather than hidden
  Rust driver calls.
- **ADR-001 / ADR-002 (Boot Image)**: the current Rust/assembly bootstrap remains
  the boot substrate, while compiled WSM owns admitted driver logic.

## 4. Explicit Lisp Prohibitions / Явні заборони для Lisp

To guarantee isolation, the WSM/Lisp layer **MAY NOT**:
*Для гарантування ізоляції, шару WSM/Lisp **СУВОРО ЗАБОРОНЕНО**:*
1. **Raw Pointers**: Access or manipulate raw memory addresses.
2. **Unchecked Device Access**: Forge physical addresses or access a device
   outside an opaque, bounded capability issued by the machine substrate.
3. **Foreign Syscalls**: Execute raw OS syscalls directly bypassing the Rust ABI gate.

This does not prohibit WSM drivers. It prohibits ambient authority. The WSM
driver may perform the allowed register protocol through its capability, while
the substrate validates width, range, lifetime and ownership.

*Це не забороняє WSM-драйвери. Це забороняє ambient authority. WSM-драйвер
може виконувати дозволений register-протокол через capability, тоді як
substrate перевіряє ширину, діапазон, lifetime і ownership.*

## 5. Driver evidence ladder / Сходинка доказів драйвера

```text
pure WSM device logic
  -> canonical my-lisp oracle
  -> CML admission
  -> hosted target witness
  -> Rust/reference driver on the same QEMU device (when useful)
  -> WSM driver over capability ABI on the same QEMU device
  -> identical sector/checksum observation
  -> later physical-hardware evidence
```

Rust reference success is evidence about the device protocol, not evidence
that the WSM production driver works. QEMU and physical hardware remain
distinct claims.

*Успіх Rust reference є evidence щодо протоколу пристрою, але не доказом
роботи production-драйвера WSM. QEMU та фізичне залізо лишаються різними
твердженнями.*

## 6. Rust+Python vs Rust+Lisp Decision / Порівняння Rust+Python та Rust+Lisp

Historically, Python was used for "policy" (orchestration scripts). We have decided to migrate from Rust+Python to Rust+Lisp.
*Історично Python використовувався для "політики" (оркестраційні скрипти). Ми прийняли рішення перейти від Rust+Python до Rust+Lisp.*

- **Why not Python? / Чому не Python?** Python requires a massive background interpreter, struggles with zero-overhead hot reloading of semantic rules, and creates implicit dependencies outside the project tree.
- **Why Lisp? / Чому Lisp?** Our Lisp (WSM) is directly manageable, compiles to our own CML IR, natively supports `status_at_import` for hot reloading, and acts as a transparent, auditable AST that the Rust daemon can sandbox completely.
