# Інвентаризація гілок — 2026-11-26
*Branch inventory: what is already in `main`, what still needs a content review*

**Дата**: 2026-11-26
**Статус**: знімок стану, не рішення. Не дозволяє жодного злиття.
**Політика**: наказ власника 2026-10-11 ([`AGENTS.md`](../AGENTS.md)) — нові гілки заборонені; інтеграція йде безпосередньо в `main`; простий ancestry-merge не вважається гарантією збереження змісту.

## Навіщо цей файл

Політика вимагає інвентаризувати історичні гілки, а не зливати їх навмання. Цей знімок фіксує, які гілки вже інтегровані, а які потребують перевірки змісту. Він існує, щоб наступний агент не почав «мержити все» — саме так виникає борг, який потім платить власник.

## Як відтворити

```bash
git fetch origin '+refs/heads/*:refs/remotes/origin/*'
for b in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -v HEAD); do
  printf '%s %s\n' "$(git rev-list --count main..$b)" "${b#origin/}"
done
gh pr list --state all --limit 200 --json number,state,headRefName
```

`+/−` — кількість комітів попереду / позаду `main`.

## Підсумок

| Клас | Кількість | Що це означає |
| :--- | ---: | :--- |
| PR змерджено (squash) | 32 | Зміст пройшов ревʼю і потрапив у `main`; гілку можна вважати адміністративно завершеною |
| Повністю в `main` (0 попереду) | 9 | Надлишкові; видалення — окреме рішення власника, не дія агента |
| PR закрито без злиття | 9 | **Потребують перевірки змісту**: частина може містити корисне, частина — застаріле |
| Без PR, з унікальними комітами | 2 | Потребують перевірки змісту |
| PR відкрито (навмисно RED) | 1 | `#46` — RED-тест, зливати не можна за визначенням |
| Створена 2026-11-26, порожня | 1 | `fix/45-boxed-rational-runtime-v9-20261126` — нуль комітів попереду `main`; див. §Порушення політики |

## Перевірені приклади (чому сліпий merge небезпечний)

Дві гілки перевірені вручну в цьому проході:

1. **`parity/compiler-symbol-provenance`** (3 коміти попереду, PR немає) — змінює `crates/m4-generator/Cargo.toml` і `crates/m4-generator/src/main.rs`. Це **Rust**, заборонений ADR-004. Зміст належить до pre-ADR-004 епохи; інтеграція заборонена, допустимий статус — архів із provenance.
2. **`provenance/gpt-canonicalization`** (2 коміти попереду, PR немає) — додає `scripts/canonicalize-gpt-image.py`. У `main` вже є новіша версія цього скрипта (238 рядків проти 230; інша сигнатура `sha256`, інший опис), а `check-shared-oracle-provenance.sh` у гілці ще посилається на розширення `.my`, яке в `main` перейменоване на `.lisp`. Зміст **застарілий**, зливати нічого.

Висновок: обидві «завершені на вигляд» гілки не підлягають злиттю, і жодна з них не виявила б цього через ancestry-перевірку.

## Повна таблиця

Tip SHA — це адреса вмісту гілки. Вона тут не для краси: якщо гілку буде видалено,
саме SHA лишається єдиним способом повернутися до її вмісту (див. §Архівування нижче).

