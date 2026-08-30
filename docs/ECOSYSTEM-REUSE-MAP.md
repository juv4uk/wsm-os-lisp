# Ecosystem reuse map

**Observed:** 2026-08-29. Links below pin the inspected commits so future
changes do not silently strengthen these claims.

## Recommended architecture

```text
WSM source
   | semantic oracle / conformance
   v
my-lisp ------------------------------+
   | admitted subset                  |
   v                                  | compare value + error
CML IR -> future freestanding backend |
   |                                  |
   v                                  |
wsm-os boot/runtime ------------------+
```

`wsm-os` should own platform boot and services. It should not fork WSM
semantics, CML lowering rules, or the FPGA ISA.

## Reuse now

| Source | Reuse in `wsm-os` | Status and limit |
|---|---|---|
| [`my-lisp/language-contract.my`](https://github.com/juv4uk/my-lisp/blob/667b587394dc8d3fc8dadff7c925e5bce68ed887/language-contract.my) | Semantic authority and version gate | Direct contract reuse; not machine code |
| [`my-lisp` conformance fixtures](https://github.com/juv4uk/my-lisp/tree/667b587394dc8d3fc8dadff7c925e5bce68ed887/tests/fixtures) | Oracle-parity inputs and expected behavior | Reuse test data selectively; preserve exact contract tier |
| [`canonical-serialization.md`](https://github.com/juv4uk/my-lisp/blob/667b587394dc8d3fc8dadff7c925e5bce68ed887/docs/canonical-serialization.md) | Stable serial/boot transcript representation | Direct specification reuse |
| [`syntax::fasl`](https://github.com/juv4uk/my-lisp/blob/667b587394dc8d3fc8dadff7c925e5bce68ed887/crates/my-lisp/src/syntax.rs) | Pre-parsed, source-hash-bound program image pattern | Reuse format/code only after `alloc` portability audit |
| [`CML Ir`](https://github.com/juv4uk/cml/blob/bfb0cac3ab3938924a58e749d99eec6ca06a8a88/src/ir.rs) and [`lower`](https://github.com/juv4uk/cml/blob/bfb0cac3ab3938924a58e749d99eec6ca06a8a88/src/lower.rs) | Front-end-independent AOT boundary | Best starting point for a freestanding target; CML coverage is narrower than current my-lisp |
| [`CML C backend`](https://github.com/juv4uk/cml/blob/bfb0cac3ab3938924a58e749d99eec6ca06a8a88/src/c_backend.rs) | Reference for closures, environments and emitted runtime layout | Design/code reference; current output is hosted C, not freestanding C |
| [`fpga-lisp/isa-contract.my`](https://github.com/juv4uk/fpga-lisp/blob/80e2fc170650b391f128353985445291da493957/isa-contract.my) | Example of a machine-readable target contract | Reuse the contract pattern, not its 32-bit FPGA encoding |
| [`fpga-lisp` testing contract](https://github.com/juv4uk/fpga-lisp/blob/80e2fc170650b391f128353985445291da493957/docs/testing.md) | Boot-image -> execute -> stable observable result evidence shape | Direct methodology reuse |

All three source repositories are MIT at the inspected commits. Linking does
not copy code; any later copied source must retain the applicable license and
notice.

## Adapt after a bounded extraction

### `my-lisp` core

[`crates/my-lisp`](https://github.com/juv4uk/my-lisp/tree/667b587394dc8d3fc8dadff7c925e5bce68ed887/crates/my-lisp)
has no normal Cargo dependencies and already separates filesystem, process and
TCP capabilities into
[`my-lisp-host`](https://github.com/juv4uk/my-lisp/tree/667b587394dc8d3fc8dadff7c925e5bce68ed887/crates/my-lisp-host).
That is the strongest reuse seam in the ecosystem.

It is **not yet `no_std`**. The inspected core still imports:

- `std::rc::Rc`, `RefCell`, `HashMap`, `HashSet` and formatting;
- `std::sync::{Arc, OnceLock, RwLock}` for buffers/capability registry;
- `std::time::Instant` for timing primitives;
- `std::io::stdin` for the line reader;
- `std::error::Error` for the host error trait.

Most containers can move to `alloc`/`core`. Timing, stdin and the global
capability registry require explicit platform decisions. Therefore the first
code change should be a feature-gated portability inventory, not adding
`#![no_std]` to the whole crate.

### FASL rather than a text reader in the first image

The first boot witness should embed a source-hash-bound FASL expression. This
avoids pulling the complete text reader, file loading and standard library into
the boot image before the evaluator boundary works. Text REPL support remains
a later platform capability.

## Reference only

### McCarthy x86_64 kernel

The ecosystem's
[`mccarthy_eval_x86_64`](https://github.com/juv4uk/ecosystem/tree/7060d6fd6d2fdc48d75b830083775a49d60beff2/prototypes/mccarthy_eval_x86_64)
is real executing assembly and proves tagged values, cons allocation,
reader/eval/apply and recursive Lisp on this CPU family.

It is not a boot kernel:

- it has its own reduced Lisp semantics, not the my-lisp contract;
- it is assembled and linked as a hosted Linux program;
- it uses process startup, `argv`, libc file I/O and OS-provided memory;
- several runtime and recovery obligations differ from `wsm-os`.

Reuse its experiments and fixtures as an x86 implementation reference. Do not
make it the semantic or boot authority.

### FPGA Lisp machine

[`fpga-lisp`](https://github.com/juv4uk/fpga-lisp/tree/80e2fc170650b391f128353985445291da493957)
already proves a true independent Lisp machine with tagged words, heap, ISA,
UART bootloader and assembler. Its reusable contribution to `wsm-os` is the
discipline:

```text
machine-readable ISA
-> deterministic image
-> simulated boot path
-> observable result
-> synthesis evidence
-> physical evidence
```

The instruction encoding, BRAM layout and UART implementation are FPGA-owned
and must not be copied into an x86 target merely for uniformity.

## Do not reuse as assumed facts

- `Rc` is not a tracing garbage collector and does not reclaim cycles.
- A dependency-free Rust crate is not automatically `no_std`.
- C output is not automatically freestanding or bootable.
- AVX2/BMI2 should follow profiling; it is not the first correctness seam.
- GTX 1050 Ti CUDA requires a driver/runtime strategy and is not a bare-metal
  primitive of the Lisp machine.
- QEMU evidence does not imply owner-hardware boot evidence.

## First executable reuse spike

1. Pin one Tier-1 WSM expression and expected value/error from my-lisp.
2. Lower the admitted form through CML IR.
3. Add a tiny freestanding emitter/runtime in `wsm-os` for only the needed IR
   nodes.
4. Boot it in QEMU and emit a canonical result over serial.
5. Compare the serial result against the canonical my-lisp oracle.

This route reuses the most mature boundaries without requiring an immediate
`no_std` conversion of the full interpreter.

---

# Карта перевикористання екосистеми (український переклад)

**Зафіксовано:** 2026-08-29. Посилання нижче пінінгують переглянуті коміти,
щоб майбутні зміни не посилювали ці твердження мовчки.

## Рекомендована архітектура

```text
WSM-джерело
   | семантичний оракул / conformance
   v
my-lisp ------------------------------+
   | допущена підмножина              |
   v                                  | порівняй значення + помилку
CML IR -> майбутній freestanding бекенд |
   |                                  |
   v                                  |
wsm-os boot/runtime ------------------+
```

`wsm-os` має володіти платформним завантаженням і сервісами. Він не повинен
форкувати семантику WSM, правила зниження CML чи FPGA ISA.

## Перевикористання зараз

| Джерело | Перевикористання в `wsm-os` | Статус і межа |
|---|---|---|
| [`my-lisp/language-contract.my`](https://github.com/juv4uk/my-lisp/blob/667b587394dc8d3fc8dadff7c925e5bce68ed887/language-contract.my) | Семантична авторитетність і версійний гейт | Пряме перевикористання контракту; не машинний код |
| [`my-lisp` conformance fixtures](https://github.com/juv4uk/my-lisp/tree/667b587394dc8d3fc8dadff7c925e5bce68ed887/tests/fixtures) | Вхідні дані й очікувана поведінка для oracle-parity | Перевикористовувати тестові дані вибірково; зберегти точний рівень контракту |
| [`canonical-serialization.md`](https://github.com/juv4uk/my-lisp/blob/667b587394dc8d3fc8dadff7c925e5bce68ed887/docs/canonical-serialization.md) | Стабільне представлення serial/boot-транскрипту | Пряме перевикористання специфікації |
| [`syntax::fasl`](https://github.com/juv4uk/my-lisp/blob/667b587394dc8d3fc8dadff7c925e5bce68ed887/crates/my-lisp/src/syntax.rs) | Патерн попередньо розібраного образу програми, прив'язаного до source-hash | Перевикористовувати формат/код лише після аудиту портативності `alloc` |
| [`CML Ir`](https://github.com/juv4uk/cml/blob/bfb0cac3ab3938924a58e749d99eec6ca06a8a88/src/ir.rs) і [`lower`](https://github.com/juv4uk/cml/blob/bfb0cac3ab3938924a58e749d99eec6ca06a8a88/src/lower.rs) | Межа AOT, незалежна від фронтенду | Найкраща точка старту для freestanding-цілі; покриття CML уже, ніж поточний my-lisp |
| [`CML C backend`](https://github.com/juv4uk/cml/blob/bfb0cac3ab3938924a58e749d99eec6ca06a8a88/src/c_backend.rs) | Довідник для замикань, середовищ і розкладки рантайму | Довідник дизайну/коду; поточний вивід — hosted C, не freestanding C |
| [`fpga-lisp/isa-contract.my`](https://github.com/juv4uk/fpga-lisp/blob/80e2fc170650b391f128353985445291da493957/isa-contract.my) | Приклад machine-readable цільового контракту | Перевикористати патерн контракту, не його 32-бітне FPGA-кодування |
| [`fpga-lisp` testing contract](https://github.com/juv4uk/fpga-lisp/blob/80e2fc170650b391f128353985445291da493957/docs/testing.md) | Форма evidence boot-image -> виконання -> стабільний спостережуваний результат | Пряме перевикористання методології |

Усі три вихідні репозиторії — MIT на переглянутих комітах. Лінкування не
копіює код; будь-який пізніше скопійований код має зберегти відповідну
ліцензію й notice.

## Адаптувати після обмеженої екстракції

### `my-lisp` ядро

[`crates/my-lisp`](https://github.com/juv4uk/my-lisp/tree/667b587394dc8d3fc8dadff7c925e5bce68ed887/crates/my-lisp) не має звичайних Cargo-залежностей
і вже відокремлює filesystem, process і TCP-спроможності в
[`my-lisp-host`](https://github.com/juv4uk/my-lisp/tree/667b587394dc8d3fc8dadff7c925e5bce68ed887/crates/my-lisp-host). Це найсильніший шов
перевикористання в екосистемі.

Воно **ще не `no_std`**. Переглянуте ядро досі імпортує:

- `std::rc::Rc`, `RefCell`, `HashMap`, `HashSet` і форматування;
- `std::sync::{Arc, OnceLock, RwLock}` для буферів/реєстру спроможностей;
- `std::time::Instant` для примітивів часу;
- `std::io::stdin` для лінійного читача;
- `std::error::Error` для хост-трейту помилок.

Більшість контейнерів можна перенести на `alloc`/`core`. Часові примітиви,
stdin і глобальний реєстр спроможностей потребують явних платформних рішень.
Тому перша зміна коду має бути feature-gated inventory портативності, а не
додавання `#![no_std]` до всієї крейти.

### FASL замість текстового читача в першому образі

Перший boot-свідок має вбудувати FASL-вираз, прив'язаний до source-hash. Це
уникає затягування повного текстового читача, завантаження файлів і стандартної
бібліотеки в boot-образ до того, як працюватиме межа evaluator. Текстова REPL
підтримка лишається пізнішою платформною спроможністю.

## Лише як довідник

### McCarthy x86_64 kernel

[`mccarthy_eval_x86_64`](https://github.com/juv4uk/ecosystem/tree/7060d6fd6d2fdc48d75b830083775a49d60beff2/prototypes/mccarthy_eval_x86_64)
екосистеми — реальний виконуваний асемблер і доводить tagged значення,
alloc cons, reader/eval/apply і рекурсивний Lisp на цьому сімействі CPU.

Це не boot-kernel:

- він має власну зменшену семантику Lisp, не контракт my-lisp;
- він зібраний і злінкований як hosted Linux-програма;
- він використовує process startup, `argv`, libc file I/O і пам'ять від ОС;
- кілька обов'язків рантайму й відновлення відрізняються від `wsm-os`.

Перевикористати його експерименти й фікстури як x86-довідник реалізації. Не
робити його семантичною або boot-авторитетністю.

### FPGA Lisp machine

[`fpga-lisp`](https://github.com/juv4uk/fpga-lisp/tree/80e2fc170650b391f128353985445291da493957) уже доводить справжню незалежну Lisp-машину з
tagged словами, купою, ISA, UART bootloader'ом і асемблером. Його придатний
внесок у `wsm-os` — дисципліна:

```text
machine-readable ISA
-> детермінований образ
-> симульований boot-шлях
-> спостережуваний результат
-> evidence синтезу
-> фізичний evidence
```

Кодування інструкцій, розкладка BRAM і реалізація UART належать FPGA і не
мають копіюватися в x86-ціль лише заради одноманітності.

## Не перевикористовувати як припущені факти

- `Rc` — не tracing garbage collector і не прибирає цикли.
- Rust-крейт без залежностей не є автоматично `no_std`.
- C-вивід не є автоматично freestanding або завантажуваним.
- AVX2/BMI2 має слідувати за профілюванням; це не перший шов коректності.
- CUDA на GTX 1050 Ti потребує стратегії драйвера/рантайму та не є
  bare-metal примітивом Lisp-машини.
- QEMU-доказ не означає доказу boot на залізі власника.

## Перший виконуваний reuse-спайк

1. Зафіксувати один Tier-1 WSM-вираз та очікуване значення/помилку з my-lisp.
2. Знизити допущену форму через CML IR.
3. Додати крихітний freestanding emitter/рантайм у `wsm-os` лише для потрібних
   вузлів IR.
4. Завантажити його в QEMU і видати канонічний результат по serial.
5. Порівняти serial-результат із канонічним оракулом my-lisp.

Цей шлях перевикористовує найзріліші межі без негайної конвертації всього
інтерпретатора на `no_std`.
