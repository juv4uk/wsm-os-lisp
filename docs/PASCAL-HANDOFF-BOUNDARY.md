# Pascal owns the handoff boundary
*Pascal володіє межею передачі керування*

**Дата**: 2026-11-27
**Статус**: EVIDENCE — вимір. Закриває залишок [ADR-006](../ADR-006-FPC-AS-FOUNDATION-PROPOSAL.md) фази **P1**, крім embedded-цілі.
**Задача**: `WSM-OS-FPC-HANDOFF-BOUNDARY`
**Гейт**: `bash scripts/check-pascal-handoff.sh`, CI `.github/workflows/pascal-handoff.yml`

---

## 1. Що було не так

Попередній зріз доводив, що Pascal виконується на цілі, але **не** що він володіє
входом у ядро: `_start` сам читав `BootInfo`, сам витягав
`physical_memory_offset` і передавав Pascal готовий `RuntimeContext*`. Тобто
Pascal отримував уже перетравлену дійсність, і жодного негативного свідка на
пошкоджений запис не існувало.

Тепер запис читає Pascal, і він же відмовляється працювати, якщо запис не такий,
як мусить бути.

## 2. Запис, який читає Pascal

Layout не вигаданий — він узятий із `docs/TARGET-BOOT-HANDOFF-ABI.md` і з
`src/runtime.s::wsm_boot_handoff`:

```text
BootInfo + 0x58 : u8   Optional<u64> tag    0 = Some, 1 = None
BootInfo + 0x60 : u64  physical_memory_offset value (коли tag = 0)
```

Читання значення зроблено побайтово (вісім `Byte` зі зсувами), щоб не залежати
від припущень компілятора про вирівнювання невирівняного покажчика.

## 3. Чотири стани, чотири названі результати

| Стан | Що робить Pascal | Умова |
| --- | --- | --- |
| `tag = 0`, значення ≠ 0 | повертає зсув, далі перевіряє збіг з asm | — |
| `tag = 1` (None) | повертає 0, алокація йде далі | — |
| покажчика немає | відмова | `ABI source=0x48414E01 value=0` |
| `tag` не 0 і не 1 | відмова | `ABI source=0x48414E02 value=<tag>` |
| `tag = 0`, значення 0 | відмова | `ABI source=0x48414E03 value=0` |
| Pascal і asm прочитали різне | відмова | `ABI source=0x48414E04 value=<offset>` |

`0x48414E..` — родина «HAN» (handoff), поруч із GC `0x4743....` і MMIO
`0x4D494F..`, щоб у тому самому рядку умови було видно, **хто** відмовив.

Останній рядок — головний. Двоє читачів одного запису мусять дійти однакового
висновку; якщо ні, це дефект одного з них, а не привід «взяти середнє».

## 4. Свідчення

```text
PASS valid       WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok
PASS missing     WSM-OS CONDITION schema=1 kind=ABI source=1212239361 value=0
PASS badtag      WSM-OS CONDITION schema=1 kind=ABI source=1212239362 value=2
PASS zerooffset  WSM-OS CONDITION schema=1 kind=ABI source=1212239363 value=0
PASCAL-HANDOFF-PASS: 4/4
```

Три негативні клітинки створюються **тестовими** мутаціями в `src/entry.s`
(`--defsym WSM_FORCE_NO_BOOT_INFO`, `WSM_FORCE_BAD_BOOT_INFO_TAG`,
`WSM_FORCE_ZERO_BOOT_INFO_OFFSET`), які ніколи не потрапляють у production-збірку:
`build-uefi-image.sh` додає їх лише за явним env-прапорцем, як і наявний
`WSM_FORCE_NO_PHYS_MAP`.

Кожна клітинка також перевіряє, що `nm -u` на фінальному ядрі порожній.

## 5. Чого це не доводить

- **Embedded-цілі.** Усе ще `-Tlinux`; pinned `x86_64-embedded` лишається
  відкритим у P0 (#113).
- **Реальної роботи з мапінгом.** Pascal перевіряє запис, але не робить
  трансляції фізичних адрес — це поки що робить асемблерний механізм.
- **Стійкості до довільного сміття.** Перевіряються чотири конкретні стани, не
  «будь-який пошкоджений запис». Наприклад, `tag = 0` зі значенням, що вказує за
  межі фізичної пам'яті, тут не ловиться — це належить перевірці мапінгу.

## 6. Відтворення

```bash
sudo apt-get install -y --no-install-recommends \
  qemu-system-x86 ovmf mtools dosfstools gdisk binutils fp-compiler
bash scripts/check-pascal-handoff.sh
```

---

## Українською: одне речення

Pascal тепер сам читає `BootInfo`, сам вирішує, чи запис придатний, і відмовляє
названою умовою в трьох різних випадках (немає покажчика, невідомий тег,
`Some` зі нулем), а четверта перевірка ловить розбіжність між Pascal і
асемблером у читанні того самого запису — тобто межа передачі керування більше
не «домовленість у документі», а виконувана умова з чотирма свідками.
