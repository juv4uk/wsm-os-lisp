# Q6b virtual disk persistence / Проєкт Q6b persistence на virtual disk

Q6a proves only an in-memory guest block. Q6b must use a disposable QEMU
virtual disk and expose a bounded block ABI to the guest. The witness is not
power-loss durability until an explicit crash test exists.

Q6a доводить лише guest-memory block. Q6b має використовувати disposable
virtual disk QEMU і надати guest bounded block ABI. Це не є durability після
втрати живлення, доки немає окремого crash-тесту.

## Required sequence / Обов’язкова послідовність

```text
guest open medium
  → read block 0 (unwritten is explicit)
  → write framed record
  → flush
  → emit digest/geometry transcript
  → shutdown cleanly
  → boot same disk again
  → read block 0
  → validate header/checksum/payload
```

The first implementation should use one fixed 512-byte block and a disposable
raw image. The guest must reject wrong geometry, invalid magic/version,
truncated payload, and checksum mismatch. Host-side image creation and QEMU
launch scripts must record exact image path, size, kernel SHA, and transcript.

Перша реалізація має використовувати один фіксований блок 512 байт і
тимчасовий raw image. Guest мусить відхиляти неправильну геометрію,
неправильні magic/version, обрізаний payload і checksum mismatch. Скрипти
створення image та запуску QEMU мають записувати шлях image, розмір, SHA kernel
і transcript.

## Claim boundary / Межа твердження

```text
Q6a  guest-memory read/write/flush        CONFIRMED
Q6b  same-disk clean-restart persistence  CONFIRMED
Q6b  framed-envelope validation + parity  OPEN
Q7   crash/restart recovery                OPEN
```

Do not call a clean restart proof power-loss durability. Do not silently reuse
the boot image as a writable data disk; the data medium must be a separate
disposable artifact.

Не називати clean restart доказом power-loss durability. Не використовувати
boot image як прихований writable data disk: medium має бути окремим
disposable artifact.


## Current architecture correction — 2026-10-08

The original Q6b sequence remains correct, but the implementation dependency is
now explicit.

Historical task `WSM-OS-VIRTIO-BLK-GUEST-DRIVER-Q6B` is complete only for the
D2 device-negotiation slice: PCI/MMIO discovery plus COMMON_CFG STATUS
ACKNOWLEDGE/readback. It did **not** establish a virtqueue or transfer sector
payload bytes.

The mechanism chain is now proven and closed through GitHub #82 /
`WSM-OS-VIRTIO-BLK-DATA-IO-Q6B`:

```text
D2 discovery/MMIO STATUS witness
  -> #84 proved guest-physical DMA page
  -> #88 bounded modern split-ring queue0
  -> #89 real 512-byte IN/OUT/FLUSH + host digest
  -> #90 fail-closed block falsifier matrix
  -> #92 Boot A write+flush / Boot B fresh-read on the same raw disk
```

Merge `721bf004e837aaaa938f1ae940a5fb1970f4c38c` confirms the narrow
Q6b claim **same-disk clean-restart persistence**. Boot B reuses the exact same
separate raw image, recreates runtime/virtqueue state, reads the persisted
sector, verifies the exact bytes, and leaves the medium unchanged.

This does **not** close the full #77 data-format/semantic ladder. The next Q6b
slice still has to store and validate the canonical framed envelope
(magic/version/length/checksum/payload), prove corruption/truncation negatives,
reconstruct/evaluate through the F6 adapter boundary, and pass the SENS-owned
L0→L3 parity witness.

Production implementation follows ADR-004: Lisp owns device/request policy;
x86-64 assembly owns irreducible PCI/MMIO/DMA/queue/fence mechanism. Retired
Rust storage crates remain specification/evidence donors only.

### Filesystem and envelope ordering

Q6b does not require FAT. First prove that bytes cross the real block device and
survive a clean reboot on the same separate raw data image. Then reuse the F6
adapter boundary for canonical envelope/content validation and finally compare
the reconstructed/evaluated result through the SENS-owned L0→L3 oracle law.

A read-only FAT16/32 projection can be added later for interoperability, but it
must not substitute for real block persistence evidence.

A RAM-disk may remain a fast mechanism test but never counts as persistence.
