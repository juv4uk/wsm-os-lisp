# Freestanding Pascal-прототип: Linux-target object у UEFI-образі
*Freestanding Pascal prototype: a Linux-target object inside the UEFI image*

**Дата:** 2026-11-26  
**Статус:** **ЧАСТКОВЕ СВІДЧЕННЯ**, не завершення P1. Прототип показує, що вузький об'єкт FPC 3.2.2, зібраний із `-Tlinux`, можна включити до чинного x86-64 UEFI-образу й викликати через System V AMD64 ABI. Він **не** перевіряє `OS_TARGET=embedded`, не доводить сумісність embedded RTL і не завершує контракт P1.  
**Задачі:** `WSM-OS-FPC-KERNEL-SKELETON` (P1, відкрита); передумова — `WSM-OS-FPC-TOOLCHAIN-PROBE` / [#113](https://github.com/juv4uk/wsm-os-lisp/issues/113) (P0, відкрита).

---

## 1. Що саме показує прототип

| Твердження | Межа доказу |
| --- | --- |
| FPC 3.2.2 компілює `src/pascal_probe.pas` у ELF64 object | Компілятор запускається явно з `-Tlinux`; це **не** embedded target |
| Об'єкт можна включити до UEFI-образу з чинними `src/entry.s`, `src/runtime.s` і `src/linker.ld` | П'ять unresolved symbols задовольняються окремими no-op символами в `src/rtl_min.s`; це лінкерні satisfiers для цього зрізу, не реалізація RTL |
| Pascal-функція викликає `wsm_cons` і повертає tagged word | Доведений вузький виклик `wsm_entry(ctx)`; інші типи, unit services та Pascal runtime не доведені |
| QEMU виводить очікуваний BOOT + RESULT transcript | Скрипт порівнює нормалізовані рядки після вилучення CR, а не сирі байти з урахуванням усіх line endings |
| `nm -u` фінального ядра порожній | Це доводить, що всі символи фінального link мають визначення; не доводить, що no-op hooks безпечні для довільної програми |

Важлива різниця: `src/entry.s::_start` зберігає BootInfo, викликає асемблерний `wsm_boot_handoff`, готує `RuntimeContext` і лише потім викликає `wsm_entry(&runtime_context)`. Pascal-функція отримує **RuntimeContext pointer**, а не BootInfo. Валідація або розбір UEFI handoff у Pascal тут не реалізовані; негативні випадки відсутнього чи пошкодженого handoff цим гейтом не доводяться.

Поточний очікуваний transcript:

```text
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok
```

Файл `artifacts/nucleus-witness-pascal-entry-qemu-serial-transcript.txt` має той самий Git blob SHA, що й базовий `artifacts/qemu-serial-transcript.txt`. Гейт запускає QEMU та звіряє рядки з цим зафіксованим очікуванням. Це корисний parity-сигнал, але не самостійний доказ того, що Pascal вже обробляє UEFI handoff.

## 2. Компілятор і ABI — що насправді використано

`scripts/check-fpc-kernel-skeleton.sh`:

- вимагає FPC версії `3.2.2` (або явного `WSM_FPC_VERSION`);
- знаходить `ppcx64` та RTL units у каталозі `x86_64-linux`;
- компілює з `-Tlinux -O- -Xs- -CX -Cn`;
- асемблює `src/rtl_min.s`, зливає об'єкти через `ld -r`, а потім передає результат до чинного UEFI image builder;
- перевіряє `nm -u target/kernel-x86_64` і запускає bounded QEMU witness.

Отже, цей прототип використовує **Linux-target FPC 3.2.2**. Те, що його об'єкт виконується в нашому UEFI/QEMU образі, показує сумісність саме цього вузького машинного коду та виклику System V AMD64. Це не підміняє перевірку upstream FPC 3.3.1 `x86_64-embedded` з [#113](https://github.com/juv4uk/wsm-os-lisp).

Фрагмент Pascal:

```pascal
function wsm_cons(ctx: Pointer; car, cdr: TWord): TWord; cdecl;
  external name 'wsm_cons';

function wsm_entry(ctx: Pointer): TWord; public name 'wsm_entry';
begin
  Result := wsm_cons(ctx, SYMBOL_A, SYMBOL_B);
end;
```

На цій Linux x86-64 toolchain `cdecl` використовує System V AMD64: перші три цілочисельні аргументи проходять через `RDI`, `RSI`, `RDX`, результат — у `RAX`. Це збігається з наявним asm runtime ABI для цього конкретного прототипу. Переносити висновок на інший target або інший FPC ABI без окремого виміру не можна.

`SYMBOL_A` і `SYMBOL_B` у файлі — локальні test-fixture слова для двох symbol IDs. Це не новий реєстр семантики й не загальні конструктори значень; production-код не повинен копіювати ці значення замість споживання pinned target contract.

## 3. П'ять RTL hooks: визначені для лінкера, не реалізовані як сервіси

`src/rtl_min.s` визначає п'ять символів, на які посилається Linux-target object:

| Символ | Поточне визначення | Чого воно **не** забезпечує |
| --- | --- | --- |
| `fpc_initializeunits` | `ret` | не запускає ініціалізацію юнітів |
| `fpc_do_exit` | `ret` | не реалізує завершення програми чи процесу |
| `INIT$_$SYSTEM` | `ret` | не ініціалізує `System` |
| `FINALIZE$_$OBJPAS` | `ret` | не виконує фіналізацію `objpas` |
| `THREADVARLIST_$SYSTEM$indirect` | нульовий terminator | не підтримує threadvar |

У цьому fixture asm `_start` напряму викликає `wsm_entry`; він не запускає звичайний FPC program main/init/finalize lifecycle. Тому ці визначення задовольняють посилання лінкера, але не стають робочою реалізацією відповідних послуг. Зокрема, `fpc_do_exit: ret` **не можна** використовувати як загальну реалізацію виходу з програми. Будь-який новий шлях, який реально викликає ці hooks, потребує окремої реалізації та позитивних/негативних свідків. Не додавати нові no-op заглушки, щоб приховати невідомі unresolved symbols.

## 4. Чого прототип не доводить

- Не перевіряє `OS_TARGET=embedded` і не закриває P0.
- Не передає BootInfo у Pascal і не перевіряє відсутній/пошкоджений handoff на Pascal-межі.
- Не доводить, що Pascal безпечно запускає FPC initialization/finalization або threadvar lifecycle.
- Не реалізує рядки, I/O, винятки, власну купу, GC, driver policy, image loader чи REPL.
- Не доводить продуктивність або перевагу часу ітерації.
- Не скасовує `src/runtime.s`; на цьому зрізі асемблер і далі надає системний runtime.

## 5. Відтворення на поточному контрольному toolchain

```bash
sudo apt-get install -y --no-install-recommends \
  qemu-system-x86 ovmf mtools dosfstools gdisk binutils fp-compiler
bash scripts/check-fpc-kernel-skeleton.sh
```

Версія компілятора перевіряється скриптом; шляхи можна явно задати через `FPC_PPCX64` і `FPC_UNITS_DIR`. Workflow: `.github/workflows/fpc-kernel-skeleton.yml`.

## 6. Що потрібно для завершення P0 і P1

**P0 — embedded-target перевірка (#113):**

1. Отримати точний upstream `x86_64-embedded` archive, обчислити SHA-256 і звірити його з записаним pin/source commit.
2. Зібрати мінімальний Pascal object саме через embedded compiler, не через `-Tlinux`.
3. Зафіксувати object format, symbols, unresolved imports, startup/runtime dependencies, linker map і size.
4. Спробувати link із нашим `src/linker.ld`; кожну відсутню послугу класифікувати. Не підкладати no-op hook без доказу, що цей execution path його не викликає.
5. Зберегти bounded QEMU witness, якщо збірка/лінкування доходять до нього. До цього P0 лишається відкритим.

**P1 — Pascal kernel skeleton:**

1. Виконуватися лише після закриття P0; використовувати pinned embedded toolchain.
2. Чітко визначити, яку частину UEFI handoff отримує Pascal, і перевірити її межі.
3. Додати негативні свідки на відсутній та malformed handoff: названа ABI-condition, не тиша і не продовження з припущеним станом.
4. Вивести незмінний BOOT transcript і перевірити порожній undefined-symbol set фінального образу.
5. Лише тоді позначати P1 як завершений.

P2 після цього порівнює той самий вертикальний сценарій на Pascal та ASM+Lisp і вимірює цикл «правка → збірка → перевірка». Поточний Linux-target прототип — корисна базова проба, але не завершення P1.

---