| Гілка | +/− | PR | Останній коміт | Вердикт | Tip SHA |
| :--- | ---: | :--- | :--- | :--- | :--- |
| `test/45-boxed-rational-runtime-red` | 13/85 | #46 OPEN | 2026-09-18 | PR відкрито (навмисно RED) | `262b036ee048` |
| `authority/semantic-guard` | 9/131 | #14 MERGED | 2026-09-11 | PR змерджено (squash) | `3e58d4339941` |
| `issue-86-predicate-bit-v8-consumer` | 9/49 | #93 MERGED | 2026-10-08 | PR змерджено (squash) | `6fcf0de50c03` |
| `chatgpt/target-abi-v6-consumer` | 8/85 | #48 MERGED | 2026-09-18 | PR змерджено (squash) | `7ca34e1d9a8a` |
| `issue-78-pit-irq-v1` | 8/45 | #98 MERGED | 2026-10-08 | PR змерджено (squash) | `42a4cc49dfaf` |
| `authority/role-boundary` | 7/132 | #13 MERGED | 2026-09-11 | PR змерджено (squash) | `4370c994fec6` |
| `fix/sens-paths-lisp-current` | 7/78 | #57 CLOSED | 2026-09-28 | PR закрито без злиття — **застаріле** | `c762f62124a1` |
| `issue-84-dma-evidence-v2` | 7/53 | #87 MERGED | 2026-10-08 | PR змерджено (squash) | `6b4503f2b522` |
| `issue-95-canonical-envelope-v1` | 7/46 | #96 MERGED | 2026-10-08 | PR змерджено (squash) | `d6d8e3a3c2a1` |
| `research/66-final-pc-binding` | 6/66 | #68 CLOSED | 2026-10-03 | PR закрито без злиття — **застаріле** | `8ef9c96fa937` |
| `issue-77-clean-restart-sector-v1` | 5/50 | #91 CLOSED | 2026-10-08 | PR закрито без злиття — **застаріле** | `3ac04f05d86e` |
| `issue-77-clean-restart-sector-v2` | 5/49 | #92 MERGED | 2026-10-08 | PR змерджено (squash) | `9343c5dc9ae7` |
| `issue-82-falsifier-matrix-v1` | 5/50 | #90 MERGED | 2026-10-08 | PR змерджено (squash) | `3b03195f2f46` |
| `issue-82-sector-roundtrip-v1` | 5/51 | #89 MERGED | 2026-10-08 | PR змерджено (squash) | `ea0923eb2785` |
| `issue-82-virtqueue-setup-v1` | 5/52 | #88 MERGED | 2026-10-08 | PR змерджено (squash) | `7bd16538a49e` |
| `issue-84-dma-address-proof-v1` | 5/54 | #85 MERGED | 2026-10-08 | PR змерджено (squash) | `5312e08dc23f` |
| `provenance/gpt-variance-model` | 5/124 | #24 CLOSED | 2026-09-11 | PR закрито без злиття — **застаріле** | `362d48a34622` |
| `issue-76-m0-m1-boot-witness-phase-a` | 4/57 | #80 MERGED | 2026-10-08 | PR змерджено (squash) | `9e545a99610f` |
| `authority/error-code-admission` | 3/130 | #15 MERGED | 2026-09-11 | PR змерджено (squash) | `75a585db6390` |
| `issue-76-sens-l3-qemu-parity` | 3/56 | #81 MERGED | 2026-10-08 | PR змерджено (squash) | `661eac2ea3b0` |
| `parity/bounded-oracle-observer` | 3/125 | #20 MERGED | 2026-09-11 | PR змерджено (squash) | `c17b6d2c101f` |
| `parity/compiler-symbol-provenance` | 3/123 | — | 2026-09-11 | без PR — **заборонене ADR-004** | `92880a7c6d05` |
| `parity/shared-oracle-corpus` | 3/129 | #16 MERGED | 2026-09-11 | PR змерджено (squash) | `a12dc112745d` |
| `rename/sens-contract-authority` | 3/78 | #55 CLOSED | 2026-09-26 | PR закрито без злиття — **застаріле** | `c2cebd9035f3` |
| `replay/31-qemu-never-ready-uart-20261009` | 3/36 | #106 MERGED | 2026-10-09 | PR змерджено (squash) | `50812a63efc5` |
| `replay/54-sens-authority-cutover-20261009` | 3/35 | #108 MERGED | 2026-10-09 | PR змерджено (squash) | `5bbb8b724b35` |
| `replay/57-active-lisp-path-hygiene-20261009` | 3/39 | #103 MERGED | 2026-10-09 | PR змерджено (squash) | `99654e1b9821` |
| `research/64-root-map-wire-consumer` | 3/66 | #65 MERGED | 2026-10-03 | PR змерджено (squash) | `431a9f4c8294` |
| `docs/m2-ledger-sync-2026-10-08` | 2/47 | #94 MERGED | 2026-10-08 | PR змерджено (squash) | `f8e0863cb90f` |
| `feat/33-target-observer-bounded` | 2/99 | #39 CLOSED | 2026-09-15 | PR закрито без злиття — **застаріле** | `46ccda36e90a` |
| `fix/31-bounded-uart-poll` | 2/99 | #37 CLOSED | 2026-09-15 | PR закрито без злиття — **застаріле** | `9955dee4edfd` |
| `issue-77-m2-q6b-realign` | 2/55 | #83 MERGED | 2026-10-08 | PR змерджено (squash) | `9868ae402f76` |
| `parity/shared-oracle-t-set` | 2/128 | #17 MERGED | 2026-09-11 | PR змерджено (squash) | `dc8e55e264de` |
| `provenance/gpt-canonicalization` | 2/124 | — | 2026-09-11 | без PR — **застаріле** | `9b0f3c36aaff` |
| `provenance/shared-oracle-chain-2` | 2/126 | #19 MERGED | 2026-09-11 | PR змерджено (squash) | `c95f63042e6d` |
| `replay/31-always-on-serial-gate-20261009` | 2/35 | #107 MERGED | 2026-10-09 | PR змерджено (squash) | `89f4b56b5efb` |
| `replay/31-serial-bounded-regression-20261009` | 2/37 | #105 MERGED | 2026-10-09 | PR змерджено (squash) | `ecfa7ba23151` |
| `replay/57-oracle-temp-lisp-20261009` | 2/38 | #104 MERGED | 2026-10-09 | PR змерджено (squash) | `ac876ce076ad` |
| `research/66-final-pc-main-replay` | 2/61 | #69 MERGED | 2026-10-03 | PR змерджено (squash) | `d42475fbca4d` |
| `chore/volnist-current-surfaces` | 1/86 | #43 MERGED | 2026-09-18 | PR змерджено (squash) | `d324ba9a1a62` |
| `parity/shared-oracle-coverage` | 1/127 | #18 MERGED | 2026-09-11 | PR змерджено (squash) | `00cdd06ad24b` |
| `provenance/image-determinism` | 1/124 | #21 CLOSED | 2026-09-11 | PR закрито без злиття — **мертве (legacy)** | `245fb6f03721` |
| `replay/31-serial-exit39-main-20261009` | 1/40 | #102 MERGED | 2026-10-09 | PR змерджено (squash) | `4c60d020a292` |
| `tmp-ignore` | 1/124 | #23 CLOSED | 2026-09-11 | PR закрито без злиття — **мертве (legacy)** | `245fb6f03721` |
| `chatgpt/bounded-serial-current-main` | 0/84 | — | 2026-09-18 | повністю в main | `f73be42caac9` |
| `fix/45-boxed-rational-runtime-v9-20261126` | 0/3 | — | 2026-11-26 | повністю в main | `8e912bdd491a` |
| `fix/ci-sens-submodule-path` | 0/69 | #56 MERGED | 2026-10-03 | повністю в main | `5172bf8bb73c` |
| `integration/neutral-target-contract` | 0/132 | — | 2026-09-10 | повністю в main | `3253c0a7174e` |
| `parity/compiler-owned-symbols` | 0/116 | #25 MERGED | 2026-09-11 | повністю в main | `767bf0565645` |
| `provenance/shared-oracle-chain` | 0/126 | — | 2026-09-11 | повністю в main | `b71163706cf8` |
| `research/60-mark-sweep-arena-model` | 0/63 | #67 MERGED | 2026-10-03 | повністю в main | `e503ef3e64d4` |
| `research/62-gc-root-map-abi` | 0/67 | #63 MERGED | 2026-10-03 | повністю в main | `6a76e5cffad4` |
| `research/64-closure-new-positive-control` | 0/58 | #70 MERGED | 2026-10-03 | повністю в main | `2dc87a8dbf8c` |
| `test/64-quote-bounded-root-map-wire` | 0/53 | #72 MERGED | 2026-10-03 | повністю в main | `89a0008d83da` |

