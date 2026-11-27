# ADR-007: Розділення PciConfig і Mmio; BOOT0 = UNPROVEN у hosted Linux
*ADR-007: Separation of PciConfig and Mmio; BOOT0 = UNPROVEN on hosted Linux*

**Date/Дата**: 2026-11-27
**Status/Статус**: **PROPOSED** — відповіді власника дано в чаті 2026-11-27; git-ратифікація ще не виконана
**Deciders/Хто вирішив**: власник (`juv4uk`), directive 2026-11-27; коміт-підпис власника потрібен для `ACCEPTED`
**Related**: [ADR-005](ADR-005-TRUST-BOUNDARY-ARBITER-NOT-KERNELLESS.md), [ADR-006](ADR-006-FPC-AS-FOUNDATION-PROPOSAL.md), [MMIO-PHYS-MAP-FAIL-CLOSED-EVIDENCE](MMIO-PHYS-MAP-FAIL-CLOSED-EVIDENCE.md), [CAPABILITY-IDENTITY-ADVERSARIAL-EVIDENCE](CAPABILITY-IDENTITY-ADVERSARIAL-EVIDENCE.md), `juv4uk/gp107-nvidia-re` `docs/04-bar-identity.md` (commit `c03a171`)

---

## 0. Decision / Рішення

| # | Рішення | Що воно забороняє |
|---:|---|---|
| D1 | `PciConfig` і `Mmio` — **дві окремі capabilities**. `PciConfig` дає енумерацію/інвентаризацію (vendor/device, BAR base) і не надає права на мапінг апертури. | Використовувати PCI-config capability як доказ права на MMIO. |
| D2 | `Mmio` має явний контракт володіння ресурсом: `Exclusive` / `HostedDriver` / `Unknown` і жорсткий read-only профіль для identity-читань. | `PROT_WRITE`, `MAP_FIXED`, `O_RDWR` у будь-якому identity-пробнику; приховане ескалування прав. |
| D3 | Для **hosted Linux під активним `nvidia.ko`** стан `BOOT0 = UNPROVEN` є **нормативним**. `NV_PMC_BOOT_0 = 0x137000A1` лишається string-only гіпотезою й не входить в авторитетний шар. | Обходити `resource0`/`iomem` заради читання регістра; вписувати гіпотезу як факт. |
| D4 | Порядок: **спершу цей ADR, потім ABI v8→v9** у `wsm-target-contract`. v9 — реалізація задокументованого контракту, а не самостійна правка структур. | Оновлювати ABI окремо від архітектурного обґрунтування. |
| D5 | Відмова доступу — **зелений негативний свідок** з названим кроком, а не падіння інфраструктури. | Пом'якшувати гейт, щоб отримати green. |
| D6 | Кожне твердження має стан: `statically proven` / `runtime-proven` / `interpretation` / `string-only` / `UNPROVEN`. | Підміняти інтерпретацію виміром, а гіпотезу — свідком. |

D1 не винаходить нову capability: у `src/runtime.s` уже існують `wsm_pci_config_capability` (kind 0, nonce `0x150434954346`) і `wsm_mmio_capability` (kind 1, nonce `0x1A0495124347`), а cross-class reuse вже відкидається негативним QEMU-свідком. Цей ADR **формалізує межу**, а не додає механізм.

## 1. Why / Навіщо

Г0/G1-зріз у `gp107-nvidia-re` показав дві різні поведінки на одному пристрої `10de:1c82 @ 0000:01:00.0`:

- PCI config space читається і збігається з `NV_ESC_CARD_INFO` (BAR0 `0xee000000`);
- `resource0` як звичайний користувач не відкривається (`EACCES`), а будучи root відкривається, але `mmap(PROT_READ|MAP_SHARED)` дає `EINVAL`.

Отже «бачити адресу BAR» і «мапити апертуру» — різні повноваження з різними режимами відмови. Без явного розділення Lisp-машина легко перетворить інвентарний факт на хибне право доступу.

## 2. Evidence / Свідки

| Факт | Стан | Джерело |
|---|---|---|
| `10de:1c82`, BAR0 `0xee000000` з двох незалежних джерел, збіг | **runtime-proven** | `02_bar_identity.pas`: sysfs config + `NV_ESC_CARD_INFO`, маркер `CROSS-CHECK-OK` |
| `resource0` user → `EACCES` (13); root → open OK, mmap → `EINVAL` (22) | **runtime-proven** | гейт `scripts/test-pascal-probe.sh` і ручний `sudo` запуск |
| Причина `EINVAL` — exclusive-володіння BAR0 / iomem-конфлікт із драйвером `nvidia` | **interpretation** | `driver → /sys/bus/pci/drivers/nvidia`; прямо з ядра не перевірено |
| `0x137000A1` і маска `$FFF00000 → $137` | **string-only** | публічний коментар у `libdrm` `cl0080.h`; на цій машині регістр **не прочитано** |
| У інвентарі рядків `libcuda.so.580.196.11` немає `BOOT_0`, `PMC`, `NV2080_CTRL_CMD` | **statically proven (string inventory)** | REA/Ghidra 12.2, Evidence `ev_4668ff25…`, `ev_ec1aa014…`, `ev_514422e5…`; це не доведення про довільні байти ELF |
| У публічних headers R580 немає literals `NV2080_CTRL_CMD_MC_GET_ARCH_INFO` | **static search result** | пошук у `/usr/src/nvidia-580.196.11`; є лише коментарі `NV2080_CTRL_MC_ARCH_INFO_ARCHITECTURE_*` у `common/inc/nv_uvm_types.h`. Приватні RM-headers у цьому дереві відсутні |
| BOOT0 прочитано на hosted-машині | **UNPROVEN** | жодного позитивного свідка; див. два негативні вище |

