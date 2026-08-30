# Lisp-machine features worth carrying into wsm-os

**Research date:** 2026-08-29  
**Status:** design input, not an implementation contract  
**Scope:** historical manuals, current implementations, and practitioner
discussions; no third-party source code copied

## Executive conclusion

The important property of a Lisp machine was not merely “an OS written in
Lisp” or a special CPU. It was the short, inspectable feedback loop across the
whole system:

```text
named definition
  -> compile one definition
  -> install it in the running world
  -> inspect live objects and callers
  -> encounter a structured condition
  -> repair/restart without discarding the computation
```

For `wsm-os`, the best near-term lesson is therefore **metadata and recovery
before GUI and drivers**. The current compiler-first route is correct: preserve
definition identity, source locations, object identity, structured failure and
deterministic snapshots while the system is still small. A custom filesystem,
window system, GC, scheduler or microcoded CPU should not enter v0.1.

## Evidence boundary

Sources have different authority:

| Class | Use here |
|---|---|
| Symbolics/MIT manuals | Primary evidence for historical mechanisms |
| Mezzano repository | Primary evidence for a current open Lisp OS |
| Practitioner forum reports | Experience reports and design leads, not contracts |
| Our repositories | Authority only for what the current ecosystem implements |

Forum enthusiasm is not proof that an old mechanism is efficient or safe on
modern hardware. Conversely, the absence of a modern commercial Lisp machine
does not show that its interaction model lacked value.

## 1. Definition-centric incremental compilation

### Historical mechanism

Genera operated on individual named definitions rather than treating the file
as the smallest compilation unit. The compiler/editor maintained definition
and caller information; a programmer could compile one function, install it,
and immediately test it. A practitioner describing Open Genera highlights the
same per-function sub-second edit/compile/load loop.

### What we already have

- `my-lisp` has parser/evaluator sessions, FASL parse snapshots and LSP symbol
  discovery.
- CML has a backend-neutral IR and deterministic target emitters.
- The swarm already records content identity, commits and evidence.

### Adopt

Make the future WSM image format definition-centric:

```text
definition-id
source-content-id
contract-version
code-range
literal/symbol table
source map
callers/dependencies
```

Do not implement hot replacement yet. First require CML to preserve this
metadata beside each emitted function. Hot replacement becomes safe only after
calling convention, closure environment and active-frame rules are explicit.

**Priority:** high, after first QEMU parity.  
**Why:** difficult to retrofit after code addresses and images become opaque.

## 2. Conditions, restarts and repairable execution

### Historical mechanism

Genera used a condition system throughout the OS and applications. The
debugger could inspect frames and values, continue using a provided restart,
return a replacement value, alter an argument and reinvoke a function, or edit
and recompile before retrying. The Symbolics debugger manual groups commands
around stack inspection, continuation, breakpoints and source/code display.

### Adopt in layers

1. Keep the current small numeric `wsm_fail` ABI for boot evidence.
2. Add a structured failure record later:

   ```text
   condition-kind
   operation
   offending-values
   source-definition-id
   source-span
   available-restart-ids
   ```

3. Initially support only deterministic restarts such as `abort-task`,
   `use-value`, and `retry-definition`.
4. A restart is an explicit continuation capability, not an arbitrary jump to
   a stale stack address.

This fits the project’s epistemic discipline: an error should carry why the
runtime believes it failed and what transitions are actually permitted.

**Priority:** high design seam; implementation after stack-frame metadata.  
**Do not do now:** pretend contract-3.0 `ErrorKind` already implies resumable
conditions.

## 3. A self-revealing system and live object inspector

### Historical mechanism

Genera described itself as “self-revealing”: status, source, callers, object
slots, processes and memory regions were inspectable symbolically. The
Inspector showed named slots rather than raw addresses. Practitioners remember
screen output as live presentations connected to the underlying objects.

### Adopt

Before a graphical inspector, define a serial/IPC inspection protocol:

```text
(inspect value-id)
(describe-definition definition-id)
(backtrace task-id)
(heap-summary)
(disassemble definition-id)
```

