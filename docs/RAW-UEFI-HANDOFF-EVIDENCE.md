# RAW UEFI HANDOFF EVIDENCE / СВІДОК МЕЖІ ПЕРЕДАЧІ КЕРУВАННЯ UEFI

**Статус:** ПІДТВЕРДЖЕНО (CONFIRMED)  
**Репозиторій:** `wsm-os-lisp`  
**Дата фіксації:** 2026-09-05  
**Задача в tasks.my:** `WSM-OS-LISP-RAW-UEFI-HANDOFF-PROBE`  

---

## 1. Architectural Boundary / Архітектурна межа

У межах Lisp Execution Quartet (`my-lisp` -> `cml` -> `wsm-my-lisp` -> `wsm-os-lisp`) метою `wsm-os-lisp` є виконання ролі цільового bare-metal субстрату x86_64 для Lisp-машини.

### Відмінність від лабораторії `wsm-os`:
- У репозиторії `wsm-os` експеримент `probe/exit-boundary-probe.c` реалізував власний ручний цикл `GetMemoryMap` та виклик `ExitBootServices()` на рівні C/gnu-efi.
- У репозиторії `wsm-os-lisp` згідно з ратифікованим **ADR-002** завантаження забезпечується перевіреним стеком `bootloader_api = "=0.11.17"` та утилітою побудови образу `wsm-os-image` (`bootloader::UefiBoot`).

### Фізичний факт переходу межі:
У моделі `bootloader_api` (версія 0.11.17):
1. Завантажувач отримує керування від UEFI прошивки.
2. Викликається `ExitBootServices()`, що остаточно завершує та звільняє всі сервіси завантаження прошивки (UEFI Boot Services).
3. Налаштовується identity/page paging та стек.
4. Керування передається в ядро за адресою `kernel_main(_boot_info: &'static mut BootInfo) -> !`.

Таким чином, **`kernel_main` запускається виключно в режимі post-ExitBootServices ("на голому залізі")**. Жоден виклик UEFI Boot Services після цієї точки фізично неможливий і не здійснюється.

---

## 2. Raw Serial Execution / Прямий ввід-вивід через 16550 UART

Усі операції вводу-виводу ядра в `crates/wsm-os-kernel/src/main.rs` здійснюються виключно через апаратні порти I/O мікросхеми 16550 UART (COM1, базова адреса `0x3F8`):

- Ініціалізація `serial_init()`:
  - Порт `0x3F9` (IER) <- `0x00` (вимикання переривань)
  - Порт `0x3FB` (LCR) <- `0x80` (DLAB=1 для дільника швидкості)
  - Порт `0x3F8` (DLL) <- `0x03` (дільник 3 -> 38400 бод)
  - Порт `0x3F9` (DLM) <- `0x00`
  - Порт `0x3FB` (LCR) <- `0x03` (8 біт, без парності, 1 стоп-біт)
  - Порт `0x3FA` (FCR) <- `0xC7` (FIFO увімкнено, скидання буферів)
  - Порт `0x3FC` (MCR) <- `0x0B` (DTR/RTS активні)
- Запис байтів `serial_write()`:
  - Пряма інструкція x86 `out dx, al` на порт `0x3F8`.
- Читання байтів `inb(COM1)` та перевірка вхідного буфера через `inb(COM1 + 5) & 1`.

Жоден протокол UEFI (`ConOut`, `SimpleTextOutput`, `EFI_SERIAL_IO_PROTOCOL`) не використовується.

---

## 3. Autonomous Lisp Machine Execution / Автономне виконання Lisp-машини

У цьому повністю ізольованому freestanding режимі підтверджено безперебійне виконання всього конвеєра:
1. Ініціалізація середовища виконання `RuntimeContext::new_with_closures`:
   - Статичний буфер пар `HEAP` (`[MaybeUninit<ConsCell>; 8]`).
   - Статичний буфер замикань `CLOSURES` (`[MaybeUninit<ClosureDescriptor>; 4]`).
   - Реєстрація безпечного володіння аренами (`claim_arena`).
2. Виклик точки входу скомпільованого Lisp-коду:
   - `let result = unsafe { wsm_entry(&mut context) };`
3. Успішне виконання утилітних та компіляторних фікстур (перевірено в QEMU/OVMF):
   - `m4` cons-пари `(A . B)`
   - `m5a` умовні вирази та арифметика `(40 . t)`
   - `m5c` глибока хвостова рекурсія tail-call (`countdown 100000` -> `t`)
   - `m1` анонімні функції та замикання (`execution=machine-call`, `lexical-frame`, `captured-frame`)
   - `d0` розпізнавання VirtIO-blk пристрою в скомпільованому WSM
   - `d1` апаратний доступ до PCI Configuration Space через механізм 1 (`0xCF8`/`0xCFC`) за opaque capability.

---

## 4. Висновок

Вимогу задачі `WSM-OS-LISP-RAW-UEFI-HANDOFF-PROBE` повністю задоволено:
- `wsm-os-lisp` успішно перетинає межу `ExitBootServices`.
- Прямий серійний зв'язок 16550 UART працює стабільно без сервісів UEFI.
- Семантика, архітектура та не-Lisp концепції з зовнішнього `wsm-os` не переносились.
- Роль `wsm-os-lisp` як bare-metal субстрату четвірки Lisp Quartet збережена в чистоті.
