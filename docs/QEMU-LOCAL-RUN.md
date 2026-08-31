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