Responses must contain stable IDs, type tags and bounded fields. Raw pointers
may be diagnostic fields but never durable identities. The same protocol can
serve serial QEMU, the semantic oracle, LSP and a later Tauri presentation UI.

This is the strongest bridge to `my-idea`: the GUI should present runtime
objects returned by one inspection protocol, not reimplement runtime
semantics.

**Priority:** high after M4; text/serial first, Tauri later.

## 4. Presentation-based UI: output retains meaning

### Historical mechanism

Dynamic Windows/CLIM presentations associated displayed text or graphics with
typed objects and applicable commands. Forum accounts describe directory
entries and other output as directly inspectable/actionable objects rather
than dead terminal text.

### Adopt as a protocol, not a window system

Represent observable output as:

```text
presentation-id
kind
canonical-text
object-id
allowed-actions
provenance
```

The serial renderer may print only `canonical-text`; Tauri can make the same
record interactive. This reuses the ecosystem’s claim/evidence/provenance
work and prevents GUI-specific semantics.

**Priority:** medium.  
**Do not do now:** build a custom compositor or port CLIM before a stable
inspection record exists.

## 5. World images and restartable state

### Historical mechanism

Genera’s “world” contained the initialized software environment and its Lisp
objects. Current discussion still identifies saving the state of running
programs as a defining attraction. Mezzano similarly builds and boots system
images.

### What not to confuse

- Current `core.my.fasl` is a source-hash-verified parser-output cache, not a
  live heap image.
- `world.my` is immutable knowledge/history state, not an OS memory dump.
- A RAM dump with host pointers is not a reproducible image.

### Adopt

Design a future logical image as relocatable sections:

```text
header + contract SHAs
interned symbols
immutable values
definitions/code metadata
mutable heap graph
roots
capability rebind requests
content digest
```

External capabilities (disk, clock, network, GPU, devices) must be rebound on
restore and must never be serialized as trusted pointers. Keep source/FASL and
an event journal sufficient to reconstruct or audit the image.

**Priority:** medium/late, but record the identity rules early.

## 6. Stack groups and suspended computations

### Historical mechanism

The MIT Lisp Machine manual describes stack groups as Lisp objects containing
the control stack, environment bindings and resumption state, used for
coroutines, generators, scheduling and error handling.

### Adopt narrowly

Do not copy machine stacks. First create explicit scheduler tasks whose state
is described by managed frames:

```text
task-id
definition-id + instruction offset
value stack
environment/roots
state: runnable | waiting | condition | stopped
```

This can later support cooperative agents, debugger suspension and resumable
conditions. Native-stack capture should remain out of scope until the compiler
owns complete frame maps.

**Priority:** medium/late.  
**Risk:** a continuation holding raw stack/register addresses cannot survive
image relocation or code replacement.

## 7. Tagged values and hardware assistance

### Historical mechanism

Historical Lisp machines attached type information to words and used hardware
checks for types, bounds and memory safety. Architecture discussions also note
that modern stock CPUs can implement tagging efficiently, so special hardware
is not automatically the right first move.

### Our position

`wsm-os-target` already defines a 64-bit, low-three-bit tagged ABI. That is the
correct x86_64 starting point. Keep:

- one target contract as numeric authority;
- runtime range/ownership checks in addition to tag checks;
- deterministic symbol IDs;
- separate FPGA representation contracts;
- profiling evidence before AVX2/BMI2 or custom instructions.

Later, `fpga-lisp` can test which checks or primitives deserve hardware. The
x86 path should not imitate a historical microcoded CPU for aesthetic reasons.

**Priority:** already adopted at M0/M1.

## 8. Garbage collection and recoverable machine faults

### Evidence

Genera used an ephemeral collector; Mezzano reports generational collection,
weak objects, improved allocation visibility, unboxed slots and recoverable
stack-overflow/memory-fault handling. Practitioners also remember long GC
pauses as a real weakness of older machines.

