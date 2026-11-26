# P2 parity matrix: two substrates, two scenarios, and where the cycle time actually goes
*P2 матриця паритету: два субстрати, два сценарії — і куди насправді йде час циклу*

**Дата**: 2026-11-26
**Статус**: **ЧАСТКОВЕ EVIDENCE — P2 не закрито**. У межах Linux-target контрольного зрізу доведено 4/4 клітинки й виміряно цикл на одній машині. Embedded-target і Pascal-side UEFI handoff негативні свідки ще відсутні; задача W3 лишається відкритою.
**Задача**: `WSM-OS-FPC-PARITY-VERTICAL-W3`
**Гейт**: `bash scripts/check-fpc-parity.sh`, CI `.github/workflows/fpc-parity.yml`

---

## 1. Матриця

Чотири клітинки звіряються з піненими транскриптами сценаріїв; скрипт додатково
порівнює фінальний `WSM-OS`-рядок ASM і Pascal для кожного сценарію. Для value
зараз використовується `artifacts/nucleus-witness-pascal-entry-qemu-serial-transcript.txt`.
Цей файл нині має той самий blob SHA, що й ASM baseline
`artifacts/qemu-serial-transcript.txt`, але P2 gate не перевіряє саму рівність цих
двох файлів. Це pin-integrity gap: повний лог кожної клітинки звіряється з pin,
але canonical ASM ownership value transcript ще не закріплено механічно.

| Сценарій | Асемблер | Pascal | Транскрипт |
| --- | --- | --- | --- |
| значення | `artifacts/fixture.s` | `src/pascal_probe.pas` | `WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok` |
| названа відмова | `artifacts/nucleus-witness-alloc-oom-fixture.s` | `src/pascal_probe_oom.pas` | `WSM-OS CONDITION schema=1 kind=OOM source=0 value=0` |

Другий рядок — важливіший за перший. Успішний шлях доводить, що ABI збігається;
**шлях відмови** доводить, що обидва субстрати однаково доводять вичерпання
арени до тієї самої названої умови, а не до різних поведінок: Pascal не має
власного «ну, тоді поверну nil».

```text
CELL asm    value  build= 2912ms boot=12475ms  WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok
CELL asm    oom    build= 2769ms boot=12979ms  WSM-OS CONDITION schema=1 kind=OOM source=0 value=0
CELL pascal value  build= 3059ms boot=12345ms  WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok
CELL pascal oom    build= 3545ms boot=12311ms  WSM-OS CONDITION schema=1 kind=OOM source=0 value=0
```

## 2. Вимір циклу — і неприємний висновок

Гейт міряє три фази окремо, бо зведення їх в одне число ховає саме те, що
треба знати:

| Фаза | asm | Pascal | Кому належить |
| --- | --- | --- | --- |
| **COMPILE** | 102 мс (`as --64`) | 277 мс (`ppcx64 -Cn`) | мові |
| **BUILD** (образ) | ~3.0 с | ~3.0 с | `sgdisk`/`mkfs`/`mcopy`/`dd` |
| **BOOT** (QEMU + перевірка) | ~12.4 с | ~12.4 с | OVMF + TCG |
| **Разом** | ~15.6 с | ~15.7 с | |

Тобто **мова дає 175 мс із 15 600 — близько 1%**. «FPC компілює за секунди →
швидша ітерація» правдиве в абсолюті (277 мс проти 102 мс) і майже нічого не
важить у циклі, бо 98% циклу — це збірка образу й емульоване завантаження.

Це не аргумент проти FPC. Це аргумент проти того, щоб **вимірювати мову**, коли
вузьке місце в іншому місці. Практичний висновок: якщо цикл справді болить,
оптимізувати треба verify-шлях (довше живе завантажене ядро, швидший boot,
менший образ), а не міняти компілятор.

## 3. Чого цей вимір не доводить

- **Одна машина, TCG-емуляція, три повтори.** На реальному залізі boot буде
  іншим — і саме тоді частка компіляції зросте.
- **Міряли крихітну програму.** У кодовій базі на тисячі рядків `ppcx64` стане
  помітним; тут він не міг.
- **Не міряли час людини.** Обов'язок з `wsm-lazarus/METHODOLOGY.md` лишається
  відкритим: джоулі на цикл і час розробника не виміряні.
- **Не міряли енергію.** RAPL-лінія не підключена до цього гейта.

## 4. Що це змінює в ADR-006

Вимір не змінює архітектурного рішення й не закриває P2. Він частково перевіряє лише аргумент про compile time: у цьому вузькому сценарії мова дає близько 1% циклу, тож вузьке місце — образ і verify path. Повне W3 acceptance залишається відкритим до embedded-target і Pascal-side handoff-свідків.

## 5. Відтворення

```bash
sudo apt-get install -y --no-install-recommends \
  qemu-system-x86 ovmf mtools dosfstools gdisk binutils fp-compiler
WSM_P2_REPEATS=3 bash scripts/check-fpc-parity.sh
```

`WSM_P2_REPEATS` задає кількість повторів; медіани рахуються з `target/fpc-parity/cycle.tsv`
і `compile.tsv`, тобто з сирих чисел, а не з округлених.

---

## Українською: одне речення

Асемблер і Pascal у чотирьох клітинках Linux-target прототипу дають однакові `WSM-OS`-рядки після нормалізації CR; вимір циклу показав близько 1% compile time (277 мс проти ~15.6 с образу й завантаження). Це часткове свідчення, а не закриття P2 чи доказ `x86_64-embedded`.
