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

## Перевірені приклади (чому сліпий merge небезпечний)

Дві гілки перевірені вручну в цьому проході:

1. **`parity/compiler-symbol-provenance`** (3 коміти попереду, PR немає) — змінює `crates/m4-generator/Cargo.toml` і `crates/m4-generator/src/main.rs`. Це **Rust**, заборонений ADR-004. Зміст належить до pre-ADR-004 епохи; інтеграція заборонена, допустимий статус — архів із provenance.
2. **`provenance/gpt-canonicalization`** (2 коміти попереду, PR немає) — додає `scripts/canonicalize-gpt-image.py`. У `main` вже є новіша версія цього скрипта (238 рядків проти 230; інша сигнатура `sha256`, інший опис), а `check-shared-oracle-provenance.sh` у гілці ще посилається на розширення `.my`, яке в `main` перейменоване на `.lisp`. Зміст **застарілий**, зливати нічого.

Висновок: обидві «завершені на вигляд» гілки не підлягають злиттю, і жодна з них не виявила б цього через ancestry-перевірку.

## Повна таблиця

| Гілка | +/− | PR | Останній коміт | Вердикт |
| :--- | ---: | :--- | :--- | :--- |
| `test/45-boxed-rational-runtime-red` | 13/75 | #46 OPEN | 2026-09-18 | PR відкрито (навмисно RED) — не зливати |
| `authority/semantic-guard` | 9/121 | #14 MERGED | 2026-09-11 | PR змерджено (squash) — інтегровано |
| `issue-86-predicate-bit-v8-consumer` | 9/39 | #93 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `chatgpt/target-abi-v6-consumer` | 8/75 | #48 MERGED | 2026-09-18 | PR змерджено (squash) — інтегровано |
| `issue-78-pit-irq-v1` | 8/35 | #98 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `authority/role-boundary` | 7/122 | #13 MERGED | 2026-09-11 | PR змерджено (squash) — інтегровано |
| `fix/sens-paths-lisp-current` | 7/68 | #57 CLOSED | 2026-09-28 | PR закрито без злиття — перевірити зміст |
| `issue-84-dma-evidence-v2` | 7/43 | #87 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `issue-95-canonical-envelope-v1` | 7/36 | #96 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `research/66-final-pc-binding` | 6/56 | #68 CLOSED | 2026-10-03 | PR закрито без злиття — перевірити зміст |
| `issue-77-clean-restart-sector-v1` | 5/40 | #91 CLOSED | 2026-10-08 | PR закрито без злиття — перевірити зміст |
| `issue-77-clean-restart-sector-v2` | 5/39 | #92 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `issue-82-falsifier-matrix-v1` | 5/40 | #90 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `issue-82-sector-roundtrip-v1` | 5/41 | #89 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `issue-82-virtqueue-setup-v1` | 5/42 | #88 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `issue-84-dma-address-proof-v1` | 5/44 | #85 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `provenance/gpt-variance-model` | 5/114 | #24 CLOSED | 2026-09-11 | PR закрито без злиття — перевірити зміст |
| `issue-76-m0-m1-boot-witness-phase-a` | 4/47 | #80 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `authority/error-code-admission` | 3/120 | #15 MERGED | 2026-09-11 | PR змерджено (squash) — інтегровано |
| `issue-76-sens-l3-qemu-parity` | 3/46 | #81 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `parity/bounded-oracle-observer` | 3/115 | #20 MERGED | 2026-09-11 | PR змерджено (squash) — інтегровано |
| `parity/compiler-symbol-provenance` | 3/113 | — (PR немає) | 2026-09-11 | без PR — перевірити зміст |
| `parity/shared-oracle-corpus` | 3/119 | #16 MERGED | 2026-09-11 | PR змерджено (squash) — інтегровано |
| `rename/sens-contract-authority` | 3/68 | #55 CLOSED | 2026-09-26 | PR закрито без злиття — перевірити зміст |
| `replay/31-qemu-never-ready-uart-20261009` | 3/26 | #106 MERGED | 2026-10-09 | PR змерджено (squash) — інтегровано |
| `replay/54-sens-authority-cutover-20261009` | 3/25 | #108 MERGED | 2026-10-09 | PR змерджено (squash) — інтегровано |
| `replay/57-active-lisp-path-hygiene-20261009` | 3/29 | #103 MERGED | 2026-10-09 | PR змерджено (squash) — інтегровано |
| `research/64-root-map-wire-consumer` | 3/56 | #65 MERGED | 2026-10-03 | PR змерджено (squash) — інтегровано |
| `docs/m2-ledger-sync-2026-10-08` | 2/37 | #94 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `feat/33-target-observer-bounded` | 2/89 | #39 CLOSED | 2026-09-15 | PR закрито без злиття — перевірити зміст |
| `fix/31-bounded-uart-poll` | 2/89 | #37 CLOSED | 2026-09-15 | PR закрито без злиття — перевірити зміст |
| `issue-77-m2-q6b-realign` | 2/45 | #83 MERGED | 2026-10-08 | PR змерджено (squash) — інтегровано |
| `parity/shared-oracle-t-set` | 2/118 | #17 MERGED | 2026-09-11 | PR змерджено (squash) — інтегровано |
| `provenance/gpt-canonicalization` | 2/114 | — (PR немає) | 2026-09-11 | без PR — перевірити зміст |
| `provenance/shared-oracle-chain-2` | 2/116 | #19 MERGED | 2026-09-11 | PR змерджено (squash) — інтегровано |
| `replay/31-always-on-serial-gate-20261009` | 2/25 | #107 MERGED | 2026-10-09 | PR змерджено (squash) — інтегровано |
| `replay/31-serial-bounded-regression-20261009` | 2/27 | #105 MERGED | 2026-10-09 | PR змерджено (squash) — інтегровано |
| `replay/57-oracle-temp-lisp-20261009` | 2/28 | #104 MERGED | 2026-10-09 | PR змерджено (squash) — інтегровано |
| `research/66-final-pc-main-replay` | 2/51 | #69 MERGED | 2026-10-03 | PR змерджено (squash) — інтегровано |
| `chore/volnist-current-surfaces` | 1/76 | #43 MERGED | 2026-09-18 | PR змерджено (squash) — інтегровано |
| `parity/shared-oracle-coverage` | 1/117 | #18 MERGED | 2026-09-11 | PR змерджено (squash) — інтегровано |
| `provenance/image-determinism` | 1/114 | #21 CLOSED | 2026-09-11 | PR закрито без злиття — перевірити зміст |
| `replay/31-serial-exit39-main-20261009` | 1/30 | #102 MERGED | 2026-10-09 | PR змерджено (squash) — інтегровано |
| `tmp-ignore` | 1/114 | #23 CLOSED | 2026-09-11 | PR закрито без злиття — перевірити зміст |
| `chatgpt/bounded-serial-current-main` | 0/74 | — (PR немає) | 2026-09-18 | повністю в main — надлишкова |
| `fix/ci-sens-submodule-path` | 0/59 | #56 MERGED | 2026-10-03 | повністю в main — надлишкова |
| `integration/neutral-target-contract` | 0/122 | — (PR немає) | 2026-09-10 | повністю в main — надлишкова |
| `parity/compiler-owned-symbols` | 0/106 | #25 MERGED | 2026-09-11 | повністю в main — надлишкова |
| `provenance/shared-oracle-chain` | 0/116 | — (PR немає) | 2026-09-11 | повністю в main — надлишкова |
| `research/60-mark-sweep-arena-model` | 0/53 | #67 MERGED | 2026-10-03 | повністю в main — надлишкова |
| `research/62-gc-root-map-abi` | 0/57 | #63 MERGED | 2026-10-03 | повністю в main — надлишкова |
| `research/64-closure-new-positive-control` | 0/48 | #70 MERGED | 2026-10-03 | повністю в main — надлишкова |
| `test/64-quote-bounded-root-map-wire` | 0/43 | #72 MERGED | 2026-10-03 | повністю в main — надлишкова |

## Що з цим робити далі

1. **Нічого не зливати автоматично.** Для 11 гілок класів «PR закрито» і «без PR» потрібен один обмежений прохід: для кожної — diff проти merge-base, рішення «застаріле / корисне / заборонене ADR-004», і лише тоді ручна інтеграція в `main`.
2. **Видалення 9 надлишкових гілок** — рішення власника (дія незворотна). Агент його не виконує самостійно.
3. **Нових гілок не створювати.** Навіть для цього проходу.
