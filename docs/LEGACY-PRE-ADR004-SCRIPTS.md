# LEGACY PRE-ADR-004 SCRIPTS / ЗАСТАРІЛІ СКРИПТИ ДО ADR-004

**Статус (Status):** ІНВЕНТАРИЗАЦІЯ (inventory), не видалення
**Репозиторій:** `wsm-os-lisp`
**Дата:** 2026-09-17

---

## 1. Навіщо цей документ / Why

[ADR-004](ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md) прибрав Rust з production.
Кілька скриптів у `scripts/` усе ще викликають `cargo … -p m4-generator`,
`wsm-os-hosted`, `wsm-os-kernel`, `wsm-os-image` — крейтів, яких у репозиторії
**більше немає**. Такі скрипти неможливо запустити й вони не є частиною CI.

Цей документ фіксує їхній статус і, де існує, канонічного наступника на
чистому ASM-шляху. Скрипти **не видаляються** (збереження provenance); вони
позначені як legacy.

ADR-004 removed Rust from production. Several scripts still invoke cargo crates
that no longer exist; they cannot run and are not part of CI. This is a
non-destructive inventory, not a deletion.

---

## 2. Інвентар / Inventory

| Скрипт | Причина legacy | Канонічний наступник (pure-ASM) |
|---|---|---|
| `rebuild-and-run-wsm-pci-config-qemu.sh` | `cargo -p m4-generator/wsm-os-image` | `check-mmio-device-op.sh`, `check-mmio-mutation-fail-closed.sh` |
| `rebuild-and-run-mapping-fail-closed.sh` | `cargo -p wsm-os-kernel`; `WSM_OS_FORCE_NO_PHYS_MAP` (Rust) | `check-mmio-mutation-fail-closed.sh` (`forced-no-phys-map`) |
| `rebuild-and-run-capability-identity-adversarial-qemu.sh` | `cargo -p wsm-os-kernel` | `check-mmio-mutation-fail-closed.sh` (`wrong-capability`) |
| `rebuild-and-run-wsm-virtio-identity-qemu.sh` | `cargo -p m4-generator/wsm-os-hosted/wsm-os-image` | провізіювання в `src/runtime.s::wsm_target_provision_mmio` (покрито `check-mmio-device-op.sh`) |
| `rebuild-and-run-fs-qemu.sh` | `cargo -p wsm-os-kernel/wsm-os-image` | — (історія; fs-шлях не портовано) |
| `rebuild-and-run-repl.sh` | `cargo -p wsm-os-kernel/wsm-os-image` | — (історія) |
| `test-repl-serial.py` | `cargo build -p wsm-os-kernel` | — (історія) |
| `check-shared-oracle-corpus.sh` | `cargo -p m4-generator/wsm-os-hosted/wsm-os-kernel` | — (історія) |
| `check-shared-oracle-provenance.sh` | `cargo -p m4-generator/wsm-os-kernel/wsm-os-image` | — (історія) |
| `check-uefi-image-reproducibility.sh` | `cargo -p wsm-os-image`; залежить від виходу попереднього | — (історія) |

Зауваження: `rebuild-and-run-rdtsc-qemu.sh` **не** є legacy — він викликає
зовнішній компілятор CML (`../cml/Cargo.toml`), а не прибрані крейти, і
лишається сумісним із pure-ASM шляхом.

---

## 3. Застарілі транскрипти / Stale transcripts

Транскрипти з рядком `WSM-OS DRIVER schema=1 driver=… execution=wsm …`
(наприклад `d1-*`, `d2-*` `-qemu-serial-transcript.txt`, `d3-*-qemu-serial-transcript.txt`,
`m5h-repl-fixture-qemu-serial-transcript.txt`) походять з pre-ADR-004 Rust-ядра.
Вони зберігаються як **історичні**; вони не є доказом поточного чистого
ASM-шляху.

- `d2` уже має паралельний pure-ASM свідок:
  `artifacts/d2-virtio-blk-status-fixture-wsm-asm-transcript.txt`.
- `d3` (cross-class capability) перевірено наново на чистому ASM як
  `d6-mmio-wrong-capability-fixture` (див.
  `docs/MMIO-MUTATION-AND-POLL-EVIDENCE.md`).

---

## 4. Правило на майбутнє / Forward rule

Додаючи новий свідок, спирайтесь на канонічний ланцюг:

```text
CML (x86-asm)  →  as --64  →  build-uefi-image.sh  →  run-qemu-uefi.sh
```

і додавайте його до `.github/workflows/ci.yml`. Скрипти, що викликають
`cargo -p <removed-crate>`, не додаються до CI і не вважаються доказом.
