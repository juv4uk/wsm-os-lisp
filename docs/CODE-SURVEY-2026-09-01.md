# CODE-SURVEY-2026-09-01 — огляд коду wsm-os

**Виконавець:** wsl-nidana-1
**Метод:** реальне читання `wsm-os-runtime/src/lib.rs`,
`wsm-os-kernel/src/main.rs` (panic/failure шлях, PCI config read),
`wsm-os-target/src/lib.rs`, `wsm-os-virtio/src/lib.rs`,
`wsm-os-block/src/lib.rs`. Не exhaustive.

## `wsm-os-runtime/src/lib.rs` (493 рядки) — дисциплінований unsafe

Весь рантайм — один `RuntimeContext` з двома сирими вказівниками
(`heap: *mut MaybeUninit<ConsCell>`, `closure_heap: *mut
MaybeUninit<ClosureDescriptor>`) + лічильники `len`/`capacity`.
Bounds-checking без жодного MMU/OS під низом: `cell()`/
`closure_descriptor()` відновлюють індекс через `address - heap_base`
(`checked_sub`, без wraparound), вимагають, щоб offset був точним кратним
розміру клітинки, потім вимагають `index < len` — вказівник має бути і
коректно вирівняний, і вже ініціалізований, щоб резолвитись. `cons()`/
`closure()` відмовляються писати, коли `len == capacity`
(`OutOfMemory`, без тихого wraparound — тест `bounded_heap_never_wraps`
доводить це напряму). Кожен `unsafe`-блок несе конкретний `// SAFETY:`,
прив'язаний до інваріанту, реально перевіреного на два рядки вище
(constructor contract, або щойно виконана перевірка offset/alignment) —
**найдисциплінованіший unsafe-код, побачений у цьому проході**.

**Реальна прогалина:** `RuntimeContext::new`/`new_with_closures` самі
`unsafe fn`, чий ЦІЛИЙ safety-контракт ("арена ексклюзивно володіється на
весь час життя контексту") — прозовий обов'язок викликача, а не
typestate. Нічого не заважає створити другий `RuntimeContext` над тією ж
ареною. **Заведено як `WSM-OS-RUNTIMECONTEXT-EXCLUSIVE-OWNERSHIP` у
`tasks.my`.**

## Panic/failure шлях, `wsm-os-kernel/src/main.rs` (469 рядків)

Два окремі канали відмови, обидва термінальні: (1) null/невалідний
`RuntimeContext`-вказівник спрацьовує `panic_context()` у runtime-краті —
крутиться нескінченно (`core::hint::spin_loop()`), свідомо не
імпортуючи `panic_fmt`, щоб лишатись freestanding; (2) обмежена
runtime-помилка (OOM/Type/AbiViolation) викликає ін'єктований
`failure_handler` (`kernel_failure`), яка декодує `ConditionRecord`,
пише структурований рядок `WSM-OS CONDITION kind=... source=... value=...`
через COM1 serial (bit-banged `outb`/`inb` через сирий `asm!`), потім
`qemu_exit(0x12)`. Власний `#[panic_handler]` робить той самий
serial-write-then-exit танок зі своїм рядком статусу і кодом `0x11`.
Три різні термінальні коди (`0x10` ok / `0x11` Rust panic / `0x12`
runtime condition) — реальна, хоч мінімальна, структура відмов, не просто
"halt".

## PCI config read, той самий файл — це і є код D1, вже живий

Не аспіраційний — реальний. Межі справжні: bus жорстко запінений на 0,
`device` 0-31, `function` 0-7, `offset` 0-254 і парний — точно збігається
з адресацією PCI config-space, і кожен reject-шлях іде через `wsm_fail`,
а не тихо кламп. Сама capability — просто тегований `Word`
(`encode_capability(1)`), перевіряється на рівність з ОДНОЮ очікуваною
константою — "unforgeable" зараз означає "єдине значення, що переживає
`decode_capability` І дорівнює одній константі, яку видає
`wsm_pci_config_capability`" — достатньо для цієї фікстури, але значно
тонша гарантія, ніж натякає проза ADR-003, щойно з'явиться друга
capability. **Заведено як
`WSM-OS-PCI-CAPABILITY-UNFORGEABILITY-HARDENING` у `tasks.my`.**

## `wsm-os-target/src/lib.rs` (327 рядків) — чисте джерело істини

`#[no_std]`, нуль `unsafe`, весь encode/decode тегів — `const fn` через
shift+mask. Точно збігається з числами `target-contract.wsm` (3-bit tag,
61-bit fixnum range тощо) — цей крейт є єдиним джерелом істини, якому
довіряють обидві сторони (CML-емісія, рантайм).

## `wsm-os-virtio/src/lib.rs` (238 рядків) — несподівано порожньо

**Нуль unsafe, взагалі жодного I/O ще немає.** Чистий `DeviceStatus`
state-machine (`acknowledge()`→`driver()`→`driver_ok()`, кожен легальний
лише з точного попереднього стану, повертає `Option`) + PCI/virtio
offset-константи. Весь привілейований port I/O живе лише в
`wsm-os-kernel`. Чисто відповідає розподілу ADR-003 на межі крейтів,
хоча наразі цей крейт — протокольні константи, ще не драйвер.

## `wsm-os-block/src/lib.rs` (613 рядків, найбільший файл)

Hosted (`std`), нуль `unsafe` — лише файловий I/O і checksums, жодних
bare-metal турбот тут, попри те що це найбільший файл у дереві.
