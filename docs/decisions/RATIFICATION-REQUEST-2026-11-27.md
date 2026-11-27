# Запит на ратифікацію: ADR-006 підпис і ADR-007 з RmControl

*Ratification request: ADR-006 signature and ADR-007 with RmControl*

**Автор**: agent `big-pickle`
**Стан**: `PROPOSED` для власника; агент **не** додавав і **не** додаватиме підписів власника
**Дата**: 2026-11-27

Цей файл — інструкція для власника, а не підтвердження. `docs/decisions/OWNER-CONFIRMATIONS.lisp`
лишається без змін: рядок там має право додати лише owner-коміт.

## 1. Чому гейт червоний

`bash scripts/check-adr-ratification.sh` падає на одному ADR:

```text
docs/ADR-006-FPC-AS-FOUNDATION-PROPOSAL.md: ACCEPTED but names no decider —
  add a "**Deciders/Хто вирішив**: <name>" line
docs/ADR-006-FPC-AS-FOUNDATION-PROPOSAL.md: ACCEPTED by
<agents@wsm-os-lisp.invalid> in 947ca396a525, and no owner confirmation on record
ADR-RATIFICATION-FAIL: 2 ADR(s) claim a decision the owner did not sign
```

**Statically proven (git provenance):** рядок статусу `ACCEPTED` в ADR-006
введено комітом `947ca39`, автором `wsm-os-lisp agent <agents@wsm-os-lisp.invalid>`.
Декларована ідентичність власника — `85576956+juv4uk@users.noreply.github.com`.
У `OWNER-CONFIRMATIONS.lisp` запису `(confirmed "ADR-006" …)` немає.

**Interpretation:** повторене доручення в чаті не є git-підписом; гейт це й
перевіряє. Червоний стан — не поломка, а чесний опис provenance.

ADR-007 зараз `PROPOSED`, тому цей гейт його не перевіряє. Після ратифікації
він стає другим кандидатом на перевірку.

## 2. Варіанти для ADR-006 (вибери один)

### Варіант А — підтвердити (рекомендований)

У owner-коміті додати до `(confirmed …)` у
`docs/decisions/OWNER-CONFIRMATIONS.lisp` рядок:

```lisp
 (confirmed "ADR-006" "2026-11-27" "Підтверджую ADR-006: Free Pascal як хост-мова; RUST=0; P0-P4 лишаються evidence-gated.")
```

У тому ж owner-коміті додати до ADR-006 рядок з ім'ям того, хто вирішив, бо
гейт вимагає і його:

```text
**Deciders/Хто вирішив**: juv4uk, власник проєкту (2026-11-26; підпис 2026-11-27)
```

Коміт має бути зроблено з author/committer
`85576956+juv4uk@users.noreply.github.com`, інакше гейт побачить агента не як
власника. Перевірка після коміту:

```bash
bash scripts/check-adr-ratification.sh
```

### Варіант Б — відкотити

Повернути ADR-006 у `PROPOSED`, ADR-004 — у `ACCEPTED`, зберегти provenance
`947ca39` як історичний запит. Це теж owner-рішення й owner-коміт.

## 3. Варіант для ADR-007

ADR-007 тепер містить **D7**: у hosted Linux легальний шлях ідентифікації —
`PciConfig` + `RmControl` / `NvRmChannel`; BAR0/MMIO — окрема capability для
firmware/bare-metal seam. Це додано на підставі **runtime-proven** зонда
`gp107-nvidia-re@2c2b746`, але статус лишається `PROPOSED`.

Якщо ти підтверджуєш саме такий склад, зроби owner-коміт, що змінює рядок
статусу на:

```text
**Status/Статус**: **ACCEPTED** — owner-ратифікація 2026-11-27
```

 і залишає/deciders-рядок із власником. Додатково можна додати рядок:

```lisp
 (confirmed "ADR-007" "2026-11-27" "Підтверджую розділення PciConfig/Mmio, BOOT0=UNPROVEN та легальний RmControl-канал ідентифікації; MMIO лише для firmware/bare-metal.")
```

Агент не змінює цей статус і не додає confirmation line самостійно.

## 4. Що не залежить від підпису

- `RUST = 0`, `src/runtime.s` як чинний механізм до green P2 — лишаються.
- `BOOT0 = UNPROVEN` у hosted Linux; `0x137000A1` — `string-only`.
- RM-значення `0x130 / 0x7 / 0xa1 / 0x2` — `runtime-proven`, але не BOOT0.
- ABI `wsm-target-contract` лишається v8 до ратифікації ADR-007; v9 буде
  реалізацією задокументованого контракту, не самостійною правкою структур.

## 5. Мала перевірка після owner-коміту

```bash
cd /home/agents/GitHub/wsm-os-lisp
bash scripts/check-adr-ratification.sh
bash scripts/check-docs-in-change.sh "$(git rev-parse HEAD~1)" HEAD
```
