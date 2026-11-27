# Перевикористання коду з wsm-lazarus

**Зафіксоване джерело:** `external/wsm-lazarus`  
**Commit:** `f5f795ce095f301e987d74aed57948d1bc4e137c`  
**Ліцензія:** власний license notice «ВОЛЬНІСТЬ» (не MIT)

## Кандидати на пряме перевикористання

| Файл / компонент | Потенційне застосування | Рішення |
|---|---|---|
| `src/wsm.domain.pas` | Точні доменні координати, атомарне завантаження таблиці, повна структурна перевірка | Переносити після адаптації reader і таблиць під SENS Contract 12.0; не копіювати старі припущення про D1–D10 |
| `src/wsm.source.pas` | Джерельний reader та структурні вузли | Перевірити залежності й контракт; можливе пряме копіювання як host-механізму після тестів |
| `scripts/check-pin.sh` | Fail-closed перевірка gitlink, manifest і точного набору джерел | Уже використано як зразок для `scripts/check-language-policy.sh` |
| `scripts/iteration/measure.py` | Відтворюваний benchmark runner, raw samples, P50/P90, compiler provenance | Не копіювати цілком: він прив'язаний до Lazarus build/test/energy scripts; повторно використати перевірені алгоритми й контракт вимірювання |
| `docs/iteration-measurement.uk.md` та `docs/chas-iteratsii.uk.md` | Методологія вимірювання повного циклу | Перевикористовувати методологію, не чужі результати як результати цього репозиторію |

## Не підключати без міграції

- `src/wsm.registry.pas` — використовує `TSid8`; Contract 12.0 забороняє SID8 як активну семантичну/reader/compiler/evaluator основу.
- `src/wsm.eval.pas` — evaluator dispatch побудований на `TSid8`; його trampoline, lexical/global environment і тестові ідеї можна переносити окремо, але dispatch треба перевести на точні домен-кваліфіковані ідентичності Contract 12.0.
- `external/sens` всередині Lazarus — його pin відповідає Contract 9.0 і не є authority для `wsm-os-lisp`.

## Правило перенесення

Копіювати готовий код напряму дозволено. При перенесенні зберігати повний license notice «ВОЛЬНІСТЬ», авторство, upstream commit, локальні зміни та тести. Якщо модуль вимагає змін, зберігати upstream-оригінал окремо від адаптованої реалізації або фіксувати diff у документації. Не переписувати перевірений механізм без вимірюваної причини.


## CI-перевірка

`check-language-policy.sh` перевіряє відсутність мовного denylist, відповідність `production-languages unrestricted` і точну рівність gitlink/manifest. `check-gate-budget.sh` запускає цей самий gate у швидкому локальному наборі, а основний workflow запускає його окремим кроком.
