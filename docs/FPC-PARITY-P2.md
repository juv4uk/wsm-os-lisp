# P2 parity matrix: two substrates, two scenarios, and where the cycle time actually goes
*P2 матриця паритету: два субстрати, два сценарії — і куди насправді йде час циклу*

**Дата**: 2026-11-26
**Статус**: **ЧАСТКОВЕ EVIDENCE — P2 не закрито**. P0/P1 embedded witnesses pass; the three-repeat embedded W3 run passes 4/4 cells and pin identity. Only physical i5-6400 measurement and energy/human-time evidence remain open.
**Задача**: `WSM-OS-FPC-PARITY-VERTICAL-W3`
**Гейт**: `bash scripts/check-fpc-embedded-parity.sh` after `bash scripts/probe-fpc-embedded.sh`; CI `.github/workflows/fpc-parity.yml`

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

### Перевірка ідентичності пінів

Два піни для `value`-сценарію (`artifacts/qemu-serial-transcript.txt` для
асемблера і `artifacts/nucleus-witness-pascal-entry-qemu-serial-transcript.txt`
для Pascal) існують тому, що субстрати пінилися незалежно. Сам по собі це
слабке місце: якщо відредагувати один і не відредагувати другий, «паритет» тихо
стане двома різними очікуваннями, які просто схожі.

Тому гейт перевіряє їхню ідентичність явно (`cmp -s`) і падає на розбіжності:

```text
PIN-IDENTITY-PASS: artifacts/qemu-serial-transcript.txt ==
                   artifacts/nucleus-witness-pascal-entry-qemu-serial-transcript.txt (byte-identical)
```

Перевірено і в зворотний бік: дописаний рядок в один пін дає
`FPC-PARITY-FAIL: value pins diverged` до того, як почнеться будь-яка збірка.

Порівняння субстратів теж посилено: звіряються **всі** рядки `WSM-OS`, а не лише
останній — інакше різниця в проміжному рядку пройшла б непоміченою.

Вимір не змінює архітектурного рішення й не закриває P2. Він частково перевіряє лише аргумент про compile time: у цьому вузькому сценарії мова дає близько 1% циклу, тож вузьке місце — образ і verify path. Повне W3 acceptance залишається відкритим до embedded-target і Pascal-side handoff-свідків.

## 5. Відтворення

```bash
sudo apt-get install -y --no-install-recommends \
  qemu-system-x86 ovmf mtools dosfstools gdisk binutils curl python3
bash scripts/probe-fpc-embedded.sh
WSM_P2_REPEATS=3 bash scripts/check-fpc-embedded-parity.sh
```

`WSM_P2_REPEATS` задає кількість повторів; медіани рахуються з `target/fpc-parity/cycle.tsv`
і `compile.tsv`, тобто з сирих чисел, а не з округлених.

---

## Українською: одне речення

Linux-target контроль історично дав 4/4; новий embedded-target W3 smoke run також дав 4/4 і byte-identical value pins. Це ще не закриває P2: потрібні три повтори й фізичний замір на i5-6400.


---

## 6. Embedded-target W3 gate — 2026-11-27

**Статус:** триразовий embedded CI run #46074055427 завершився SUCCESS; 12/12 клітинок та canonical pin identity PASS. Linux-target вимір вище лишається історичним control і не підміняє embedded результат. Старий `scripts/check-fpc-parity.sh` задекларований як legacy у `policy-enforcement.lisp`; active acceptance path — embedded workflow.

`scripts/check-fpc-embedded-parity.sh` використовує checksum-pinned FPC 3.3.1 `x86_64-embedded` toolchain, встановлену `scripts/probe-fpc-embedded.sh`. Обидва Pascal сценарії — окремі `unit` модулі:
- value: `src/pascal_probe.pas`;
- named OOM: `src/pascal_probe_oom.pas`.

Для обох об'єктів очікується рівно один зовнішній символ — Assembly `wsm_cons`. Жоден FPC PROGRAM startup hook і жоден `rtl_min.s` no-op stub не лінкується.

Чотири клітини на кожен повтор:
1. ASM value;
2. ASM named OOM;
3. embedded Pascal value;
4. embedded Pascal named OOM.

Гейт механічно перевіряє:
- byte-identical identity між ASM value transcript pin і Pascal value pin до будь-якої збірки;
- кожен повний QEMU serial transcript проти відповідного pin;
- усі рядки `WSM-OS` між ASM і Pascal для value та OOM;
- порожній `nm -u` у фінальному Pascal kernel;
- compile, image-build і QEMU+verify час окремо, із сирими TSV, SHA-256 образів і host profile.

Триразовий результат (12/12 клітинок): canonical value pins byte-identical; value та OOM дали однакові повні `WSM-OS` рядки. Медіани на GitHub-hosted runner:
- `COMPILE`: asm 13 ms / Pascal 31 ms;
- `BUILD`: asm 1173 ms / Pascal 1197 ms;
- `BOOT+verify`: asm 1978 ms / Pascal 2018 ms.

Артефакт [15233758284](https://github.com/juv4uk/wsm-os-lisp/actions/runs/46074055427/artifacts/15233758284). `host-profile.txt` підтверджує runner: AMD EPYC 9V74, 4 vCPU, Ubuntu 26.04.1, 15 GiB RAM, QEMU 10.2.1. Це не твій i5-6400 і не GPU benchmark.

Цей результат закриває повторюваний embedded W3 smoke/parity gate для вузького value/OOM зрізу. P2 як ширша production-оцінка не закривається: фізичний замір на i5-6400, RAPL energy, людський час редагування та ширший SENS runtime parity залишаються відкритими.

The legacy declaration is intentionally narrow: it preserves the old Linux-target control runner for reproducing archived numbers, but does not permit it to serve as the active W3 acceptance gate.

## 7. Замір на локальному хості (WSL/Linux)

Для вимірювання циклу на власному CPU виконай у WSL/Linux з каталогу репозиторію:

```sh
sudo apt-get update
sudo apt-get install -y qemu-system-x86 ovmf mtools dosfstools gdisk binutils curl python3
bash scripts/probe-fpc-embedded.sh
WSM_P2_REPEATS=5 bash scripts/check-fpc-embedded-parity.sh
```

Артефакт `target/fpc-embedded-parity/host-profile.txt` фіксує CPU, ОС, пам'ять, QEMU та FPC; `compile.tsv` і `cycle.tsv` містять сирі заміри. Передай ці файли разом із serial logs та SHA-256 образів для порівняння з CI. Це вимір часу розробницького циклу (компіляція, створення образу, TCG/OVMF boot і перевірка transcript), **не** GPU benchmark і не вимір швидкодії GTX 1050 Ti. QEMU тут працює через TCG і навантажує CPU.
