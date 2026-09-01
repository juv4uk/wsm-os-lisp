# VISION

**Status: aspiration, not a decision or a contract.** This document names the
architectural ceiling the project is aimed at. It does not authorize any of
it, does not change scope, and does not add or close any `tasks.my` entry.
Nothing here may be cited as evidence that something works.

The rest of this repository stays exactly as disciplined as before:
- `README.md` states what the current bounded evidence actually proves.
- `tasks.my` is the executable, swarm-tracked evidence ladder.
- This file states where the project is ultimately headed, and keeps that
  separate from both, on purpose. A large dream is not a defect in a small,
  precise claim — conflating the two is.

## Why this file exists

The narrow claim in `README.md` ("NOT full OS, NOT full no_std my-lisp, NOT
bare-metal CUDA") correctly describes the current evidence state. It must
never be read as the architectural ceiling. The two need to stay visibly
separate:

```text
VISION:
  full WSM-native operating system
  full WSM language on bare metal (self-hosting)
  WSM-owned drivers
  GPU compute / CUDA research

CURRENT EVIDENCE (see README.md / tasks.my):
  closures
  CML x86_64 lowering
  QEMU boot parity
  PCI capability foundation
  ...
```

## The shape of the machine

```text
                 WSM-OS
                    |
        +-----------+-----------+
        |                       |
    Lisp machine             hardware
        |                       |
        |            +----------+----------+
        |            |          |           |
        |           CPU        GPU       devices
        |            |          |           |
        v            v          v           v
   full WSM       x86_64    GPU compute   drivers
   environment     ASM       runtime      in WSM
        |
        +-- reader
        +-- evaluator
        +-- compiler/runtime
        +-- libraries
        +-- Constitution
        +-- filesystem
        +-- drivers
        +-- network
        +-- user environment
```

## Three named goals

### 1. A full operating system

Not "boot prototype" forever — a system that itself provides:

```text
boot -> memory management -> scheduler -> interrupts -> devices
     -> storage -> filesystem/world -> input/output -> networking
     -> process/service model -> security/capabilities -> Lisp environment
```

`README.md`'s framing should change from *research prototype* to
*experimental WSM-native operating system* — but only once the evidence for
each stage above actually exists, one bounded fixture at a time, the same
way every milestone in `tasks.my` already works.

### 2. Full `my-lisp` on bare metal, in three stages

The current architecture is `ASM + a small WSM runtime`, and full `no_std
my-lisp` is Rust. That is not a contradiction as long as the `no_std` port is
read as a bootstrap bridge, not the final architecture:

```text
STAGE 1 (current)
  my-lisp Rust/std -> CML -> ASM + small WSM runtime

STAGE 2
  my-lisp Rust/no_std -> full WSM semantics on bare metal

STAGE 3
  minimal ASM -> WSM -> meta-eval/runtime written in WSM -> WSM executes WSM
```

Stage 3 is where the Rust implementation stops being load-bearing and becomes
an **oracle / reference implementation** — kept around for differential
testing, no longer required for the machine to run. `tasks.my` already names
this direction (`WSM-OS-CONSTITUTION-READER-META-EVAL`); this section just
says it out loud as a destination, not only as one more milestone in a list.

The intermediate claim this stage sequence is building toward, worth stating
precisely once it is actually proven: **the full canonical WSM semantics can
exist without a host OS.** Only after that can the semantics be migrated,
piece by piece, out of Rust and into WSM itself.

### 3. Bare-metal GPU / CUDA — a distinct, harder frontier

Two different things must not be named the same:

```text
GPU compute on bare metal   !=   full CUDA-compatible bare-metal runtime
```

The first is a real architectural goal:

```text
WSM -> CML GPU lowering -> WSM-OS GPU capability/runtime -> GPU
```

The second is much harder — CUDA is an entire NVIDIA ecosystem (device
initialization, firmware, command submission, memory management, kernels,
synchronization, binary formats, and more) and is explicitly out of scope
here as a near-term goal.

A staged ladder, in the same spirit as the PCI/virtio evidence ladder this
repository already uses:

```text
G0  detect GPU
G1  map BARs safely
G2  initialize GPU enough for compute
G3  allocate GPU memory
G4  submit one command
G5  execute one known compute kernel
G6  WSM -> CML -> GPU kernel
G7  heterogeneous CPU + GPU execution
G8  CUDA-compatible subset
G9  broader CUDA runtime compatibility
```

Reaching **G6** — one real WSM-authored compute kernel running on bare-metal
GPU hardware through CML lowering — would already be a major result, with or
without anything resembling the rest of the CUDA API.

#### Open ownership question (not resolved by this document)

**Corrected 2026-09-01** — the first version of this section understated how
crowded this picture already is:

- `wsm-os/repo.my` explicitly lists `cuda-runtime` under `non-authorities`.
- There are now **two separate hosted CUDA surfaces**, not one. CML's own
  `gpu-cuda` feature (`src/gpu_cuda.rs`/`gpu_cuda_runtime.rs`, PTX via NVRTC)
  already runs an admitted i32 `map` on real hardware — a GTX 1050 Ti,
  verified 2026-08-24 (`cml/docs/cuda-runtime.md`), through the host's
  existing NVIDIA driver (via WSL's `libcuda.so` bridge; the native Linux
  driver in that environment reports `CUDA_ERROR_NO_DEVICE`), not bare
  metal. Separately, `wsm-cuda`'s own README describes a similarly-scoped,
  narrower hosted path (`WSM fixture -> CML Compute IR -> CPU oracle -> CUDA
  kernel`). How these two relate — whether `wsm-cuda` consumes CML's
  already-working backend, duplicates it, or owns a genuinely distinct
  slice — is not documented anywhere found as of this writing.
- Neither hosted surface claims G1/G2 below (mapping BARs, initializing the
  GPU without any vendor driver underneath); the bare-metal gap is untouched
  by both.

Bare-metal GPU initialization (G1-G5) is therefore still a real, currently
unclaimed gap — not silently assigned to `wsm-os`, `wsm-cuda`, or CML.
Whether it becomes a new capability class inside `wsm-os` (via the same
PCI/MMIO/DMA capability model `ADR-003` already establishes) or a separate
track is an open decision for whenever this frontier is actually approached
— and resolving the CML/`wsm-cuda` relationship above is a smaller, more
immediate open question this document also does not settle.

## The self-hosting shape, restated

```text
              WSM
               |
        WSM written in WSM
               |
       tiny native primitives
               |
              ASM
               |
            hardware
```

Not an operating system that happens to contain a Lisp. An operating system
for which Lisp is the way it exists.

---

## VISION (українською)

**Статус: прагнення, не рішення і не контракт.** Цей документ називає
архітектурну стелю проєкту. Він нічого не авторизує, не змінює scope і не
додає й не закриває жоден запис у `tasks.my`. Ніщо звідси не може
цитуватися як доказ того, що щось працює.

Решта репозиторію лишається настільки ж дисциплінованою, як і раніше:
- `README.md` каже, що саме зараз доводить обмежений доказ.
- `tasks.my` — виконуваний, відстежуваний роєм ланцюжок доказів.
- Цей файл каже, куди проєкт зрештою прямує, і навмисно тримає це окремо
  від обох. Велика мрія — не хиба маленької точної заявки; плутати їх —
  хиба.

## Навіщо цей файл

Вузька заявка в `README.md` ("NOT full OS, NOT full no_std my-lisp, NOT
bare-metal CUDA") коректно описує поточний стан доказів. Її ніколи не варто
читати як архітектурну стелю. Ці дві речі мають лишатися візуально окремими
(див. англомовну версію вище — VISION / CURRENT EVIDENCE).

## Форма машини

Див. діаграму вище (англомовна версія) — вона єдина для обох мовних секцій.

## Три названі цілі

### 1. Повноцінна операційна система

Не "boot prototype" назавжди — система, яка сама надає: boot, memory
management, scheduler, interrupts, devices, storage, filesystem/world,
input/output, networking, process/service model, security/capabilities,
Lisp environment.

Формулювання в `README.md` має змінитися з *research prototype* на
*experimental WSM-native operating system* — але лише коли з'явиться доказ
для кожного з цих етапів, по одній обмеженій фікстурі за раз, так само як
уже працює кожна віха в `tasks.my`.

### 2. Повний `my-lisp` на bare metal, у три етапи

Поточна архітектура — це `ASM + малий WSM-runtime`, а повний `no_std
my-lisp` — це Rust. Суперечності немає, якщо `no_std`-порт розглядати як
bootstrap-міст, а не остаточну архітектуру:

```text
ЕТАП 1 (поточний)
  my-lisp Rust/std -> CML -> ASM + малий WSM-runtime

ЕТАП 2
  my-lisp Rust/no_std -> повна WSM-семантика на bare metal

ЕТАП 3
  мінімальний ASM -> WSM -> meta-eval/runtime, написаний на WSM -> WSM виконує WSM
```

На етапі 3 Rust-реалізація перестає бути обов'язковою і стає **oracle /
референсною реалізацією** — потрібною для диференційного тестування, але
вже не для роботи машини. `tasks.my` уже називає цей напрямок
(`WSM-OS-CONSTITUTION-READER-META-EVAL`); цей розділ лише промовляє це
вголос як пункт призначення, а не просто чергову віху в списку.

Проміжна заявка, до якої веде ця послідовність етапів, варта точного
формулювання лише після того, як вона реально буде доведена: **уся
канонічна семантика WSM здатна існувати без host OS.** Лише після цього її
можна поступово переносити, шматок за шматком, з Rust у сам WSM.

### 3. Bare-metal GPU / CUDA — окремий, важчий фронтир

Дві різні речі не можна називати однаково: GPU compute on bare metal ≠ full
CUDA-compatible bare-metal runtime. Перше — реальна архітектурна мета (WSM
-> CML GPU lowering -> WSM-OS GPU capability/runtime -> GPU). Друге —
набагато важче: CUDA — це ціла NVIDIA-екосистема (ініціалізація пристрою,
firmware, command submission, memory management, kernels, синхронізація,
бінарні формати тощо) і явно поза найближчим scope тут.

Сходи (G0-G9) — див. англомовну версію вище; G6 (один справжній
WSM-написаний compute-kernel на bare-metal GPU через CML lowering) уже сам
по собі був би значним результатом, навіть без решти CUDA API.

#### Відкрите питання авторства (цей документ його не вирішує)

**Виправлено 2026-09-01** — перша версія цього розділу применшувала, наскільки
переповнена ця картина насправді:

- `wsm-os/repo.my` явно перелічує `cuda-runtime` серед `non-authorities`.
- Зараз є **дві окремі hosted-CUDA поверхні**, не одна. Власна фіча CML
  `gpu-cuda` (`src/gpu_cuda.rs`/`gpu_cuda_runtime.rs`, PTX через NVRTC) вже
  виконує допущений i32 `map` на реальному залізі — GTX 1050 Ti, перевірено
  2026-08-24 (`cml/docs/cuda-runtime.md`), через уже наявний на хості
  NVIDIA-драйвер (через WSL-міст `libcuda.so`; нативний Linux-драйвер у
  цьому середовищі повертає `CUDA_ERROR_NO_DEVICE`) — не bare metal.
  Окремо, власний README `wsm-cuda` описує подібний за обсягом, вужчий
  hosted-шлях (`WSM fixture -> CML Compute IR -> CPU oracle -> CUDA kernel`).
  Як ці два співвідносяться — чи `wsm-cuda` споживає вже робочий бекенд CML,
  чи дублює його, чи володіє справді окремим шматком — ніде не
  задокументовано на момент написання.
- Жодна з hosted-поверхонь не претендує на G1/G2 нижче (мапування BAR,
  ініціалізація GPU без жодного vendor-драйвера під низом); bare-metal
  розрив не торкнутий жодною з них.

Bare-metal ініціалізація GPU (G1-G5) — і досі реальна, наразі нічия межа —
не закріплена мовчки ні за `wsm-os`, ні за `wsm-cuda`, ні за CML. Чи стане
вона новим класом capability всередині `wsm-os` (через ту саму PCI/MMIO/DMA
capability-модель, яку вже встановлює `ADR-003`), чи окремим напрямком —
відкрите рішення на момент, коли до цього фронтиру справді дійде черга — а
розв'язання співвідношення CML/`wsm-cuda` вище є меншим, ближчим відкритим
питанням, яке цей документ теж не вирішує.

## Форма самохостингу, ще раз

Не операційна система, яка просто містить Lisp. Операційна система, для
якої Lisp є способом її існування.