## Результат перевірки змісту (11 гілок без злитого PR)

Перевірено 2026-11-26. Метод: diff проти `merge-base`, потім вибірка до 8 «змістових»
доданих рядків (довших за 45 символів, не комментарів) і пошук кожного в дереві `main`
через `git grep -F`. Додатково — пошук маркера `LEGACY` і файлів `.rs`/`Cargo.*`.

| Гілка | Вердикт | Доказ |
| :--- | :--- | :--- |
| `issue-77-clean-restart-sector-v1` | **застаріле** | 8/8 вибіркових рядків уже в `main` |
| `research/66-final-pc-binding` | **застаріле** | 8/8 уже в `main` |
| `fix/sens-paths-lisp-current` | **застаріле** | перейменування `.my`→`.lisp`; `main` зробив це сам, пізніше й інакше (0/5 збігів — інші SHA в URL) |
| `rename/sens-contract-authority` | **застаріле** | 2/2 уже в `main` |
| `feat/33-target-observer-bounded` | **застаріле** | 8/8 уже в `main` |
| `fix/31-bounded-uart-poll` | **застаріле** | 3/8; скрипти `check-serial-putc-bounded.sh` і `rebuild-and-run-serial-timeout-qemu.sh` уже в `main` з PR #102 |
| `provenance/gpt-variance-model` | **застаріле** | 8/8 уже в `main` |
| `tmp-ignore` | **мертве (legacy)** | править `check-shared-oracle-provenance.sh` через `cargo`-крейти, прибрані ADR-004; `main` має версію без Rust |
| `provenance/image-determinism` | **мертве (legacy)** | той самий `cargo`-диф, що й `tmp-ignore`; детермінізм образу вже покритий `check-uefi-image-reproducibility.sh` |
| `parity/compiler-symbol-provenance` | **заборонене ADR-004** | править `crates/m4-generator/{Cargo.toml,src/main.rs}` — Rust у production заборонений |
| `provenance/gpt-canonicalization` | **застаріле** | 3/8; `main` має новіший канонікалізатор (238 рядків, шляхи `.lisp`) проти 230 рядків зі старими `.my` |

