# MMIO WRITE32 VALUE-PRESERVATION EVIDENCE / СВІДОК ЗБЕРЕЖЕННЯ ЗНАЧЕННЯ В MMIO WRITE32

**Статус:** ПІДТВЕРДЖЕНО (CONFIRMED), виправлено
**Репозиторій:** `wsm-os-lisp`
**Дата фіксації:** 2026-09-17
**Задача:** `wsm-os-lisp#40` ([DEVICE-CAP-VERTICAL-1])

---

## 1. Проблема / Problem

`wsm_mmio_write32` отримує значення для запису в `%rcx`
(`RDI=ctx, RSI=cap, RDX=offset, RCX=value`). Перед bounds-перевіркою функція
викликала внутрішній `.Ldecode_check_mmio_cap`, щоб перевірити право
(identity) capability. Цей хелпер використовує `%rcx` як scratch для nonce:

```asm
.Ldecode_check_mmio_cap:
    ...
    movabsq $0x1A0495124347, %rcx
    shlq $16, %rcx
    cmpq %rcx, %rax
```

`%rcx` — caller-saved, і значення зберігалося в `%r12` **після** виклику.
Тому кожен store записував не передане значення, а похідну від nonce сталу:

```text
low32((0x1A0495124347 << 16) >> 3) = 0x4868E000
```

Наслідок: `device_status` (virtio-pci common-config, offset `0x14`) ніколи не
набував значення `1`; запис мовчки перетворювався на `0x4868E000`. Читання
повертало `0`, а Lisp-фікстура D2 `(eq (mmio-read32 mmio 20) 1)` давала `nil`.

Це той самий клас дефекту, що й у `%rcx`-псуванні в `.Lpage_walk_present`, яке
було виправлено раніше в межах #40 (провіженінг фізичної бази).

## 2. Локалізація / Localization

Доказ, що read-шлях коректний, а write-шлях — ні (обидва на канонічному
чисто-ASM шляху, QEMU `q35`, `virtio-blk-pci,disable-legacy=on,addr=5`):

| Перевірка | Результат |
|---|---|
| сирий `movl 20(%base)` після `wsm_mmio_write32(cap,20,1)` | `0` |
| сирий `movl $1, 20(%base)`; потім `wsm_mmio_read32(cap,20)` | `1` |
| прямий `movl $1,(base+0x14)` → `movl (base+0x14)` | `1` |

Тобто пристрій доступний, регістр `device_status` защіпає `1`, read32
обчислює адресу правильно — а write32 клав не те значення.

## 3. Виправлення / Change

`src/runtime.s`, `wsm_mmio_write32`: значення зберігається в `%r12`
**до** виклику `.Ldecode_check_mmio_cap`, після чого декодується і пишеться:

```asm
    pushq %rdi
    movq %rcx, %r12        # save value: decode clobbers %rcx
    movq %rsi, %rdi
    call .Ldecode_check_mmio_cap
    ...
    sarq $3, %r12
    movl %r12d, (%rbx,%rax)
```

Bounds-перевірка (`offset + 4 <= region_len`, `CF` на переповнення) і
fail-closed `wsm_fail` лишаються без змін; стекові шляхи помилок
збалансовані.

## 4. Witness / Свідок

Канонічний чисто-ASM шлях, гейт `scripts/check-mmio-device-op.sh`
(доданий до `.github/workflows/ci.yml`):

```bash
bash scripts/check-mmio-device-op.sh
```

```text
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=t status=ok
MMIO-DEVICE-OP: PASS (Lisp device op writes/reads real virtio-blk device_status via opaque MMIO capability)
```

Фікстура `artifacts/d2-virtio-blk-status-fixture.lisp` не містить жодної
фізичної/віртуальної адреси — лише непрозору MMIO-capability і
типізований offset/width. Транскрипт:
`artifacts/d2-virtio-blk-status-fixture-wsm-asm-transcript.txt`.

### Заувага про попередній доказ / Note on the earlier evidence

`docs/MMIO-PHYS-MAP-FAIL-CLOSED-EVIDENCE.md` §4 посилається на позитивний
вихід `WSM-OS DRIVER schema=1 ... value=t execution=wsm`. Цей транскрипт
походить із **колишнього Rust-ядра** (`crates/wsm-os-kernel`), якого в цьому
репозиторії вже немає після ADR-004. На канонічному чисто-ASM шляху той
позитивний результат **не відтворювався** (фікстура давала `nil`) — саме це
й виявив цей свідок. Тепер обидва факти розділені: історичне Rust-свідчення
лишається як історія; чинний доказ — чисто-ASM гейт вище.

## 5. Висновок / Conclusion

- `CONFIRMED`: `wsm_mmio_write32` зберігає значення через виклик декодера.
- `CONFIRMED`: одна реальна пристрійна операція (`device_status=1` → read `1`)
  виконується Lisp-політикою над непрозорою capability на реальному
  чисто-ASM target-шляху.
- `CONFIRMED`: read32/bounds/fail-closed не змінювалися і лишаються зеленими.
