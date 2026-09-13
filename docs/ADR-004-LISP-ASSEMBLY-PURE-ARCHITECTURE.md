# ADR-004: Pure Lisp + x86-64 Assembly Architecture (Zero-Rust Target)
*ADR-004: Архітектура чистого Lisp + x86-64 асемблера (Ціль: Zero-Rust)*

**Date/Дата**: 2026-09-14  
**Status/Статус**: ACCEPTED (owner directive / директива власника)  
**Supersedes/Заміщує**: [ADR-003: Machine Mechanism Below, WSM Logic Above](ADR-003-RUST-LISP-MECHANISM-POLICY.md) (SUPERSEDED)

---

## 1. Context and Problem Statement / Контекст і постановка проблеми

Попередній [ADR-003](ADR-003-RUST-LISP-MECHANISM-POLICY.md) допускав використання Rust як "тимчасового субстрату, bootstrap-коду, еталонного драйвера або test harness". На практиці це створило архітектурну лазівку: замість самодостатньої операційної системи на Lisp виник розлогий Rust-прошарок із 9 crate-ів, а в `crates/wsm-os-kernel/src/lisp_repl.rs` було написано повноцінний дублікат Lisp evaluator-а на Rust (reader, evaluator, environments, closures, symbol table, primitive dispatch).

Це суперечить фундаментальній меті проєкту — бути **фізичним доказом самодостатності нашого Lisp як повноцінної системної мови**. Замість формули *"Lisp керує системою поверх голого машинного механізму"*, виникла залежність *"Lisp виконується всередині та під контролем товстого Rust ядра"*.

Власник скасовує архітектуру "Rust + Lisp".

---

## 2. Decision / Рішення

Кінцева production-архітектура репозиторію `wsm-os-lisp`:

$$\text{LISP} + \text{x86-64 ASSEMBLER}. \quad \mathbf{RUST = 0}.$$

Жодної третьої мови реалізації у production runtime не існує.

```text
               ЦІЛЬОВА АРХІТЕКТУРА

                      Lisp
              (semantics & policy)
                       ↓
             Canon + function table
                       ↓
                      CML
                       ↓
                 x86-64 assembly
                       ↓
 ┌───────────────────────────────────────────┐
 │        tiny assembly machine ABI          │
 │        (irreducible machine mechanism)    │
 │ boot / IRQ / ports / MMIO / paging / DMA  │
 └───────────────────────────────────────────┘
                       ↓
                  Bare Metal CPU
```

### 2.1. Розподіл обов'язків / Separation of Concerns

1. **Lisp owns ALL system semantics and policy / Lisp володіє ВСІЄЮ семантикою та політикою системи:**
   - Reader, evaluator, macro expansion, symbol interning, lexical environments, closures.
   - REPL (введення/виведення, взаємодія, історія, рендеринг тексту через шрифти).
   - Драйверна політика: сканування PCI-шини, стан пристроїв (state machines), протокол PS/2 контролера, інтерпретація пакетів миші та скан-кодів клавіатури, повторні спроби (retries), тайм-аути.
   - Файлова система: структури записів (records), парсинг каталогів, кешування блоків.
   - Планувальник (scheduler), черги та керування ресурсами.

