# Local QEMU witness / Локальний QEMU-свідок

Always rebuild the kernel and UEFI image before a local run. A pre-existing
`target/wsm-os-uefi.img` may belong to an older runtime/ABI and can emit a
structured condition while the committed transcript expects the current
fixture result.

Перед локальним запуском завжди перебудовуйте kernel та UEFI image. Старий
`target/wsm-os-uefi.img` може належати попередній версії runtime/ABI й давати
structured condition, тоді як committed transcript очікує актуальний fixture.

```bash
OVMF_CODE=/gnu/store/.../share/firmware/ovmf_code_x64.bin \
OVMF_VARS=/gnu/store/.../share/firmware/ovmf_vars_x64.bin \
scripts/rebuild-and-run-qemu.sh
```

The wrapper follows the CI order: bare-metal kernel build, UEFI image
creation, then `run-qemu-uefi.sh` with its bounded timeout and transcript
comparison. The result remains `QEMU-BOOT-PARITY`, not physical hardware
evidence.

Wrapper повторює порядок CI: збірка bare-metal kernel, створення UEFI image,
потім `run-qemu-uefi.sh` з bounded timeout і порівнянням transcript. Результат
залишається `QEMU-BOOT-PARITY`, а не evidence фізичного обладнання.

## FS fixture / FS fixture

The WSM FS machine witness is a separate image and does not replace the frozen
compiler fixture:

```bash
OVMF_CODE=/gnu/store/.../share/firmware/ovmf_code_x64.bin \
OVMF_VARS=/gnu/store/.../share/firmware/ovmf_vars_x64.bin \
scripts/rebuild-and-run-fs-qemu.sh
```

It embeds the canonical two-record F6 stream, validates the exact bounded
fixture bytes, materializes a small cons value, and prints a canonical FS
observation. This is a read-only machine witness; it is not a disk driver or
power-loss durability proof.

Окремий FS witness вбудовує канонічний двозаписний F6 stream, перевіряє точні
bounded bytes, materializes мале cons-значення й друкує canonical FS
observation. Це read-only machine witness, а не disk driver і не доказ
power-loss durability.
