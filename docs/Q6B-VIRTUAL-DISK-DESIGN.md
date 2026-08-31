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
Q6a  guest-memory read/write/flush       CONFIRMED
Q6b  same-disk clean-restart persistence  OPEN
Q7   crash/restart recovery               OPEN
```

Do not call a clean restart proof power-loss durability. Do not silently reuse
the boot image as a writable data disk; the data medium must be a separate
disposable artifact.

Не називати clean restart доказом power-loss durability. Не використовувати
boot image як прихований writable data disk: medium має бути окремим
disposable artifact.
