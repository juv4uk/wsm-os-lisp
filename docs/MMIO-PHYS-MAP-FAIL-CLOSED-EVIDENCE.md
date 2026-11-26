# MMIO PHYSICAL-MEMORY MAPPING FAIL-CLOSED EVIDENCE / СВІДОК FAIL-CLOSED ФІЗИЧНОЇ ПАМ'ЯТІ ДЛЯ MMIO

**Статус:** ПІДТВЕРДЖЕНО (CONFIRMED)
**Репозиторій:** `wsm-os-lisp`
**Дата фіксації:** 2026-09-13
**Задача в tasks.lisp:** `WSM-OS-VIRTIO-BLK-GUEST-DRIVER-Q6B` (MMIO-статусна частина D2)

> [!NOTE]
> **Historical Evidence Note (2026-09-14, [ADR-004](ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md)):**
> This document witnesses the fail-closed MMIO physical mapping principle established on 2026-09-13.
> Under ADR-004, the fail-closed translation logic and condition codes are implemented directly
> in pure x86-64 assembly primitives (`src/drivers.s`, `src/runtime.s`), maintaining zero Rust in production.
> / Цей документ фіксує принцип fail-closed відображення фізичної пам'яті MMIO від 2026-09-13.
> Відповідно до ADR-004, логіка перевірки та коди умов реалізуються безпосередньо в чистих
> асемблерних примітивах (`src/drivers.s`, `src/runtime.s`), забезпечуючи нуль Rust у production.


---

## 1. Проблема / Problem

MMIO-адреси приходять із PCI BAR і є фізичними адресами. Для доступу під
post-`ExitBootServices` page tables ядро користується фізичним зміщенням,
яке надає завантажувач (`bootloader_api` → `BootInfo::physical_memory_offset`).

Стара реалізація застосовувала:

```rust
PHYS_MEM_OFFSET = boot_info.physical_memory_offset.into_option().unwrap_or(0);
```

...а потім додавала цей offset до фізичної адреси BAR. Якщо завантажувач не
надав offset (`None`), це мовчки перетворювалось на **identity mapping**:

```rust
virt_addr = PHYS_MEM_OFFSET + phys_base; // PHYS_MEM_OFFSET = 0
```

Нуль не є доказом наявності мапінгу: це лише "default value", який створює
хибне враження, ніби фізична й віртуальна адреси збігаються. Це класичне
mapping bug, яке маскує відсутність мапінгу за віртуальним доступом, що
відбувається в будь-якому разі.

## 2. Рішення / Change

У `crates/wsm-os-kernel/src/main.rs` фізичне зміщення переведено на явний стан:

```rust
enum PhysMemMapping { Offset(u64), Unavailable }
static mut PHYS_MEM_MAPPING: PhysMemMapping = PhysMemMapping::Unavailable;
```

Трансляція адреси виконується тільки через `translate_mmio_addr` з
`checked_add` для обох доданків:

```rust
fn translate_mmio_addr(phys_base: u64, byte_offset: u64) -> Result<u64, u32> {
    let virt_offset = match unsafe { PHYS_MEM_MAPPING } {
        PhysMemMapping::Offset(offset) => offset,
        PhysMemMapping::Unavailable => return Err(MMIO_ERR_MAPPING_UNAVAILABLE_READ),
    };
    virt_offset.checked_add(phys_base)
        .and_then(|sum| sum.checked_add(byte_offset))
        .ok_or(MMIO_ERR_ADDRESS_OVERFLOW_READ)
}
```

Нові substrate-коди джерела помилок (для structured condition):

| Код | Значення |
|---:|---|
| `0x4D49_4F07` = 1296649991 | `MMIO_ERR_MAPPING_UNAVAILABLE_READ` |
| `0x4D49_4F08` = 1296649992 | `MMIO_ERR_MAPPING_UNAVAILABLE_WRITE` |
| `0x4D49_4F09` = 1296649993 | `MMIO_ERR_ADDRESS_OVERFLOW_READ` |
| `0x4D49_4F0A` = 1296649994 | `MMIO_ERR_ADDRESS_OVERFLOW_WRITE` |

Відсутність мапінгу й адресне переповнення відкидаються **до** будь-якого
`read_volatile` / `write_volatile`.

## 3. Witness за відсутності мапінгу / Missing-mapping witness

Мутація через env `WSM_OS_FORCE_NO_PHYS_MAP=1` примусово ставить
`PhysMemMapping::Unavailable` на boot. Збірка, image і QEMU-прогін:

