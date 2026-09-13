# Bootstrap plan

## Evidence ladder

`DESIGNED -> BOOTED -> WSM-EVAL-PASS -> ORACLE-PARITY -> REAL-HARDWARE-PASS`

Each state requires its own evidence. QEMU boot does not prove real-hardware
support, and a host-side WSM result does not prove bare-metal execution.

## Phase 0 — inventory before porting

1. Split my-lisp dependencies into semantic core and host services.
2. Classify each `std` dependency: replace with `core`/`alloc`, inject through
   a platform trait, or keep host-only.
3. Record graph/cycle semantics explicitly. `Rc` releases acyclic ownership;
   it is not a tracing collector and does not collect reference cycles.
4. Choose the smallest evaluator slice that can execute without filesystem,
   TCP, subprocesses, threads, or wall-clock services.

## Phase 1 — boot witness

- x86_64 UEFI/QEMU first; no direct install on the owner's machine.
- serial console as the initial observable interface.
- deterministic panic report and bounded allocator.
- CI boots the image under a timeout and matches a fixed serial transcript.

## Phase 2 — WSM semantic witness

- expose platform services behind an explicit boundary;
- execute one frozen WSM expression;
- compare value and error behavior with the canonical my-lisp oracle;
- expand only after parity is green.

## Deferred until evidence exists

- GUI, keyboard REPL, disk image persistence and networking;
- live image mutation and recovery semantics;
- AVX2/BMI2 lowering (only after profiling ordinary scalar code);
- NVIDIA GPU support. GTX 1050 Ti requires a driver/runtime strategy; CUDA is
  not treated as a direct bare-metal primitive;
- physical boot on owner hardware.

## Core Architecture Decision (Settled: ADR-001 & ADR-004)

The architecture is settled by [ADR-001](ADR-001-COMPILER-FIRST.md) and
[ADR-004](ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md):
- **Selected**: CML-compiled Lisp forms linked with minimal x86-64 assembly machine primitives.
- **Rejected & Revoked**: `no_std` Rust interpreter/substrate. Production target has zero Rust.

---

# План завантаження / Bootstrap plan (Ukrainian)

## Драбина доказів (Evidence ladder)

`DESIGNED -> BOOTED -> WSM-EVAL-PASS -> ORACLE-PARITY -> REAL-HARDWARE-PASS`

Кожен стан вимагає власних доказів. Завантаження в QEMU не доводить підтримку
реального обладнання, а результат WSM на стороні хоста не доводить виконання
на "голому залізі" (bare-metal).

## Фаза 0 — інвентаризація перед портуванням

1. Розділити залежності `my-lisp` на семантичне ядро та хост-сервіси.
2. Класифікувати кожну залежність `std`: замінити на `core`/`alloc`,
   передати (inject) через платформений trait, або залишити лише для хоста.
3. Явно зафіксувати семантику графів/циклів. `Rc` звільняє ациклічне
   володіння; це не tracing collector і він не збирає циклічні посилання.
4. Обрати найменший фрагмент обчислювача (evaluator slice), який може
   виконуватися без файлової системи, TCP, підпроцесів, потоків чи сервісів
   реального часу (wall-clock).

## Фаза 1 — свідок завантаження (boot witness)

- Спочатку x86_64 UEFI/QEMU; ніяких прямих інсталяцій на машині власника.
- Послідовний (serial) консольний вивід як початковий спостережуваний інтерфейс.
- Детермінований звіт про паніку та обмежений (bounded) алокатор.
- CI завантажує образ з таймаутом і порівнює результат з фіксованим
  консольним транскриптом.

## Фаза 2 — WSM семантичний свідок (semantic witness)

- Відкрити доступ до платформених сервісів через чітко визначену межу;
- Виконати один заморожений WSM-вираз;
- Порівняти значення та поведінку при помилках із канонічним оракулом `my-lisp`;
- Розширювати функціонал лише після того, як паритет стане зеленим (green).

## Відкладено до появи доказів

- GUI, клавіатурний REPL, збереження образів на диск та мережа;
- Семантика мутації живого образу та відновлення;
- Оптимізація AVX2/BMI2 (лише після профілювання звичайного скалярного коду);
- Підтримка NVIDIA GPU. GTX 1050 Ti вимагає стратегії драйвера/середовища виконання;
  CUDA не розглядається як прямий bare-metal примітив;
- Фізичне завантаження на обладнанні власника.

## Базове архітектурне рішення (Затверджено: ADR-001 та ADR-004)

Архітектуру остаточно визначено [ADR-001](ADR-001-COMPILER-FIRST.md) та
[ADR-004](ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md):
- **Обрано**: Lisp-форми, скомпільовані через `cml` та злінковані з незвідними машинними примітивами на x86-64 асемблері.
- **Відхилено та скасовано**: `no_std` Rust інтерпретатор/субстрат. У цільовому runtime — нуль Rust.
