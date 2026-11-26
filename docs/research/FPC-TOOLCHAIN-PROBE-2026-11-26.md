# FPC 3.2.2 Linux-target control probe — not the embedded target
*Контрольна проба FPC 3.2.2 для Linux — не перевірка embedded-цілі*

**Дата**: 2026-11-26
**Статус**: CONTROL EVIDENCE — виміряно лише `-Tlinux`, не `OS_TARGET=embedded`. Це контрольний підексперимент P0, а не доказ сумісності або несумісності embedded RTL. Перевірка upstream `x86_64-embedded` відстежується в [#113](https://github.com/juv4uk/wsm-os-lisp/issues/113).
**Задача**: `WSM-OS-FPC-TOOLCHAIN-PROBE`

---

**Upstream embedded snapshot (перевірка каталогу/README 2026-11-26)**

Окремо перевірено конкретну upstream-публікацію `x86_64-embedded`; це не продовження Linux-проби вище.

| Поле | Спостережене значення |
| --- | --- |
| Архів | [FPC 3.3.1 x86_64-embedded](https://downloads.freepascal.org/fpc/snapshot/trunk/x86_64-embedded/fpc-3.3.1.x86_64-embedded.built.on.x86_64-linux.tar.gz) |
| Розмір у каталозі | 5.2 MB |
| Час у каталозі | 2026-11-26 13:57 UTC |
| Час генерації за README | 2026-11-26 13:56 UTC |
| Компілятор | `3.3.1-22025-ge3155f6ecc` |
| Команда збірки | `make singlezipinstall OS_TARGET=embedded CPU_TARGET=x86_64 SNAPSHOT=1 "" PP=ppcx64 CROSSOPT="-n -gl -vx " OPT=""` |
| Репозиторій джерел | `https://gitlab.com/freepascal.org/fpc/source.git` |
| Commit джерел | `e3155f6eccd98f003c33a620996786e83ac79cd1` |
| Commit build-репозиторію | `712d9f81225c1da6d5e5feb3922d71f18df33778` |

Первинний README: [README-fpc-3.3.1.x86_64-embedded.built.on.x86_64-linux](https://downloads.freepascal.org/fpc/snapshot/trunk/x86_64-embedded/README-fpc-3.3.1.x86_64-embedded.built.on.x86_64-linux).

**Межа доказу:** це підтверджує target triple, час і provenance snapshot. SHA-256 самого архіву ще не обчислено; архів у цьому середовищі не був отриманий локально, тому немає ані compiler run, ані object, link map, `nm -u`, розміру образу чи QEMU-транскрипту. Не підміняти ці відсутні результати README-метаданими.

FPC називає development snapshots непідтримуваними та попереджає, що вони можуть бути нестабільними: [офіційна сторінка Development](https://www.freepascal.org/develop.html). Тому цей exact snapshot є **дослідницьким інструментом P0**, а не новою стабільною toolchain-базою й не дозволом на production Pascal.

P0 лишається відкритим до відтворюваного завантаження з SHA-256, компіляції саме через `-Tembedded`, аналізу undefined symbols і перевірки лінкування з нашим `src/linker.ld`. Позитивний compile окремо не доводить UEFI startup або SENS parity.

---

## 1. Що перевірялося

Цей звіт фіксує лише контрольний експеримент із FPC 3.2.2 та `-Tlinux` на x86_64. Він **не** тестує `-Tembedded` і не перевіряє upstream snapshot `x86_64-embedded`.

Перевірені питання:

1. Чи компілює Linux-target FPC object і чи експортує названий символ?
2. Чи лінкується саме цей Linux-target object нашим `src/linker.ld` без Linux RTL?
3. Який розмір має порожня Linux-target програма?

Embedded-target перевірка — окреме завдання [#113](https://github.com/juv4uk/wsm-os-lisp/issues/113).

## 2. Умови

```text
FPC            3.2.2 (Debian fp-compiler-3.2.2 3.2.2+dfsg-20, amd64)
контрольна ціль  -Tlinux, x86_64 (не embedded)
прапорці       -O- -Xs- -CX -Fu<units>/rtl -Fu<units>/rtl-objpas
лінкер         GNU ld 2.40, скрипт src/linker.ld (наш, без libc)
```

Джерело програми — 10 рядків: одна глобальна змінна і одна експортована
функція з `public name 'wsm_probe_entry'`.

## 3. Результати

### 3.1 Об'єкт збирається, символ експортується

```text
$ nm probe.o | grep wsm_probe_entry
0000000000000000 T wsm_probe_entry
```

Це підтверджує лише те, що FPC 3.2.2 у Linux-target режимі створює ELF object і дозволяє експортувати названий символ. Це ще не доводить сумісності embedded ABI, UEFI handoff або цільового RTL.

### 3.2 Freestanding лінкування **не проходить**

```text
$ ld -T src/linker.ld -o probe_alone.elf probe.o
ld: warning: cannot find entry symbol _start; defaulting to 0000000000100000
ld: probe.o: in function `main':
probe.pas:(.text.n_main+0x5): undefined reference to `fpc_initializeunits'
probe.pas:(.text.n_main+0xa): undefined reference to `fpc_do_exit'
probe.o:(.data.n_INITFINAL+0x10): undefined reference to `INIT$_$SYSTEM'
probe.o:(.data.n_INITFINAL+0x28): undefined reference to `FINALIZE$_$OBJPAS'
probe.o:(.data.n_FPC_THREADVARTABLES+0x4): undefined reference to `THREADVARLIST_$SYSTEM$indirect'
```

П'ять символів у цьому конкретному Linux-target object — хуки Linux RTL, а не наш код. Цей результат не можна переносити на `OS_TARGET=embedded`: інша ціль може мати інший startup/RTL шлях.

### 3.3 Ціна «порожньої» програми

```text
$ size probe
   text    data     bss     dec     hex
 144592   39448    9496  193536   2f400
```

`program probe; begin end.` у цій конфігурації Linux-target має близько **190 КБ**. Це вимір Linux RTL, а не embedded footprint і не розмір майбутнього Pascal ядра. Публікація `Minimal RTL` стосується дуже малого runtime з overhead близько 50 КБ; вона не доводить відсутності embedded target.

## 4. Що це означає для ADR-006

| Питання | Відповідь |
| --- | --- |
| Чи компілює FPC 3.2.2 Linux-target об'єкт? | Так, і експортує потрібне ім'я символу; це не перевірка embedded target |
| Чи лінкується Linux-target object без його RTL? | Ні: цей конкретний object має п'ять unresolved Linux RTL hooks |
| Чи треба переписувати RTL для embedded target? | Ще невідомо; це перевіряє [#113](https://github.com/juv4uk/wsm-os-lisp/issues/113) на pinned `x86_64-embedded` snapshot |
| Чи є у upstream embedded target? | Так, існує FPC 3.3.1 `x86_64-embedded` snapshot; його UEFI/ABI сумісність з нашим образом ще не доведена |

**P0 не зелений для нашої embedded/UEFI цілі.** Цей контрольний підексперимент показав, що Linux-target object не лінкується без Linux RTL hooks. Він **не** доводить, що `x86_64-embedded` вимагає повного власного RTL. Цей висновок можливий лише після перевірки #113.

## 5. Що далі (P1)

Мінімальний Pascal-стаб, який:

1. не використовує `System` узагалі (`{$mode objfpc}` + `nostackframe` + власний `_start`),
   або замінює його власним `system.pp` — обрати треба на P1, з виміром;
2. лінкується нашим `linker.ld` без жодного undefined-символа;
3. приймає UEFI handoff і друкує `WSM-OS BOOT schema=1 arch=x86_64 status=ok`.

Перед P1 потрібно завершити embedded-target probe #113 і визначити мінімальний startup/link profile. Критерій P1: `nm -u` на фінальному об'єкті **порожній**, а QEMU-транскрипт збігається з наявним BOOT-рядком.

---

## Українською: одне речення

FPC 3.2.2 у режимі `-Tlinux` збирає ELF object, але цей Linux-target object не лінкується з нашим freestanding linker script без п'яти Linux RTL hooks; розмір порожньої Linux-target програми — близько 190 КБ. Це не вимір embedded footprint: перевірка upstream `x86_64-embedded` та її UEFI ABI сумісності відстежується в #113.
