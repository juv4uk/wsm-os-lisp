# FPC x86_64-embedded: перший compile/link свідок
*FPC x86_64-embedded: first compile/link witness*

**Дата:** 2026-11-27  
**Issue:** [#113](https://github.com/juv4uk/wsm-os-lisp/issues/113)  
**Статус:** COMPILE + FREESTANDING LINK PASS; UEFI/QEMU acceptance remains OPEN.

## 1. Точна upstream-публікація / Exact upstream artifact

URL архіву:
`https://downloads.freepascal.org/fpc/snapshot/trunk/x86_64-embedded/fpc-3.3.1.x86_64-embedded.built.on.x86_64-linux.tar.gz`

| Поле | Зафіксоване значення |
|---|---|
| Архівний розмір | 5,439,712 bytes |
| SHA-256 архіву | `a3e9e0a01c06b28acee6aca51c9d7a2980d965ac5180e8f53700fd2e000182a7` |
| README generation | 2026-11-27 13:38 |
| FPC version | `3.3.1-22061-g2e77266e1e` |
| FPC source commit | `2e77266e1eafbc802fcb93f59eab356eb588263d` |
| FPC build-repository commit | `712d9f81225c1da6d5e5feb3922d71f18df33778` |
| Compiler binary | `bin/x86_64-linux/ppcrossx64` |
| Embedded RTL | `units/x86_64-embedded/rtl` |

Це новіший snapshot, ніж записаний у первинному звіті від 2026-11-26. Upstream каталог має рухомий вміст; тому URL сам по собі не є pin. Наш harness тепер fail-closed перевіряє одночасно archive SHA-256, source commit і compiler version.

## 2. Компіляція / Compile

Команда:

```sh
ppcrossx64 -Tembedded -Px86_64 -n \
  -Fu<extracted>/units/x86_64-embedded/rtl \
  -FU<out>/units -FE<out>/bin -Cn -O- -al \
  tests/fpc_embedded_probe.pas
```

Результат:
- exit code 0;
- object: ELF 64-bit LSB relocatable, x86-64;
- object size: 1,224 bytes;
- exported symbol: `wsm_fpc_embedded_probe`;
- `nm -u fpc_embedded_probe.o`: порожньо.

Функція приймає два `LongInt` за значенням і повертає `LongInt`. Вона не використовує heap, exceptions, threadvar, I/O або RTL-сервіси. Це навмисно вузький freestanding slice.

## 3. Лінкування / Link

Окремий Assembly entry `tests/fpc_embedded_entry.s` задає `_start`, передає 40 і 2 у `%edi/%esi`, викликає експортований Pascal symbol і зупиняється через `hlt`. Це перевіряє реальне з'єднання ASM → FPC object, не створюючи фальшивих RTL stubs.

```sh
as --64 tests/fpc_embedded_entry.s -o fpc_embedded_entry.o
ld -T src/linker.ld -Map=embedded-link.map \
  -o embedded-link.elf fpc_embedded_entry.o fpc_embedded_probe.o
```

Результат:
- assembler exit code 0;
- linker exit code 0;
- фінальний образ — ELF64 x86-64 statically linked executable;
- entry point: `0x100000`;
- розмір: text 68 bytes, data 0, bss 0;
- `nm -u embedded-link.elf`: порожньо;
- disassembly показує аргументи через `RDI/RSI`, результат через `EAX`.

Це доводить, що для цього простого embedded Pascal unit не потрібні п'ять Linux RTL hooks із контрольного `-Tlinux` експерименту. Воно **не** доводить, що повна FPC RTL або програма з unit initialization/exceptions/threadvar готова до нашого ядра.

## 4. Чому P0 залишається відкритим / Why P0 remains open

- Не виконано UEFI/QEMU boot witness із повним чинним BootInfo handoff.
- Не перевірено EFI function pointers і callbacks через `MS_ABI_Default` на реальному виклику.
- Не перевірено stack/shadow-space/callee-saved поведінку на callback межі.
- Не перевірено FPC program startup, initialization/finalization, exceptions або threadvar.
- Мінімальний link witness має власний тестовий `_start`; це не production boot chain.

Отже: **FPC x86_64-embedded compile/link для мінімального Pascal unit — PASS; UEFI target acceptance — OPEN.** Не переносити висновок на повний kernel/runtime і не замінювати `src/runtime.s` на цьому доказі.

## English summary

The exact 2026-11-27 FPC 3.3.1 x86_64-embedded snapshot is now pinned by archive SHA-256, source commit, and compiler version. A minimal Pascal unit compiles to an ELF64 object with no undefined symbols. An Assembly entry calls the exported Pascal function and links through the repository linker script into a static ELF64 image with an empty undefined-symbol table. This is a compile/link witness only; UEFI BootInfo handoff, Microsoft x64 EFI callbacks, runtime initialization, and QEMU boot remain unverified.
