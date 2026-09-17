# MMIO MUTATION + BOUNDED-POLL EVIDENCE / СВІДОК МУТАЦІЙ ТА ОБМЕЖЕНОГО ОПИТУВАННЯ MMIO

**Статус (Status):** ПІДТВЕРДЖЕНО (CONFIRMED) на канонічному шляху pure-ASM
**Репозиторій:** `wsm-os-lisp`
**Задача:** issue #40, DEVICE-CAP-VERTICAL-1
**Дата фіксації:** 2026-09-17

---

## 1. Проблема / Problem

До [ADR-004](ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md) Rust-ядро друкувало
структуровану умову:

```text
WSM-OS CONDITION schema=1 kind=ABI source=1296649992 value=14998298004509163542
```

Чистий ASM-шлях (`src/entry.s`) друкував лише:

```text
WSM-OS PANIC schema=1 status=error
```

Наслідок: **device/ABI-збій було неможливо відрізнити від Lisp-семантичного
збою**, а мутаційних свідків (хибна можливість, вихід за межі, відсутнє
відображення) на канонічному шляху не існувало.

Before ADR-004 the Rust kernel printed a structured condition. The pure-ASM path
printed only a uniform PANIC line, so a device/ABI failure was indistinguishable
from a Lisp semantic failure, and the canonical path had no mutation witnesses.

---

## 2. Зміна / Change

1. `src/entry.s::kernel_failure` тепер друкує **структуровану умову**:

   ```text
   WSM-OS CONDITION schema=1 kind=<NAME> source=<code> value=<word>
   ```

   `kind` — закрита назва (OOM/TYPE/SYMBOL/ABI/OVERFLOW/UNKNOWN); `source` і
   `value` — десяткові. Вихід лишається `0x12` → shell 37.

2. `src/runtime.s`: додано `wsm_fail_src(ctx, kind, source, value)`. Старий
   `wsm_fail(ctx, kind, value)` делегує йому з `source=0` (Lisp-семантичні
   умови), тож device/ABI-збої отримують явний код джерела.

3. Коди джерел MMIO (портовано з pre-ADR-004 ядра, commit `7b66ca8`):

   | Код | Значення | Напрям |
   |---:|---|---|
   | `0x4D494F01` = 1296649985 | decode_fixnum | read |
   | `0x4D494F02` = 1296649986 | capability/bounds/alignment | read |
   | `0x4D494F03` = 1296649987 | not provisioned | read |
   | `0x4D494F04` = 1296649988 | decode_fixnum | write |
   | `0x4D494F05` = 1296649989 | capability/bounds/alignment | write |
   | `0x4D494F06` = 1296649990 | not provisioned | write |
   | `0x4D494F07` = 1296649991 | mapping unavailable | read |
   | `0x4D494F08` = 1296649992 | mapping unavailable | write |
   | `0x4D494F09` = 1296649993 | address overflow | read |
   | `0x4D494F0A` = 1296649994 | address overflow | write |
   | `0x4D494F00` = 1296649984 | **pure-ASM-only**: fail-closed provision | нейтральний |

4. `.Ldecode_check_mmio_cap` розрізняє: валідна база (≥1), хибна ідентичність
   (`0`, tag/nonce mismatch) і `-1` (регіон не провізійовано). Завдяки цьому
   read/write повідомляють різні коди `not provisioned`.

5. Тестовий гачок `WSM_OS_FORCE_NO_PHYS_MAP=1` (лише через `as --defsym`,
   ніколи в production) відтворює стан "завантажувач не надав мапінг".

---

## 3. Мутаційні свідки / Mutation witnesses

Гейт `scripts/check-mmio-mutation-fail-closed.sh` (канонічний pure-ASM шлях):

| Мутація | Фікстура | Пристрій | Очікувана умова |
|---|---|---:|---|
| Вихід за межі, читання | `d4-mmio-bounds-read` | так | `source=1296649986` |
| Вихід за межі, запис | `d5-mmio-bounds-write` | так | `source=1296649989` |
| Хибна можливість (PCI cap як MMIO) | `d6-mmio-wrong-capability` | так | `source=1296649989` |
| Провізіювання недоступне (немає пристрою) | `d4-mmio-bounds-read` | ні | `source=1296649984 value=6` |
| Мапінг завантажувача відсутній (forced) | `d4-mmio-bounds-read` | так | `source=1296649984 value=2` |