**Висновок: зливати нічого.** Одинадцять гілок розподілилися на застарілі (8),
мертві legacy-дифи (2) і заборонене ADR-004 (1). Це не «немає часу перевірити» —
це перевірено, і результат негативний.

### Як перевірити гілку за дві хвилини

```bash
base=$(git merge-base main origin/<branch>)
git diff --shortstat $base origin/<branch>            # обсяг
git diff --name-only $base origin/<branch> | grep -E '\.rs$|Cargo\.'   # Rust = заборонено
git log -1 --format=%s origin/<branch>                # чи є маркер LEGACY
git diff $base origin/<branch> | grep '^+' | grep -v '^+++' | head -40   # що саме додано
```

Далі — вибірка доданих рядків і `git grep -F` по `main`. Якщо більшість знаходиться,
гілка застаріла; якщо diff чіпає `.rs`/`Cargo.*` — заборонена; якщо скрипт сам себе
називає LEGACY — мертва.

## Архівування з provenance: чому SHA достатньо

Політика вимагає архівувати старі несумісні реалізації **з provenance**, а не зберігати
їх живими гілками. Практично це означає: записати tip SHA, вердикт і причину — і тоді
видалення гілки не втрачає нічого, крім зручності `git checkout`.

Це не саморобна схема. Ідентифікатор SWHID (Software Heritage) з 2025-04-23 є
стандартом ISO/IEC 18670, і його хеші — це власні хеші git-обʼєктів: будь-який
локальний checkout уже містить валідні SWHID-адреси, навіть якщо Software Heritage
не індексував репозиторій. Тобто коміт, записаний у цій таблиці, є одночасно
звичайним git-SHA і адресою вмісту в сенсі ISO-стандарту.

