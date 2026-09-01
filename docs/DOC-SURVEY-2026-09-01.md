# DOC-SURVEY-2026-09-01 — огляд нових доків wsm-os

**Виконавець:** wsl-nidana-1 (ecosystem-координаційна сесія)
**Метод:** `git log --since=2026-08-28 --name-only --diff-filter=A -- docs/`
+ `--stat` для суттєво змінених файлів. Виключено вже раніше розібране:
README.md, repo.my, AGENTS.md, ADR-001, ADR-003, target-contract.wsm,
tasks.my (закриті/відкриті задачі), і сам `docs/VISION.md` (написаний і
щойно виправлений у цій сесії).

## Reproducibility-хребет під усіма "unchanged fixture" твердженнями

- **`docs/DEFINITION-CAPSULE.md`** (росте з 30 серпня по 1 вересня) —
  версіонована ідентичність скомпільованого WSM-визначення: `definition_id =
  sha256(schema+source-semantic-sha+entry-symbol+target-ABI+
  my-lisp-contract+CML-contract)`, навмисно БЕЗ байтів машинного коду — тому
  перекомпіляція того самого допущеного визначення зберігає ідентичність,
  а digest об'єкта/асемблера й далі ловить дрейф. `check-definition-capsule.sh`
  подвійно регенерує й побайтово звіряє. Реальний gotcha: GNU `as` додає
  недетермінований `.note.gnu.property`, стрипається через `objcopy` перед
  хешуванням, щоб Guix/GitHub давали однакові байти. Це фундамент під усіма
  "unchanged fixture, pinned SHA" твердженнями з closure-runtime і
  PCI-identity роботи цієї сесії.

## Перший реальний capability-boundary прецедент

- **`docs/BLOCK-MECHANISM.md`** (11 комітів 31 серпня, найбільший churn) —
  `wsm-os-block`: файл-бековані блоки фіксованого розміру, 16-байтний
  заголовок (magic/version/len/FNV-1a checksum), 15 доведених властивостей
  (round-trip, відхилення corruption/truncation/geometry, ін'єкція часткового
  запису). Явно лише механізм — жодних WSM-значень/імен/журналу. Новина:
  hosted broker тепер гейтить доступ до block-medium за capability-грантом
  path/geometry — перший реальний прецедент тієї самої форми, яку `ADR-003`
  хоче для PCI/MMIO.

## Відкриті, чесно named-unclosed

- **`docs/FS-READONLY-ADAPTER.md`** — `wsm-os-fs-adapter` між block-medium і
  семантикою конвертів my-lisp; `read_validated_image` — все-або-нічого.
  Наразі доводить лише reopen/atomic-rejection синтетичним валідатором —
  явно каже, що наступний witness має підключити СПРАВЖНІЙ парсер конвертів
  my-lisp. Відкритий інтеграційний контракт, ще не закритий.

- **`docs/Q6B-VIRTUAL-DISK-DESIGN.md`** — явно визначає ще відкритий
  розрив: Q6a (guest-memory read/write) CONFIRMED, Q6b (clean-restart
  persistence на тому самому диску) OPEN, Q7 (crash/power-loss recovery)
  OPEN. Захищає від тихого повторного використання boot-образу як
  writable-диска.

## Фундамент і спадковість

- **`docs/ADR-002-BOOT-SUBSTRATE.md`** — ACCEPTED: `bootloader`/
  `bootloader_api` запінені точно на 0.11.17, nightly-2026-07-27 toolchain
  запінений (пізніший nightly зламав UEFI-лінкування на `wcslen`). Реальний,
  датований, фальсифіковний пін — варто перевірити, чи ще актуальний.

- **`docs/LISP-MACHINE-HERITAGE.md`** — не дизайн-док, позиційний документ:
  бере tagged-word dispatch, object-aware memory, bump-then-copying-GC,
  symbol=interned-ID зі спадщини Symbolics/Ivory/Scheme-79; явно відкидає
  CDR-coding, апаратний CAR/GC, microcode ISA. Теза: "WSM-OS aims to become a
  machine whose natural values are WSM values." Пряме пояснення, чому
  tagging-схема в `target-contract.wsm` виглядає саме так — і чому fpga-lisp
  ділить той самий machine contract (FETCH→DECODE→tag-dispatch→cons-memory).
  Пряма опора під self-hosting-тезою `docs/VISION.md`.

## Реальна прогалина

Немає жодного окремого PCI/virtio design-доку — ця архітектура (поточний
фронтир, WSM-OS-WSM-PCI-CONFIG-CAPABILITY-D1 та далі) зараз живе лише в
`tasks.my` + commit messages, не в `docs/`.

## Не прочитано (стат-нуто, не виявилось суттєвіше за вище)

`ECOSYSTEM-REUSE-MAP.md`, `LISP-MACHINE-FEATURE-RESEARCH.md`,
`TARGET-ABI.md`, `IMPLEMENTATION-PLAN.md`, `QEMU-LOCAL-RUN.md`,
`OWNER-HARDWARE-PROFILE.md`.
