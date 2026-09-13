# CAPABILITY-IDENTITY ADVERSARIAL WITNESS / СВІДОК ІДЕНТИЧНОСТІ CAPABILITY (ADVERSARIAL)

**Статус:** ПІДТВЕРДЖЕНО (CONFIRMED)
**Репозиторій:** `wsm-os-lisp`
**Дата фіксації:** 2026-09-13
**Джерело задачі:** `WSM-OS-PCI-CAPABILITY-UNFORGEABILITY-HARDENING` (done 2026-09-06) — цей witness посилює той самий висновок QEMU-доказом поза ладом unit tests.

---

## 1. Що саме перевіряється / What is under test

Capability — це opaque token, виданий substrate. Його decoded class є
частиною ідентичності: `CapabilityKind` входить у packed descriptor поряд із
instance і nonce. Користування capability з одного класу в межах чужого класу
має відкидатись **до** будь-якої volatile-дії, навіть коли сам descriptor
глобально well-formed (коректно декодується й узгоджений із активним grant).

Це подвійний шар захисту порівняно зі старою «рівністю константі» (див.
description задачі): знання дійсного значення capability одного класу не
узагальнюється на інший клас.

## 2. Fixture / Фікстура (hostile WSM)

```lisp
((lambda (pci)
   (mmio-write32 pci 20 1))
 (pci-config-capability))
```

Hostile WSM законно отримує PCI-config capability від `wsm_pci_config_capability`,
потім намагається використати те саме слово як MMIO capability для
virtio-blk common-cfg STATUS register (offset 20). CML-mapped імпорти:
`wsm_mmio_write32`, `wsm_pci_config_capability` (в ratify-allowlist).

## 3. Очікування та результат / Expectation and result

```bash
nice -n 15 bash scripts/rebuild-and-run-capability-identity-adversarial-qemu.sh
```

```
CAPABILITY-ID-PASS: PCI capability rejected as MMIO capability before volatile access
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS CONDITION schema=1 kind=ABI source=1296649989 value=12115145523094093838
```

- гість вийшов структуровано через `wsm_fail` (qemu exit `0x12` → shell 37);
- `CONDITION kind=ABI source=1296649989` = `0x4D49_4F05`
  (MMIO wrong-capability/write-парец); 
- `value` — це той самий capability word, що PCI-capability-слово з
  d1-bounds transcript; перетин класів не пройшов;
- жоден `stage=mmio-status value=t` у логу — volatile-доступу не було.
  Транскрипт: `artifacts/d3-mmio-identity-violation-adversarial-fixture-qemu-serial-transcript.txt`.

Детермінізм пайплайну підтверджено подвійним `--verify artifacts`
(byte-identical assembly/manifest/capsule/compiler-symbols).

## 4. Висновок / Conclusion

- `CONFIRMED`: capability-клас є частиною ідентичності token, не лише
  «shape-перевірка». Слово з класом `PciConfig`, узгоджене з активним PCI
  grant, не працює як клас `Mmio`.
- `CONFIRMED`: доказ відбувається на цьому ж QEMU-субстраті, де живе додатна
  сторона (d1/d2), за одним pinned CML і target-contract.
- Scope не розширювався: ніяких нових механізмів (DMA/interrupts/virtqueue)
  не додавалось.