```bash
WSM_OS_FORCE_NO_PHYS_MAP=1 WSM_FIXTURE=d2-virtio-blk-status-fixture \
  bash scripts/rebuild-and-run-mapping-fail-closed.sh
```

Результат:

```
PHYS-MAP-PASS: MMIO path rejected missing physical-memory mapping before volatile access
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS CONDITION schema=1 kind=ABI source=1296649992 value=14998298004509163542
```

- гість вийшов структуровано через `wsm_fail` (qemu exit `0x12` → shell 37);
- серійний лог містить `CONDITION kind=ABI source=1296649992` =
  `MMIO_ERR_MAPPING_UNAVAILABLE_WRITE`;
- лог **не містить** `stage=mmio-status value=t` — жоден volatile-доступ не
  відбувся. Транскрипт: `artifacts/d2-virtio-blk-status-fixture-fail-closed-phys-map-transcript.txt`.

## 4. Позитивний шлях без змін / Positive path unchanged

> [!WARNING]
> **Застаріло з 2026-09-17 (ADR-004 / issue #40):** наведений нижче доказ
> походить із pre-ADR-004 Rust-ядра; скрипт
> `scripts/rebuild-and-run-wsm-pci-config-qemu.sh` викликає прибрані крейти
> (`cargo -p m4-generator/wsm-os-image`) і **більше не запускається**. Рядок
> `WSM-OS DRIVER …` не є доказом поточного чистого ASM-шляху.
> Канонічний позитивний свідок тепер:
> `scripts/check-mmio-device-op.sh` →
> `WSM-OS RESULT schema=1 value=t status=ok` (див.
> `docs/MMIO-MUTATION-AND-POLL-EVIDENCE.md`).

Історичний (legacy) запис нижче збережено для provenance:

```
WSM-OS DRIVER schema=1 driver=virtio-blk stage=mmio-status value=t execution=wsm status=ok
```

## 5. Висновок / Conclusion

- `CONFIRMED`: MMIO-шлях fail-closed за відсутності bootloader-мапінгу.
- `CONFIRMED`: offset zero більше не розглядається як identity mapping.
- `CONFIRMED`: позитивний QEMU-шлях (D1/D2) без змін проходить.
- Scope обмежений MMIO-трансляцією; ABI target-contract v2 не змінювався.
---

## 6. Аудит 2026-11-26: що з цього документа ще чинне / Audit 2026-11-26

Перевірка під час побудови реєстру політик (ADR-005, W4) показала, що розділи 1–3 цього
документа описують **pre-ADR-004 Rust-епоху** і в поточному дереві не відтворюються.

| Твердження документа | Стан на 2026-11-26 |
| :--- | :--- |
| Коди `MMIO_ERR_MAPPING_UNAVAILABLE_READ/WRITE` (0x4D494F07/08) — чинні коди відмови | **Ні.** Вони оголошені в `src/runtime.s`, але **жодна інструкція їх не породжує**. `wsm_mmio_capability` зводить усі п'ять причин (немає offset / немає cap / поганий BAR / не замаплено / немає пристрою) в один код `MMIO_ERR_PROVISIONING` (0x4D494F00) |
| Свідок `artifacts/d2-virtio-blk-status-fixture-fail-closed-phys-map-transcript.txt` (`source=1296649992`) | **Історичний.** Його згенерував `scripts/rebuild-and-run-mapping-fail-closed.sh`, який позначений LEGACY pre-ADR-004 і не запускається (кличе прибрані cargo-крейти) |
| Живий свідок тієї самої мутації | `artifacts/d4-mmio-bounds-read-fixture-no-phys-map-transcript.txt`, `source=1296649984`; відтворюється кейсом `forced-no-phys-map` у `scripts/check-mmio-mutation-fail-closed.sh`, який запускається в CI |
| Принцип fail-closed | **Чинний і доведений**, але грубішим кодом: одна відмова на п'ять причин |

Наслідки, зафіксовані в реєстрі:

- політика `mmio-missing-physical-mapping` посилається на живий шлях і живий свідок;
- коди `MMIO_ERR_MAPPING_READ/WRITE` і `MMIO_ERR_DECODE_READ/WRITE` оголошені в
  `policy-enforcement.lisp` як **reserved-but-unemitted** з причинами;
- рішення «розрізняти п'ять причин окремими кодами чи лишити один» **не прийнято** —
  це питання до власника, а не до агента.

Розділ 4 зі своїм `[!WARNING]` лишається чинним без змін.
