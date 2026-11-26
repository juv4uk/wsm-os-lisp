# FPC toolchain probe: what actually happens on our target
*Проба інструментарію FPC: що насправді відбувається на нашій цілі*

**Дата**: 2026-11-26
**Статус**: EVIDENCE — вимір, не рішення. Обслуговує [ADR-006](../ADR-006-FPC-HOST-LANGUAGE.md) фазу **P0**.
**Задача**: `WSM-OS-FPC-TOOLCHAIN-PROBE`

---

## 1. Що перевірялося

Три питання, кожне окремо:

1. Чи збирає pinned FPC об'єктний файл під нашу ціль і чи експортує він потрібний символ?
2. Чи лінкується цей об'єкт нашим `src/linker.ld` без стороннього коду?
3. Скільки коштує «порожня» програма?

## 2. Умови

```text
FPC            3.2.2 (Debian fp-compiler-3.2.2 3.2.2+dfsg-20, amd64)
ціль           -Tlinux, x86_64
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

Це підтверджує: FPC дає звичайний ELF-об'єкт і дозволяє назвати символ так, як
його очікує наш ABI. Тобто технічної несумісності з нашим ланцюгом немає.

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

П'ять символів, і всі п'ять — хуки RTL, а не наш код. Кожна програма FPC
генерує таблиці `INITFINAL` і `FPC_THREADVARTABLES` і викликає ініціалізацію
юнітів; без RTL ці посилання нічим не закриваються.

### 3.3 Ціна «порожньої» програми

```text
$ size probe
   text    data     bss     dec     hex
 144592   39448    9496  193536   2f400
```

`program probe; begin end.` — близько **190 КБ**. Це не докір: саме цю цифру
FPC wiki має на увазі, коли каже, що embedded-підтримка «не та, де 50 КБ
overhead має значення». Тепер вона наша, а не цитата.

## 4. Що це означає для ADR-006

| Питання | Відповідь |
| --- | --- |
| Чи можна писати рівень 2 на FPC? | Так, компілятор працює на нашій цілі й дає потрібні символи |
| Чи можна взяти RTL «як є»? | Ні: він тягне ініціалізацію, фіналізацію й таблиці потокових змінних |
| Що треба написати самим? | Мінімальний RTL: `fpc_initializeunits`, `fpc_do_exit`, `INIT$`/`FINALIZE$`-сумісні заглушки, `THREADVARLIST` |
| Скільки це? | Невідомо, доки не зроблено P1 — і саме тому P1 окрема задача |

**P0 не зелений.** Він дав відповідь «ні, не без власного RTL», і ця відповідь
корисніша за оптимістичну: вона називає роботу до того, як вона почалася.

## 5. Що далі (P1)

Мінімальний Pascal-стаб, який:

1. не використовує `System` узагалі (`{$mode objfpc}` + `nostackframe` + власний `_start`),
   або замінює його власним `system.pp` — обрати треба на P1, з виміром;
2. лінкується нашим `linker.ld` без жодного undefined-символа;
3. приймає UEFI handoff і друкує `WSM-OS BOOT schema=1 arch=x86_64 status=ok`.

Критерій приймання P1: `nm -u` на фінальному об'єкті **порожній**, і транскрипт
QEMU збігається з наявним BOOT-рядком.

---

## Українською: одне речення

FPC 3.2.2 збирає об'єкт під нашу ціль і експортує потрібний символ, але будь-яка
програма вимагає п'яти RTL-хуків, яких у freestanding-лінкуванні немає, і
«порожня» програма важить ~190 КБ — тобто ціна власного RTL виміряна, а не
переказана з чужого FAQ.