## 3. What changes / Що змінюється

| Артефакт | Стан |
|---|---|
| `src/runtime.s`, `src/*.pas`, `scripts/*` | **не змінюються цим ADR** |
| `target-abi-pin.lisp`, `docs/TARGET-ABI.md`, `wsm-target-contract` | **не змінюються** до ратифікації ADR; v8 ще чинний, v9 — мета |
| `docs/ADR-007-*.md` | новий запис архітектурного рішення |
| `policy-enforcement.lisp` | нових політик у цьому коміті немає; чинні `mmio-*` лишаються |
| `gp107-nvidia-re` | research-репозиторій, не authority; свідки там лишаються свідками |

## 4. Форма контракту (концепція, не новий ABI)

| Властивість | `PciConfig` | `Mmio` |
|---|---|---|
| Тип | tagged `Word` з nonce | tagged `Word` з nonce |
| Параметри | `ctx`; читання: bus/dev/func/offset | `ctx`; читання: capability + offset |
| Calling convention | SysV x86-64: `RDI=ctx`, повернення в `RAX` | SysV x86-64: `RDI=ctx`, `RSI=cap`, `RDX=offset`, повернення в `RAX` |
| Allocation | немає; дескриптор обчислюється з константи | немає; регіон уже підготовлено у `wsm_mmio_region_*` |
| Memory layout | `(nonce<<16)|(instance<<3)|kind`, tag `110` | та сама схема, інші nonce/kind |
| Returned value | слово-дескриптор | слово-дескриптор або named condition `MMIO_ERR_PROVISIONING` |
| Права | config read тільки | MMIO read32 тільки для identity; write окремою політикою |

Стан володіння (`Exclusive`/`HostedDriver`/`Unknown`) поки **не закодований у v8**. Його кодування — робота ABI v9 (`wsm-target-contract`), і вона не виконується до ратифікації цього ADR. Тому таблиця вище — дизайн-намір, а не опис чинного біта в `runtime.s`.

## 5. Фаза RM-arch_info — окремий research-шлях

Пропозиція шукати архітектуру/ревізію через `NV_ESC_RM_CONTROL` (клас `0x2080`) приймається як **гіпотеза для окремої фази**, не як доведений факт:

1. Назва `NV2080_CTRL_CMD_MC_GET_ARCH_INFO` не знайдена ні в публічних headers R580, ні в REA-інвентарі рядків libcuda. Поки це не перевірено, писати `03_rm_arch_info.pas` як «доведений шлях» заборонено.
2. Легальний пошук: REA-перегляд `NV_ESC_RM_CONTROL` уlibcuda + публічні `ctrl2080*.h` + runtime-виклик кандидатів з реєстрацією cmd id і struct layout.
3. Позитивний результат фази 03 може колись дати **arch/implementation** через RM. Він **не перетворює** BOOT0 у прочитаний: це інший канал, і в таблиці доказів він має лишатися окремим рядком.
4. Прямий MMIO BOOT0 лишається суто за межею bare-metal/UEFI seam.

## 6. Fail-closed наслідок

Гейт `gp107-nvidia-re/scripts/test-pascal-probe.sh` перевіряє код після зрізу Pascal-коментарів: заборонені `PROT_WRITE`, `MAP_FIXED`, `O_RDWR`, `FpWrite`, `pwrite`. Негативні маркери `EACCES` (user) і `EINVAL` (root, ручний запуск) дають `G1-FAIL-CLOSED-OK`. Цей механізм гейта є взірцем для майбутніх capability-перевірок у `wsm-os-lisp`: заборона перевіряє **код**, а не текст пояснень.

## 7. Відкриті питання до власника

1. Чи ратифікувати ADR-007 owner-комітом (або рядком у `docs/decisions/OWNER-CONFIRMATIONS.lisp`), щоб зняти статус `PROPOSED`?
2. Чи кодувати стан володіння ресурсом (`Exclusive`/`HostedDriver`/`Unknown`) у v9 окремим полем, чи лишити його policy-рівнем без ABI-зміни?
3. Чи запускати фазу 03 (RM arch info) зараз, чи спершу закрити v8→v9 і лише потім повернутися до RM-дослідження?
4. Чи потрібен окремий `make gate-root` у `gp107-nvidia-re`, чи достатньо ручного sudo-свідка, як ти рекомендував?

## Українською: одне речення

PCI-config можна показувати як інвентар, але MMIO треба видавати окремою read-only capability з явним володінням; під живим драйвером NVIDIA BOOT0 лишається `UNPROVEN`, а гіпотезу `0x137000A1` не можна назвати фактом.
