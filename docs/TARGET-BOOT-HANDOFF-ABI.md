# Target Boot Handoff ABI — evidence record / Доказ ABI передачі керування

**Статус:** CONFIRMED (evidence-based, не з пам'яті)
**Репозиторій:** `wsm-os-lisp`
**Дата:** 2026-09-15
**Сфера:** поля `BootInfo`, які цільовий асемблер чи читає, чи не читає; контракт для MMIO phys→virt.

---

## 1. Хто викликає наш `_start` і що передає в `%rdi`

Завантажувач — піний `bootloader` crate 0.11.17, успадкований через
`artifacts/bootx64.efi` (документовано в `ADR-002-BOOT-SUBSTRATE.md`,
`RAW-UEFI-HANDOFF-EVIDENCE.md`). У `context_switch` (джерело:
`bootloader-x86_64-common-0.11.17/src/lib.rs`) перед `jmp` на точку входу
kernel в регістр `%rdi` кладеться значення `addresses.boot_info`:

```asm
xor rbp, rbp
mov cr3, {}            # page_tables.kernel_level_4_frame
mov rsp, {}            # addresses.stack_top
push 0
jmp {}                 # addresses.entry_point
# `in("rdi")` => &'static mut BootInfo
```

**Висновок:** у нашому `_start` `%rdi` на вході дорівнює `&BootInfo`.
Це фактична, а не припущена поведінка завантажувача.

## 2. Layout `BootInfo` для полів, які читає ASM

`BootInfo` — `#[repr(C)]`, версія `bootloader_api = "=0.11.17"`.
Вирахувано реальним компілятором цього самого крейту:

```text
BootInfo size = 232 align = 8
physical_memory_offset offset 0x58 (88)
```

Тип поля `physical_memory_offset` — `Optional<u64>` (`#[repr(C)]` enum):

| Байт 0 (тег) | Значення |
|---|---|
| `0x00` | `Some` — значення лежить на байтах 8..15 |
| `0x01` | `None` — фізичний мапінг не надано |

`Option`-подібне `Optional<u64>` займає 16 байт (тег у нульовому байті,
значення на offset 8), вирівнювання 8. Тобто **слово значення
`physical_memory_offset` перебуває на offset `0x58 + 8 = 0x60`** вузла
`BootInfo`, а **тег — на `0x58`**.

Підтверджено побайтовим дампом того самого типу (див. розділ 4).

## 3. Конфігурація мапінгів, яку бачить наш kernel

`src/bootloader-config.bin` (133 байти) — десеріалізований тим самим
`bootloader_api`:

```text
mappings.kernel_stack     = Dynamic
mappings.kernel_base      = Dynamic
mappings.boot_info        = Dynamic
mappings.framebuffer      = Dynamic
mappings.physical_memory  = Some(Dynamic)   # фіз. пам'ять мапиться
mappings.page_table_recursive = None
mappings.aslr             = false
mappings.dynamic_range_start = None
mappings.dynamic_range_end   = None
```

Зогляду на `Some(Dynamic)`: завантажувач мапує фізичну пам'ять у динамічно
обрану високошвидкісну віртуальну область; фактичний offset передається через
`physical_memory_offset`. Це **не** дозволяє нам знати адресу наперед — отже
target мусить прочитати її з `BootInfo` в рантаймі.

Зогляду на `page_table_recursive = None`: рекурсивного відображення рівнів
немає; для перевірки «чи реально BAR відмаплений» target має виконати власний
page-table walk через `%cr3` (це наша стрільня — див. MMIO vertical slice).

## 4. Побайтовий доказ `Optional<u64>`

Експеримент: `bootloader_api 0.11.17` у хостовому Rust, дамп байтів:

```text
None : 01 00 00 00 00 00 00 00  00 a0 f6 00 fc 7f 00 00   <- байт0 = 0x01
Some : 00 00 00 00 fc 7f 00 00  00 00 00 00 00 01 00 00   <- байт0 = 0x00, value @8
```

(значення в `Some` = `0x0000000100000000`, малий порядок байтів;
вісімка з `fc 7f` на байтах 1–7 — сміття від дроп-керiвання в harness,
не частина layout.)

## 5. Що ASM реально використовує з Rust-структури

Жодного розмазування знань по коду. Єдині залежності — дві сталі в target boot
init (перелічені нижче), які покриваються `bootloader_api =0.11.17` — pin
зафіксовано в `ADR-002` та `Cargo.lock`/алиas-файлах образу:

| Поле | Тип | Offset у `BootInfo` | Призначення |
|---|---|---|---|
| тег `physical_memory_offset` | `Optional<u64>` discriminant | `0x58` | Some/None |
| значення `physical_memory_offset` | u64 | `0x60` | базовий offset фіз. пам'яті в virt |

Якщо `bootloader_api` колись буде змінено версією — цей файл є контрольною
точкою для повторного вимірювання layout перед комітом.

## 6. Примітка мовою

Цільовий асемблер споживає тільки два машинні значення з boot handoff і не
розуміє Rust-структури загалом. Це свідомий мінімальний boot handoff adapter:
`BootInfo` повідомляє факт-карту (offset), provisioning і адреси BAR власні
для target, а Lisp/CML ніколи не бачать фізичних адрес або boot offset.

---

# Target Boot Handoff ABI — українською / основний зміст

Цей документ фіксує доказ контракту між завантажувачем (bootloader 0.11.17)
і цільовим асемблером `wsm-os-lisp`:

- `%rdi` на вході в `_start` = `&BootInfo`;
- `physical_memory_offset` — `Optional<u64>` на offset `0x58` (тег; `0x00`
= Some, `0x01` = None) та `0x60` (значення, u64);
- конфіг мапує фізичну пам'ять (`physical_memory = Some(Dynamic)`), рекурсії
level-4 немає;
- ASM читає рівно два поля, всі допоміжні речі — target-side.

Доказовий ланцюг: source `bootloader` → `context_switch` (`%rdi`) →
`BootInfo` layout виміряно компілятором → конфіг десеріалізовано офіційним
крейтом → дамп `Optional<u64>` побайтово.