### Adopt later, with metrics

The bounded bump heap remains correct for v0.1 because it makes exhaustion
deterministic. The next collector should be chosen only after traces show
allocation lifetime and root behavior. Reuse the existing `my-lisp` GC design
work instead of inventing another collector in `wsm-os`.

Required evidence before a generational collector:

- exact root maps for compiled frames;
- independent reachability oracle;
- stress mode and metamorphic “GC changes no observable semantics” tests;
- pause time, allocation rate and retained-size measurements;
- write-barrier contract if generations are introduced.

**Priority:** deferred; do not block first boot.

## 9. History as a first-class debugging primitive

### Historical mechanism

Genera maintained histories for commands, output, processes and windows. This
made investigation part of the environment rather than an afterthought.

### Adopt

Add bounded, typed event rings—not unrestricted logging—to the future runtime:

```text
sequence
event-kind
task/definition-id
logical timestamp
small payload
```

For deterministic tests, use logical counters rather than wall-clock time.
Expose the ring through the inspector and include it in failure evidence. The
existing swarm append-only journal demonstrates the value of replayable state,
but OS execution events require a separate bounded schema.

**Priority:** high for debugging, after serial output.

## 10. Files and versions

Forum discussion and manuals show that Lisp machines still used hierarchical
files and directories; versioned files were useful, but there is no evidence
that replacing the file abstraction itself was their central advantage.

For `wsm-os`:

- keep source and artifacts content-addressed and Git-backed on the host;
- use embedded read-only image sections first;
- add FAT only when physical boot requires it;
- do not invent a novel filesystem before the object/image model exists.

**Priority:** low.

## What the forums warn us not to do

1. **“Written in Lisp” does not remove modern hardware complexity.** USB,
   GPUs, networks and heterogeneous devices remain difficult.
2. **One address space is not automatically safe.** Modern isolation or
   capability boundaries still matter; tagged values alone do not authorize
   device access.
3. **Nostalgia is not a product requirement.** Open Genera is valuable for
   study, but practitioners caution that its old environment is not by itself
   practical for modern daily work.
4. **Special hardware is not automatically faster.** Caches, stock x86_64 and
   good compiler metadata may beat recreating historical microcode.
5. **A full Lisp OS is a long-lived ecosystem.** Mezzano’s thousands of
   commits and continuing hardware work are evidence against promising a
   complete OS from the first boot witness.

## Recommended roadmap impact

### Add to early architecture, without expanding v0.1

1. Explicit tail-position metadata and a target-level constant-stack proof.
2. CML definition IDs and source maps.
3. Runtime object IDs distinct from raw addresses.
4. Structured condition records while retaining the small boot error ABI.
5. A versioned serial inspector protocol.
6. A bounded logical event ring.

### Prototype after first QEMU oracle parity

7. A cross-substrate semantic trace using logical IDs rather than addresses.
8. A ratified immutable literal-space ownership model.
9. Definition-level replacement with active-frame safety rules.
10. Presentation records consumed by Tauri.
11. Relocatable logical image format with capability rebinding.
12. Managed task frames as the path toward stack groups/restarts.

### Keep deferred

10. Generational GC, GUI compositor, filesystem, networking, SMP, custom
    microcode and physical-device drivers.

## Sources

Primary and project sources:

- [Symbolics Genera Concepts](https://www.chai.uni-hamburg.de/~moeller/symbolics-info/genera/genera.html)
- [Symbolics Common Lisp Language Concepts](https://bitsavers.org/pdf/symbolics/software/genera_8/Symbolics_Common_Lisp_Language_Concepts.pdf)
- [Symbolics Program Development Utilities](https://bitsavers.org/pdf/symbolics/software/genera_8/Program_Development_Utilities.pdf)
- [Preliminary Lisp Machine Manual — stack groups](https://www.bitsavers.org/pdf/mit/cadr/Weinreb_Moon-Lisp_Machine_Manual_Jan_1979.pdf)
- [Mezzano repository and current feature record](https://github.com/froggey/Mezzano)

Practitioner discussions (anecdotal evidence, used as leads):

- [Running Open Genera 2.0 on Linux — Hacker News](https://news.ycombinator.com/item?id=39040697)
- [Genera and Interlisp-D differences — Hacker News](https://news.ycombinator.com/item?id=36713595)
- [Lisp Machine user experience — Reddit](https://www.reddit.com/r/lisp/comments/n94vl9/)
- [Why we need Lisp machines — Reddit](https://www.reddit.com/r/lisp/comments/tml3mb/)
- [Architecture of Lisp Machines discussion — Hacker News](https://news.ycombinator.com/item?id=27715043)
- [Modern Lisp OS discussion — Reddit](https://www.reddit.com/r/lisp/comments/1luw79t/)

---

# Особливості Lisp-машин, які варто перенести в wsm-os (український переклад)

**Дата дослідження:** 2026-08-29  
**Статус:** дизайн-вхід, не контракт реалізації  
**Межі:** історичні мануали, поточні реалізації та дискусії практиків; жоден
third-party код не скопійовано

## Виконавчий висновок

Важлива властивість Lisp-машини була не просто «ОС, написана на Lisp» чи
спеціальний CPU. Це був короткий, оглядовий цикл зворотного зв'язку через усю
систему:

```text
іменоване визначення
  -> скомпілювати одне визначення
  -> встановити його у живому світі
  -> оглянути живі об'єкти та викликачів
  -> зустріти структурований condition
  -> полагодити/перезапустити без відкидання обчислення
```

Для `wsm-os` найкращий найближчий урок — тому **метадані та відновлення перед
GUI й драйверами**. Поточний compiler-first шлях правильний: зберегти
ідентичність визначень, розташування джерел, ідентичність об'єктів,
структуровану відмову та детерміновані знімки, поки система ще мала. Власна
файлова система, віконна система, GC, планувальник чи мікрокодовий CPU не
мають входити у v0.1.

## Межа evidence

Джерела мають різну авторитетність:

| Клас | Використання тут |
|---|---|
| Мануали Symbolics/MIT | Основний evidence для історичних механізмів |
| Репозиторій Mezzano | Основний evidence для поточної відкритої Lisp ОС |
| Форумні звіти практиків | Звіти про досвід і дизайн-напрямки, не контракти |
| Наші репозиторії | Авторитетність лише щодо того, що екосистема реалізує зараз |

Форумний ентузіазм не доводить, що старий механізм ефективний чи безпечний на
сучасному залізі. І навпаки, відсутність сучасної комерційної Lisp-машини не
показує, що її інтерактивна модель не мала цінності.

## 1. Визначення-центрична інкрементальна компіляція

### Історичний механізм

Genera оперував окремими іменованими визначеннями, а не трактував файл як
найменшу одиницю компіляції. Компілятор/редактор підтримував інформацію про
визначення та викликачів; програміст міг скомпілювати одну функцію,
встановити її й одразу протестувати. Практик, що описує Open Genera, підкреслює
той самий підсекундний per-function цикл edit/compile/load.

### Що в нас уже є

- `my-lisp` має сесії parser/evaluator, FASL-знімки розбору та LSP-виявлення
  символів.
- CML має нейтральний до бекенду IR і детерміновані цільові емітери.
- Swarm уже записує ідентичність вмісту, коміти й evidence.

### Прийняти

Зробити майбутній формат WSM-образу визначення-центричним:

```text
definition-id
source-content-id
contract-version
code-range
literal/symbol table
source map
callers/dependencies
```

Не реалізовувати hot replacement ще. Спершу вимагати, щоб CML зберігав ці
метадані поруч із кожним виданим функцією. Hot replacement стане безпечним лише
після того, як calling convention, closure-середовище та правила активних
фреймів стануть явними.

**Пріоритет:** високий, після першого QEMU parity.  
**Чому:** важко дооснастити після того, як кодові адреси й образи стануть
непрозорими.

## 2. Conditions, restarts і відновлюване виконання

### Історичний механізм

Genera використовував систему condition по всій ОС і застосунках. Дебагер міг
оглядати фрейми та значення, продовжувати за допомогою наданого restart,
повертати замінне значення, змінювати аргумент і викликати функцію знову, або
редагувати й перекомпілювати перед повторною спробою. Мануал дебагера Symbolics
групує команди навколо огляду стеку, продовження, breakpoints і відображення
джерела/коду.

### Прийняти шарами

1. Зберегти поточний малий числовий ABI `wsm_fail` для boot-evidence.
2. Додати пізніше структурований запис відмови:

   ```text
   condition-kind
   operation
   offending-values
   source-definition-id
   source-span
   available-restart-ids
   ```

3. Спочатку підтримувати лише детерміновані restarts, як-от `abort-task`,
   `use-value` і `retry-definition`.
4. Restart — це явна спроможність продовження, а не довільний перехід на
   застарілу адресу стеку.

Це відповідає епістемічній дисципліні проекту: помилка має нести, чому рантайм
вірить, що це сталося, і які переходи насправді дозволені.

**Пріоритет:** високий дизайн-шов; реалізація після метаданих стек-фреймів.  
**Не робити зараз:** не вдавати, що `ErrorKind` contract-3.0 уже означає
відновлювані conditions.

## 3. Саморозкривна система та живий інспектор об'єктів

### Історичний механізм

Genera описувала себе як «self-revealing»: статус, джерело, викликачі, слоти
об'єктів, процеси та області пам'яті були оглядовими символічно. Інспектор
показував іменовані слоти, а не сирі адреси. Практики пам'ятають екранний вивід
як живі презентації, пов'язані з основними об'єктами.

### Прийняти

Перед графічним інспектором визначити serial/IPC-протокол огляду:

```text
(inspect value-id)
(describe-definition definition-id)
(backtrace task-id)
(heap-summary)
(disassemble definition-id)
```

Відповіді мають містити стабільні ID, type tags і обмежені поля. Сирі вказівники
можуть бути діагностичними полями, але ніколи тривалими ідентичностями. Той
самий протокол може слугувати serial QEMU, семантичному оракулу, LSP і пізнішій
Tauri-презентації.

Це найсильніший міст до `my-idea`: GUI має показувати об'єкти рантайму,
повернуті одним протоколом огляду, а не перереалізовувати семантику рантайму.

**Пріоритет:** високий після M4; text/serial спершу, Tauri пізніше.

## 4. Презентаційний UI: вивід зберігає значення

### Історичний механізм

Динамічні презентації Windows/CLIM пов'язували показаний текст або графіку з
типізованими об'єктами й доступними командами. Форумні звіти описують записи
директорій та інший вивід як прямо оглядові/дійові об'єкти, а не мертвий
термінальний текст.

### Прийняти як протокол, а не віконну систему

Показати спостережуваний вивід як:

```text
presentation-id
kind
canonical-text
object-id
allowed-actions
provenance
```

Серійний рендерер може друкувати лише `canonical-text`; Tauri може зробити той
самий запис інтерактивним. Це перевикористовує роботу екосистеми над
claim/evidence/provenance і запобігає GUI-специфічній семантиці.

**Пріоритет:** середній.  
**Не робити зараз:** не будувати власний композитор і не портувати CLIM, доки
не існує стабільного запису огляду.

## 5. World-образи та відновлюваний стан

### Історичний механізм

«World» Genera містив ініціалізоване програмне середовище та його Lisp-об'єкти.
Поточна дискусія досі називає збереження стану запущених програм визначальною
принадою. Mezzano аналогічно будує й завантажує системні образи.

### Що не плутати

- Поточний `core.my.fasl` — це кеш виводу parser'а, перевірений за source-hash,
  а не живе зображення купи.
- `world.my` — незмінний стан знань/історії, а не дамп пам'яті ОС.
- Дамп RAM із host-вказівниками — не відтворюваний образ.

### Прийняти

Спроєктувати майбутній логічний образ як релоковані секції:

```text
header + contract SHAs
interned symbols
immutable values
definitions/code metadata
mutable heap graph
roots
capability rebind requests
content digest
```

Зовнішні спроможності (disk, clock, network, GPU, пристрої) мають
переприв'язуватися при відновленні й ніколи не серіалізуватися як довірені
вказівники. Зберігати source/FASL і журнал подій, достатній для реконструкції
або аудиту образу.

**Пріоритет:** середній/пізній, але правила ідентичності записати рано.

## 6. Stack groups і призупинені обчислення

### Історичний механізм

Мануал MIT Lisp Machine описує stack groups як Lisp-об'єкти, що містять стек
керування, прив'язки середовища та стан відновлення, використовуються для
coroutines, генераторів, планування й обробки помилок.

### Прийняти вузько

Не копіювати машинні стеки. Спершу створити явні планувальні задачі, стан яких
описаний керованими фреймами:

```text
task-id
definition-id + instruction offset
value stack
environment/roots
state: runnable | waiting | condition | stopped
```

Це може пізніше підтримувати кооперативних агентів, призупинення в дебагері та
відновлювані conditions. Захоплення рідного стеку має лишатися поза межами,
доки компілятор не володіє повними картами фреймів.

**Пріоритет:** середній/пізній.  
**Ризик:** продовження, що тримає сирі адреси стеку/регістрів, не може
пережити релокацію образу чи заміну коду.

## 7. Tagged значення та апаратна допомога

### Історичний механізм

Історичні Lisp-машини кріпили інформацію про тип до слів і використовували
апаратні перевірки типів, меж і безпеки пам'яті. Архітектурні дискусії також
зазначають, що сучасні stock CPU можуть ефективно реалізовувати tagging, тож
спеціальне залізо не є автоматично правильним першим кроком.

### Наша позиція

`wsm-os-target` уже визначає 64-бітний ABI з tagging у нижніх трьох бітах. Це
правильна x86_64 точка старту. Зберегти:

- один цільовий контракт як числову авторитетність;
- перевірки меж/ownership рантайму на додачу до tag-перевірок;
- детерміновані ID символів;
- окремі контракти представлення FPGA;
- evidence профілювання перед AVX2/BMI2 чи власними інструкціями.

Пізніше `fpga-lisp` може тестувати, які перевірки чи примітиви заслуговують
апаратної реалізації. x86-шлях не повинен імітувати історичний мікрокодовий CPU
з естетичних міркувань.

**Пріоритет:** уже прийнято на M0/M1.

## 8. Збирання сміття та відновлювані відмови машини

### Evidence

Genera використовувала ефемерний колектор; Mezzano повідомляє про generational
збір, слабкі об'єкти, покращену видимість алокації, unboxed слоти та
відновлювану обробку stack-overflow/memory-fault. Практики також пам'ятають
довгі паузи GC як реальну слабкість старіших машин.

### Прийняти пізніше, з метриками

Обмежена bump-купа лишається правильною для v0.1, бо робить вичерпання
детермінованим. Наступний колектор слід обирати лише після того, як трасування
покажуть час життя алокацій і поведінку коренів. Перевикористати наявну роботу
над дизайном GC `my-lisp` замість винаходу ще одного колектора в `wsm-os`.

Необхідний evidence перед generational колектором:

- точні root maps для скомпільованих фреймів;
- незалежний оракул досяжності;
- stress-режим і метаморфічні тести «GC не змінює спостережувану семантику»;
- вимірювання часу паузи, швидкості алокації та утриманого розміру;
- контракт write-barrier, якщо вводяться покоління.

**Пріоритет:** відкладено; не блокувати перший boot.

## 9. Історія як першокласний примітив налагодження

### Історичний механізм

Genera підтримувала історії команд, виводу, процесів і вікон. Це робило
розслідування частиною середовища, а не запізнілою думкою.

### Прийняти

Додати обмежені, типізовані кільця подій — не необмежене журналювання — до
майбутнього рантайму:

```text
sequence
event-kind
task/definition-id
logical timestamp
small payload
```

Для детермінованих тестів використовувати логічні лічильники, а не час стінного
годинника. Показати кільце через інспектор і включити в evidence відмови. Наявний
append-only журнал swarm демонструє цінність відтворюваного стану, але події
виконання ОС потребують окремої обмеженої схеми.

**Пріоритет:** високий для налагодження, після serial-виводу.

## 10. Файли та версії

Форумні дискусії й мануали показують, що Lisp-машини все ще використовували
ієрархічні файли й директорії; версійовані файли були корисними, але немає
доказів, що заміна самої абстракції файлів була їх центральною перевагою.

Для `wsm-os`:

- тримати source та артефакти content-addressed і Git-backed на хості;
- спершу використовувати вбудовані read-only секції образу;
- додати FAT лише тоді, коли фізичний boot цього вимагає;
- не винаходити систему файлів до появи моделі об'єктів/образів.

**Пріоритет:** низький.

## Про що форуми попереджають нас не робити

1. **«Written in Lisp» не прибирає складність сучасного заліза.** USB, GPU,
   мережі та гетерогенні пристрої лишаються складними.
2. **Один адресний простір не є автоматично безпечним.** Сучасна ізоляція чи
   межі спроможностей досі важливі; самі tagged значення не авторизують доступ
   до пристроїв.
3. **Nostalgia — не вимога продукту.** Open Genera цінна для вивчення, але
   практики застерігають, що її старе середовище само по собі не практичне для
   сучасної щоденної роботи.
4. **Спеціальне залізо не є автоматично швидшим.** Кеші, stock x86_64 і добрі
   метадані компілятора можуть перевершити відтворення історичного мікрокоду.
5. **Повна Lisp ОС — це довгоживуча екосистема.** Тисячі комітів Mezzano й
   тривала робота над залізом — доказ проти обіцянки повної ОС від першого
   boot-свідка.

## Рекомендований вплив на roadmap

### Додати до ранньої архітектури, без розширення v0.1

1. Явні tail-position метадані та доказ константного стеку на рівні цілі.
2. ID визначень CML і source maps.
3. ID об'єктів рантайму, відмінні від сирих адрес.
4. Структуровані записи condition при збереженні малого ABI помилок boot.
5. Версійований serial-протокол інспектора.
6. Обмежене логічне кільце подій.

### Прототипувати після першого QEMU oracle parity

7. Крос-субстратний семантичний trace з логічними ID, а не адресами.
8. Ратифікована модель ownership незмінного literal-простору.
9. Заміна на рівні визначень із правилами безпеки активних фреймів.
10. Presentation-записи, споживані Tauri.
11. Релокований логічний формат образу з переприв'язкою спроможностей.
12. Керовані task-фрейми як шлях до stack groups/restarts.

### Тримати відкладеним

10. Generational GC, GUI-композитор, файлова система, мережа, SMP, власні
    мікрокод і драйвери фізичних пристроїв.

## Джерела

Основні та проєктні джерела (ті самі посилання, що в англійському оригіналі):

- [Symbolics Genera Concepts](https://www.chai.uni-hamburg.de/~moeller/symbolics-info/genera/genera.html)
- [Symbolics Common Lisp Language Concepts](https://bitsavers.org/pdf/symbolics/software/genera_8/Symbolics_Common_Lisp_Language_Concepts.pdf)
- [Symbolics Program Development Utilities](https://bitsavers.org/pdf/symbolics/software/genera_8/Program_Development_Utilities.pdf)
- [Preliminary Lisp Machine Manual — stack groups](https://www.bitsavers.org/pdf/mit/cadr/Weinreb_Moon-Lisp_Machine_Manual_Jan_1979.pdf)
- [Mezzano repository and current feature record](https://github.com/froggey/Mezzano)

Дискусії практиків (анекдотичний evidence, використовуються як напрямки):
посилання ідентичні англійському оригіналу вище (Hacker News / Reddit).
