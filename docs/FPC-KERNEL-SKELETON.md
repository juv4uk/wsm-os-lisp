# Freestanding Pascal: Linux control and embedded UEFI witnesses
*Freestanding Pascal: Linux control and embedded UEFI witnesses*

**Оновлено:** 2026-11-27  
**Статус:** Linux-target UNIT control and embedded UNIT/QEMU witness pass; embedded Pascal BootInfo handoff P1 gate is now automated.

## 1. Чинна модель

Kernel-facing Pascal code is a `unit`, not a `program`. The assembly entry owns startup, stack, BootInfo parsing/runtime context, and system services. A Pascal unit exports a narrow function with an explicit System V AMD64 ABI and imports only the Assembly mechanisms it actually uses.

- `src/pascal_probe.pas` is a unit and is the FPC 3.2.2 Linux-target control.
- `src/pascal_handoff.pas` is a unit that reads BootInfo, validates the Optional tag/value, and compares its result with the independent Assembly reader.
- `src/rtl_min.s` is retained as historical evidence of early no-op PROGRAM hooks. Active unit-control and embedded handoff scripts no longer link it.

## 2. Linux-target control

`scripts/check-fpc-kernel-skeleton.sh` pins FPC 3.2.2 and compiles `src/pascal_probe.pas` with `-Tlinux -Cn`. The resulting unit object has only one undefined symbol, `wsm_cons`, which is implemented by `src/runtime.s`. It links directly into the existing UEFI image without no-op RTL satisfiers.

`scripts/check-pascal-handoff.sh` remains the FPC 3.2.2 Linux-target control for BootInfo parsing. It compiles the handoff unit and uses explicit section garbage collection only for unused type metadata; it does not link `src/rtl_min.s`.

## 3. Embedded target witness

The pinned FPC 3.3.1 `x86_64-embedded` snapshot is checksum-pinned in [FPC-EMBEDDED-PROBE-2026-11-27.md](research/FPC-EMBEDDED-PROBE-2026-11-27.md). It compiles a Pascal unit, links into the existing UEFI image, and boots in OVMF/QEMU without no-op RTL stubs. A controlled Assembly callee and Pascal callback exercise Microsoft x64 ABI function-pointer/callback behavior.

## 4. BootInfo handoff P1

`scripts/check-fpc-embedded-pascal-handoff.sh` compiles `src/pascal_handoff.pas` with the pinned embedded compiler and runs four UEFI/QEMU cells:
- valid BootInfo;
- missing BootInfo;
- invalid Optional tag;
- Some tag with zero physical-memory offset.

The Pascal unit reads the record itself and compares it with the independent Assembly value. The final kernel must have an empty `nm -u`; the exact pre-link import set is `RTTI_$SYSTEM_$_BYTE$indirect` plus `saved_boot_info`, `wsm_target_phys_mem_offset`, `wsm_cons` and `wsm_fail_src`. The unused Byte RTTI metadata section is removed by the explicit test-profile `--gc-sections` pass. No no-op RTL hooks are used.

## 5. Program lifecycle is a separate runtime

A minimal FPC PROGRAM has five startup/init/finalization/threadvar hooks. A PROGRAM using threadvar and class exceptions has a substantially larger set of exception, Object/VMT and threadvar dependencies. These are classified by `scripts/probe-fpc-embedded.sh`; they are not implemented by the kernel UNIT path. Do not turn a Pascal PROGRAM into a kernel entry until those services have a real runtime contract and positive/negative witnesses.

## 6. Boundaries

- The embedded unit witness does not authorize production migration.
- Assembly remains the owner of the production entry, BootInfo parsing, stack, runtime and device mechanisms.
- P1 proves the bounded BootInfo handoff path only when the new four-cell embedded QEMU gate passes; P2 still requires semantic parity and the measured edit-build-test loop.
- `src/rtl_min.s` is historical only; active unit tests do not link its no-op symbols.
