# FPC unit: `wsm.bootinfo`

**Статус:** перший повторно використовуваний FPC unit для target-side механізму; експериментальний vertical slice, не production migration.
**Рівень:** Pascal / target mechanism.
**Власник ABI:** `wsm-os-lisp`; джерело layout: `docs/TARGET-BOOT-HANDOFF-ABI.md`.

## Призначення

`wsm.bootinfo` ізолює декодування одного поля UEFI `BootInfo` —
`physical_memory_offset: Optional<u64>`. Unit не читає PCI/MMIO, не керує
пам'яттю і не додає мовних або SENS-примітивів. Він не є джерелом семантики
WSM-пакетів: це механізм нижче package/effect gateway.

## Контракт байтів

Для pinned `bootloader_api = 0.11.17`:

| Поле | Offset | Формат |
|---|---:|---|
| Optional tag | `0x58` | `0 = Some`, `1 = None` |
| Значення для `Some` | `0x60` | little-endian `u64` |

Парсер читає байти окремо, тому не вимагає 8-byte alignment для самого
покажчика. Пам'ять за ненульовим `BootInfo` усе одно має бути валідною та
доступною щонайменше до байта `0x67` включно. Перевірити довільний недійсний
віртуальний покажчик без окремого memory-probe механізму цей unit не може.

## API

```pascal
function WsmBootInfoReadPhysicalMemoryOffset(
  BootInfo: Pointer;
  out PhysicalMemoryOffset: QWord;
  out DiagnosticValue: QWord
): TWsmBootInfoStatus; cdecl;
```

`TWsmBootInfoStatus` — фіксований `Byte`, аби не залежати від розміру Pascal
enum у target ABI:

| Значення | Constant | Поведінка |
|---:|---|---|
| 0 | `WSM_BOOTINFO_STATUS_OK` | `Some(nonzero)` повертає offset; `None` повертає 0 |
| 1 | `WSM_BOOTINFO_STATUS_MISSING` | `BootInfo = nil` |
| 2 | `WSM_BOOTINFO_STATUS_INVALID_TAG` | tag відмінний від 0 або 1; `DiagnosticValue` містить tag |
| 3 | `WSM_BOOTINFO_STATUS_ZERO_OFFSET` | `Some(0)`; відмова |

Обидва вихідні значення очищаються на вході. На помилці offset лишається 0.
`DiagnosticValue` зберігає лише tag для `INVALID_TAG`; інші помилки мають
нульовий diagnostic.

## Fail safely і межі

- `nil` → `MISSING`, без розіменування.
- невідомий Optional tag → `INVALID_TAG`, не трактувати як `None`.
- `Some(0)` → `ZERO_OFFSET`, не трактувати як відсутнє значення.
- `None` → успішний `0`, як визначено існуючим handoff ABI.
- невідповідність результату незалежному ASM reader → чинний `HAN_ERR_MISMATCH`.

Unit не використовує heap, `SysUtils`, exceptions, threadvars або зовнішні
ASM-символи. Hosted-тести перевіряють API окремо; Linux-target і embedded
UEFI/QEMU гейти перевіряють той самий unit у складі handoff fixture. Перевірка
не означає, що ASM production entry/runtime уже перенесено на Pascal.

## Відтворення

```sh
bash scripts/check-pascal-handoff.sh
bash scripts/probe-fpc-embedded.sh
bash scripts/check-fpc-embedded-pascal-handoff.sh
```

Перша команда включає hosted unit tests та чотири Linux-target QEMU handoff
клітини. Дві наступні команди перевіряють pinned `x86_64-embedded` toolchain
та ті самі чотири handoff клітини на embedded target. Для кожного фінального
ядра acceptance вимагає порожній `nm -u`; no-op RTL stubs заборонені.