Обмеження, яке варто знати: SWHID адресує **вміст**, а не гілку. Гілка — це рухомий
вказівник; після видалення її історія живе лише доти, доки обʼєкти не зібрані
`git gc`. Тому перед видаленням гілок варто або дочекатися індексації в Software
Heritage, або зберегти пакунок (`git bundle`) на носії власника.

## Порушення політики, зафіксоване 2026-11-26

Під час інвентаризації виявлено гілку, створену **сьогодні**:

| Гілка | Попереду `main` | Позаду | Вміст |
| :--- | ---: | ---: | :--- |
| `fix/45-boxed-rational-runtime-v9-20261126` | **0** | 3 | немає жодного коміту, якого не було б у `main`; Rust не чіпає |

Тобто: наказ власника від 11.10.2026 забороняє створювати будь-які нові гілки, а гілку
створено — і вона **порожня**: вона вказує на предка `main` і не несе жодного унікального
вмісту. Зливати нічого, втрачати нічого.

Що це означає практично:

- жодної шкоди вмісту `main` це не завдало;
- але це ознака, що правило «жодної нової гілки» не має механічного примусу — лише текст
  у `AGENTS.md`. Політика без гейта існує до першого, хто її не прочитав;
- гілку не видалено: це рішення власника (дія незворотна). Вона лишається зафіксованою
  тут із нульовим вмістом, щоб наступний агент не витрачав час на її «злиття».

### Два шари примусу (додано того ж дня)

Правило без механізму існує до першого, хто його не прочитав. Тому додано обидва шари, які можливі:

| Шар | Що робить | Права | Стан |
| :--- | :--- | :--- | :--- |
| **Запобігання** | GitHub ruleset із правилом *Restrict creations* на всі refs: створювати гілки може лише той, хто в bypass-списку | **адмін репозиторію** | Готовий до імпорту: [`contracts/github-ruleset-no-new-branches.json`](../contracts/github-ruleset-no-new-branches.json). **Імпортувати може лише власник** — агент не має і не повинен мати цих прав |
| **Виявлення** | `scripts/check-branch-policy.py`: порівнює `git ls-remote --heads` із [`branch-disposition.lisp`](../branch-disposition.lisp); нова гілка — FAIL, зсунутий tip замороженої гілки — FAIL, зникла гілка — WARN | лише читання | Працює: воркфлоу `branch-policy.yml` (щодня + вручну), політика `no-new-branches` у реєстрі |

`branch-disposition.lisp` — це і є та машиночитана форма «архіву з provenance», про яку йде мова в §Архівування: імена, tip SHA і вердикти. Гілка, якої немає в цьому файлі, валить перевірку.

Чому це важливо саме як два шари: запобігання вимагає адмінських прав і є рішенням власника; виявлення вимагає лише читання й тому може працювати вже. Агент, який «просто створив ruleset», перевищив би свої повноваження — і саме так виглядала б помилка, яку потім ніхто не помітить.

## Що з цим робити далі

1. **Перевірку 11 гілок виконано 2026-11-26** (§Результат перевірки). Зливати нічого: 8 застарілих, 2 мертві legacy, 1 заборонена ADR-004. Повторювати цей прохід не потрібно.
2. **Видалення 10 надлишкових гілок** (9 повністю в `main` + 1 порожня від 2026-11-26) — рішення власника, дія незворотна. Агент її не виконує. Tip SHA кожної — у таблиці вище, тобто видалення не втрачає адресу вмісту.
3. **Нових гілок не створювати.** Навіть для цього проходу. Правило текстове; механічного гейта немає, і це видно з §Порушення політики.