2. **Assembly owns ONLY irreducible machine mechanisms / Асемблер володіє ВИКЛЮЧНО незвідними машинними механізмами:**
   - Початкова точка входу CPU / UEFI (hand-off, перехід у Long Mode 64-bit).
   - Збереження та відновлення регістрів процесора (context saving/restore).
   - Точки входу та повернення переривань/пасток (IDT, ISR, iretq).
   - Прямий ввід/вивід портів (`in`/`out`).
   - Привілейовані інструкції CPU (`rdtsc`, `rdrand`, `cpuid`, читання/запис CR0/CR3/CR4, RDMSR/WRMSR, `cli`/`sti`, `invlpg`, `wbinvd`).
   - Примітиви сторінкової адресації (page table manipulation).
   - Базовий MMIO доступ (load/store потрібної розрядності з бар'єрами).
   - Апаратні бар'єри пам'яті (`mfence`, `lfence`, `sfence`).
   - Атомарні примітиви (`lock cmpxchg` тощо), де вони безпосередньо необхідні залізу.
   - DMA та трансляція фізичних адрес.

3. **Assembly MUST NOT own Lisp semantics / Асемблер НЕ МАЄ володіти семантикою Lisp:**
   - Асемблер не реалізує логіку пристроїв, парсинг виразів, семантику символів або структури Lisp-середовищ. Асемблер є виключно виконавцем машинних примітивів, що викликаються згенерованим кодом.

4. **Zero-Rust Criterion / Критерій повного вилучення Rust:**
   ```text
   find . -name '*.rs'        -> 0 production files
   find . -name 'Cargo.toml'  -> 0
   Cargo.lock                 -> absent
   rust-toolchain.toml        -> absent
   .cargo/                    -> absent
   crates/ Rust workspace     -> absent
   ```

---

## 3. Pipeline походження коду / Code Provenance Pipeline

`wsm-os-lisp` не пише власний окремий інтерпретатор або evaluator. Семантика береться виключно з канону:

```text
my-lisp (семантичний оракул, канон, специфікація мови)
   │
   ▼
  CML (компілятор, пониження у машинні форми)
   │
   ▼
x86-64 assembly + target code
   │
   ▼
Bare Metal / QEMU
```

---

## 4. Класифікація модулів при переході / Transition Classification

При міграції наявний код класифікується за чотирма категоріями:

| Поточний компонент | Класифікація | Цільове призначення |
| :--- | :--- | :--- |
| `crates/wsm-os-kernel/src/lisp_repl.rs` | **OBSOLETE DUPLICATE** | Видалити негайно; Lisp REPL має походити з `my-lisp` Canon через CML |
| `crates/wsm-os-kernel/src/drivers.s` | **MACHINE MECHANISM** | Зберегти machine primitives (`in`/`out`, `rdtsc`, `cpuid`, raw pci); логіку винести в Lisp |
| `crates/wsm-os-kernel/src/ps2.rs` | **POLICY -> Lisp / PRIMITIVE -> ASM** | PS/2 протокол і стан миші — в Lisp; порти 0x60/0x64 — в ASM |
| `crates/wsm-os-kernel/src/gop_console.rs` | **POLICY -> Lisp / HANDOFF -> ASM** | Рендеринг тексту, кольори, екранний буфер — в Lisp; адреса FB — в ASM/UEFI handoff |
| `crates/wsm-os-kernel/src/fs_records.rs` | **SEMANTICS -> Lisp** | Семантика записів та парсинг WSM-FS — в Lisp |
| `crates/wsm-os-virtio`, `wsm-os-block` | **POLICY -> Lisp / MMIO -> ASM** | Черги дескрипторів та протокол VirtIO — в Lisp; MMIO load/store — в ASM |
| `crates/wsm-os-runtime` | **SEMANTICS -> Lisp / MEM -> ASM** | Структури cons/closure — канон Lisp; виділення пам'яті та пастки — мінімальний ASM/Lisp |
| `crates/wsm-os-image` | **TOOLING** | Замінити на чистий скрипт складання UEFI FAT32 образу або x86 bootloader без Rust залежностей |

---

## 5. Доказова валідація / Executable Witness Parity

Міграція вважається коректною, якщо всі затверджені свідки (witnesses) проходять успішно:
1. `(cons (quote A) (quote B))` -> `(A . B)`.
2. Замикання (closures) та лексичні оточення.
3. Доступ до апаратних можливостей PCI / MMIO fail-closed.
4. VirtIO / блокові пристрої.
5. Серійні та інтерактивні тести REPL на чистій Lisp-системі в QEMU.
6. CI-вартовий відсутності Rust (`scripts/check-no-rust.sh`) завершується з кодом 0.