Кожен очікуваний транскрипт містить **лише** `BOOT` + `CONDITION`; гейт
додатково доводить, що рядок `WSM-OS RESULT ... status=ok` відсутній, тобто
**жоден volatile-доступ не відбувся** (fail-closed *до* доступу).

---

## 4. Обмежене опитування / Bounded poll

Гейт `scripts/check-mmio-bounded-poll.sh` доводить політику пристрою в Lisp:

| Фікстура | Поведінка | Результат |
|---|---|---|
| `d7-virtio-blk-ack-poll` | запис ACKNOWLEDGE, опитування до підтвердження | `value=t` |
| `d8-virtio-blk-never-ready` | опитування поля, яке ніколи не готове | `value=nil` (детерміновано) |

Negative witness проти нескінченного циклу структурний: `run-qemu-uefi.sh`
повертає 124 на QEMU-таймауті, що провалює гейт. `d8` завершується за
скінченний бюджет (64 ітерації) і дає явний канонічний результат `nil`, а не
зависання і не пошкодження Lisp-семантики.

---

## 4a. Розрізнення семантичного та пристроєвого збою / Semantic vs device

Гейт `scripts/check-condition-distinguishability.sh` доводить, що та сама
структурована умова розрізняє два класи машинно-перевірним чином:

| Клас | Фікстура | Умова |
|---|---|---|
| Lisp-семантичний | `d9-lisp-type-failure` | `kind=TYPE source=0 value=91` |
| Device/ABI | `d4-mmio-bounds-read` | `kind=ABI source=1296649986` |

`source=0` (немає коду субстрату) проти ненульового коду пристрою — і є
машинний критерій розрізнення. `d9` — це `(car 11)`: типова помилка над
fixnum.

**Виявлений і виправлений дефект (RED → GREEN).** До виправлення семантичний
збій повідомляв `value=2` (сам код `ERR_TYPE`) замість слова-порушника. Причина:
у `.Lcar_type_err`/`.Lcdr_type_err`/`.Lclosure_type_err` та їхніх ABI-варіантах
порядок був `movl $ERR_TYPE, %esi` **до** `movq %rsi, %rdx`, тож `%rsi`
(слово-порушник) уже був перезаписаний кодом помилки. Порядок виправлено на
`movq %rsi, %rdx` → `movl $ERR_*`. Тепер `(car 11)` дає `value=91` (fixnum 11 =
`11<<3|3`). Гейт фіксує очікуване `value=91`, тож регресія не пройде мовчки.

---

## 5. RED-доказ / Red evidence

До цієї зміни на канонічному шляху:
- клас збою був невидимий (усі збої — один рядок `PANIC`);
- не існувало жодного гейта, що доводив би fail-closed мутацій.

Гейти побудовані так, що проходять лише за наявності структурованої умови
конкретного коду; відсутність `RESULT` у транскрипті — доказ відсутності
volatile-доступу.

---

## 6. Межі та чесні розбіжності / Limits and honest divergence

- **Провізіювання vs. доступ:** pure-ASM перевіряє мапінг **під час
  провізіювання** (page walk), а не при кожному доступі. Тому для "мапінг
  відсутній" код джерела — `0x4D494F00` зі значенням-сентинелем (`2` або `5`),
  а не legacy-коди `0x4D494F07/08` (які лишаються зарезервованими для
  per-access трансляції). Це свідома розбіжність, а не мовчазна зміна.
- **Сумісність кодів:** read-коди `0x…02` і write-коди `0x…05` історично
  об'єднували "хибна можливість" і "вихід за межі". Гейти тому розрізняють
  мутації за фікстурою та відсутністю volatile-доступу, а не лише за кодом.
- **Що не зроблено:** legacy Rust-транскрипт `d3` лишається історичним (див.
  `docs/LEGACY-PRE-ADR004-SCRIPTS.md`); тут його намір перевірено наново на
  чистому ASM через `d6`.

---

## 7. Висновок / Conclusion

- `CONFIRMED`: чистий ASM-шлях повідомляє структуровану умову з кодом джерела;
- `CONFIRMED`: device/ABI-збій відрізняється від Lisp-семантичного (`kind`);
- `CONFIRMED`: усі 5 мутацій fail-closed **до** volatile-доступу;
- `CONFIRMED`: опитування пристрою має скінченний бюджет; never-ready дає
  детермінований `nil`;
- `CONFIRMED`: семантичний збій (`kind=TYPE source=0`) машинно відрізняється
  від пристроєвого (`kind=ABI source=<code>`); дефект `offending_value`
  виправлено;
- 14/14 CI-гейтів зелені локально.
