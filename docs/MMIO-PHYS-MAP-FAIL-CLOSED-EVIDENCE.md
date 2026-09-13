# MMIO PHYSICAL-MEMORY MAPPING FAIL-CLOSED EVIDENCE / СВІДОК FAIL-CLOSED ФІЗИЧНОЇ ПАМ'ЯТІ ДЛЯ MMIO

**Статус:** ПІДТВЕРДЖЕНО (CONFIRMED)
**Репозиторій:** `wsm-os-lisp`
**Дата фіксації:** 2026-09-13
**Задача в tasks.my:** `WSM-OS-VIRTIO-BLK-GUEST-DRIVER-Q6B` (MMIO-статусна частина D2)

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

`scripts/rebuild-and-run-wsm-pci-config-qemu.sh` (d1-capability, d1-bounds,
d2-status) лишається зеленою без мутації:

```
WSM-OS DRIVER schema=1 driver=virtio-blk stage=mmio-status value=t execution=wsm status=ok
```

## 5. Висновок / Conclusion

- `CONFIRMED`: MMIO-шлях fail-closed за відсутності bootloader-мапінгу.
- `CONFIRMED`: offset zero більше не розглядається як identity mapping.
- `CONFIRMED`: позитивний QEMU-шлях (D1/D2) без змін проходить.
- Scope обмежений MMIO-трансляцією; ABI target-contract v2 не змінювався.