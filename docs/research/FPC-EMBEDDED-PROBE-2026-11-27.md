# FPC x86_64-embedded: compile/link та MS ABI witness
*FPC x86_64-embedded: compile/link and MS ABI witness*

**Дата:** 2026-11-27  
**Issue:** [#113](https://github.com/juv4uk/wsm-os-lisp/issues/113)  
**Статус:** EMBEDDED COMPILE + STATIC LINK + MS ABI CODEGEN PASS; UEFI/QEMU runtime acceptance remains OPEN.

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

Upstream snapshot URL є рухомим; тому URL сам по собі не є pin. Harness fail-closed перевіряє archive SHA-256, source commit і compiler version.

## 2. Компіляція / Compile

Команда:

```sh
ppcrossx64 -Tembedded -Px86_64 -n \
  -Fu<extracted>/units/x86_64-embedded/rtl \
  -FU<out>/units -FE<out>/bin -Cn -O- -al \
  tests/fpc_embedded_probe.pas
```

Поточний розширений зріз:
- compile exit code 0;
- object: ELF64 relocatable x86-64, 2,808 bytes;
- exported symbols: `wsm_fpc_embedded_probe`, `wsm_invoke_efi_probe`, `wsm_efi_callback`;
- object має один unresolved metadata symbol `RTTI_$SYSTEM_$$_QWORD$indirect`, який походить від процедурного типу. Це не виклик runtime-функції.

## 3. Microsoft x64 ABI / UEFI calling-convention codegen

У Pascal unit оголошено:

- `TEfiProbeFunction = function(A, B, C, D: QWord): QWord; MS_ABI_Default`;
- `wsm_invoke_efi_probe` викликає переданий function pointer із чотирма аргументами;
- `wsm_efi_callback` експортується з `MS_ABI_Default`.

Згенерований FPC assembly містить:
- аргументи function-pointer call у `RCX/RDX/R8/R9`;
- непрямий `call *Fn`;
- callback entry читає перші два аргументи з `RCX/RDX`;
- FPC виділяє stack frame, що включає Microsoft x64 home/shadow area.

Тестовий Assembly entry:
- викликає Pascal callback за Microsoft x64 convention, резервуючи 32-byte shadow space;
- містить перевірку alignment `RSP mod 16 = 8` у EFI-shaped stub;
- записує всі чотири 8-byte home slots;
- перевіряє збереження `RBX/RDI/RSI/R12-R15` після callback.

Це **статична перевірка згенерованого коду та зв'язування**, а не runtime-виконання цих інструкцій. EFI-shaped stub — контрольний assembly callee, не UEFI firmware function.

## 4. Лінкування / Link

```sh
as --64 tests/fpc_embedded_entry.s -o fpc_embedded_entry.o
ld --gc-sections -T src/linker.ld -Map=embedded-link.map \
  -o embedded-link.elf fpc_embedded_entry.o fpc_embedded_probe.o
```

`--gc-sections` відкидає не використаний процедурний RTTI section, що містить єдине object-level unresolved metadata reference. Це не stub і не підміна функції. Фінальна перевірка `nm -u` має бути порожньою; будь-який залишковий undefined symbol — fail.

Поточний локально перевірений результат:
- assembler exit code 0;
- linker exit code 0;
- ELF64 x86-64 statically linked executable;
- entry point: `0x10003e`;
- text=552 bytes, data=0, bss=4096;
- фінальний `nm -u` — порожньо.

## 5. Межа доказу / Evidence boundary

Доведено:
- pinned FPC 3.3.1 x86_64-embedded компілює вузький Pascal unit;
- об'єкт має ELF64 формат;
- System V AMD64 cdecl та Microsoft x64 ABI codegen для function pointer/callback присутні у generated assembly;
- ASM entry + Pascal object зв'язуються через наш linker script без фінальних undefined symbols.

Ще не доведено:
- реальне виконання ELF або QEMU UEFI boot;
- виклик через справжню UEFI System Table/Boot Services;
- реальний BootInfo handoff у поточний kernel;
- фактичне виконання shadow-space, stack-alignment та callee-saved runtime assertions;
- FPC program startup, unit initialization/finalization, exceptions, threadvar або повну RTL;
- сумісність усіх FPC embedded targets із нашою production boot chain.

Отже: **мінімальний embedded compile/link + статичний MS ABI witness — PASS; UEFI/QEMU runtime acceptance — OPEN.** Не переносити цей висновок на повний kernel/runtime і не замінювати `src/runtime.s` на цьому доказі.

## English summary

The pinned FPC 3.3.1 x86_64-embedded snapshot compiles the Pascal probe to ELF64. Generated assembly confirms System V cdecl plus Microsoft x64 `MS_ABI_Default` function-pointer and callback code generation. A freestanding assembly entry and the Pascal object link through the repository linker script; `--gc-sections` removes an unused procedural RTTI metadata section, and the final undefined-symbol table is empty. The linked ABI assertions have not yet been executed: real UEFI Boot Services, BootInfo handoff, and QEMU boot remain unverified.
