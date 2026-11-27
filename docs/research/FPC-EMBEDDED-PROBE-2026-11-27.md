# FPC x86_64-embedded: compile/link, ABI та UEFI/QEMU свідок
*FPC x86_64-embedded: compile/link, ABI and UEFI/QEMU witness*

**Дата:** 2026-11-27  
**Issue:** [#113](https://github.com/juv4uk/wsm-os-lisp/issues/113)  
**Статус:** bounded embedded UNIT + UEFI/QEMU + MS ABI runtime witness PASS; full PROGRAM lifecycle remains classified, not adopted.

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

Upstream snapshot URL є рухомим; URL сам по собі не є pin. Harness перевіряє archive SHA-256, source commit і compiler version. Це development snapshot, а не stable release.

## 2. Embedded UNIT compile та freestanding link

Команда:

```sh
ppcrossx64 -Tembedded -Px86_64 -n -Fu<embedded-rtl> \
  -FU<out>/units -FE<out>/bin -Cn -O- -al \
  tests/fpc_embedded_probe.pas
```

Перевірено:
- compile exit code 0;
- object — ELF64 relocatable x86-64;
- exported symbols: `wsm_fpc_embedded_probe`, `wsm_invoke_efi_probe`, `wsm_efi_callback`;
- generated assembly пройшов перевірки System V та Microsoft x64 ABI codegen;
- freestanding link із тестовим Assembly entry і чинним `src/linker.ld` — exit 0;
- фінальний `nm -u` — порожній.

Окремий kernel-oriented unit `tests/fpc_embedded_kernel_probe.pas` має лише механічні залежності, потрібні для цього шляху: чинний Assembly `wsm_cons` і test-only Microsoft ABI callee. Невикористаний procedural RTTI metadata section відкидається явним `--gc-sections` у тестовому профілі; фінальний kernel знову перевіряється на порожній undefined-symbol table. Жодних no-op RTL stubs не додається.

## 3. UEFI/QEMU та реальний Microsoft x64 ABI виклик

GitHub Actions [run #46071610953](https://github.com/juv4uk/wsm-os-lisp/actions/runs/46071610953) завершився **SUCCESS**. [Артефакт доказів](https://github.com/juv4uk/wsm-os-lisp/actions/runs/46071610953/artifacts/15232149812).

Тестовий Pascal unit:
- викликає Assembly function pointer через `MS_ABI_Default`;
- отримує від нього 22 лише якщо чотири аргументи прийшли в `RCX/RDX/R8/R9`, callback повернув очікуване значення, стек має потрібне вирівнювання й callee-saved регістри збережені;
- викликає чинний Assembly `wsm_cons` і повертає той самий tagged cons, що й ASM baseline.

Assembly callee:
- перевіряє `RSP mod 16 = 8` на вході;
- записує у чотири 8-byte Microsoft x64 home/shadow slots;
- викликає Pascal callback `wsm_efi_callback` з Microsoft x64 ABI та 32-byte shadow space;
- перевіряє `RBX/RBP/RDI/RSI/R12-R15` після callback;
- повертає success value лише після всіх перевірок.

Результат QEMU/OVMF:
```text
FPC_EMBEDDED_UNIT_COMPILE=PASS
MS_ABI_FUNCTION_POINTER_AND_CALLBACK_FIXTURE=LINKED
FREESTANDING_LINK=PASS
FINAL_KERNEL_UNDEFINED_SYMBOLS=NONE
UEFI_QEMU_BOOT=PASS
MS_ABI_FUNCTION_POINTER=PASS
MS_ABI_CALLBACK=PASS
MS_ABI_SHADOW_SPACE_ALIGNMENT_CALLEE_SAVED=PASS
FPC-EMBEDDED-KERNEL-PROBE-PASS
```

Серійний transcript побайтково звіряється з наявним `artifacts/qemu-serial-transcript.txt`. OVMF завантажує чинний bootloader; він передає керування kernel image, у якому Pascal unit виконується разом із незміненими `src/entry.s` та `src/runtime.s`.

**Межа:** Microsoft x64 ABI перевірено контрольним Assembly function pointer/callback, а не викликом реального UEFI Boot Services/System Table entry. QEMU перевіряє UEFI boot path, але Pascal unit не читає BootInfo — це лишається P1 handoff роботою.

## 4. Чому kernel path має бути UNIT, а не PROGRAM

Окремо перевірено два program lifecycle профілі на тому самому pinned embedded compiler.

### Мінімальний PROGRAM

`src/pascal_probe.pas` як Pascal `program` експортує `wsm_entry`, але його object має шість undefined symbols:
- `fpc_initializeunits`;
- `fpc_do_exit`;
- `INIT$_$SYSTEM`;
- `FINALIZE$_$OBJPAS`;
- `THREADVARLIST_$SYSTEM$indirect`;
- `wsm_cons`.

Перші п'ять — startup/initialization/finalization/threadvar dependencies; шостий — реальна функція нашого Assembly runtime.

### PROGRAM з exception + threadvar

Окремий `tests/fpc_embedded_program_features.pas` містить `threadvar`, клас-виняток, `raise` та `try/except`. Його object має 30 undefined symbols, включно з:
- `FPC_THREADVAR_RELOCATE`;
- `fpc_raiseexception`, `fpc_catches`, `fpc_setjmp`, `fpc_raise_nested`;
- `fpc_pushexceptaddr`, `fpc_popaddrstack`, `fpc_doneexception`;
- Object/VMT/constructor/destructor та System exception support.

Ці символи зберігаються в артефакті; harness не лінкує їх із порожніми заглушками. Отже, повноцінний FPC `program` startup/exception/threadvar lifecycle ще потребує окремого runtime контракту.

### Практичний висновок

**Для kernel integration зараз доведений вузький UNIT model:** Pascal надає leaf functions із явним ABI; Assembly лишається власником boot, stack, memory/runtime mechanisms і `wsm_cons`. Не переносити program startup до ядра, доки його залежності не реалізовані та не перевірені. Це не означає, що весь FPC RTL треба переписати.

## 5. Межі та наступний етап

Доведено:
- checksum-pinned `OS_TARGET=embedded CPU_TARGET=x86_64` toolchain;
- unit compile, object format, exports та freestanding link;
- Microsoft x64 function-pointer/callback codegen і runtime assertions у QEMU;
- UEFI/OVMF boot із byte-identical WSM-OS serial transcript;
- конкретний program startup/exception/threadvar dependency surface.

Ще не доведено:
- Pascal-side BootInfo validation та missing/malformed handoff negatives;
- виклик справжнього UEFI Boot Services/System Table function pointer;
- повний FPC program startup, unit initialization/finalization, exceptions/threadvar у production runtime;
- parity/production migration для інших компонентів.

Тому P0 embedded toolchain witness для UNIT path — **PASS**. P1 лишається відкритим для Pascal-side handoff boundary; P2 лишається окремим parity gate. Production `src/runtime.s` та `src/entry.s` не змінювалися; цей результат не дозволяє Pascal migration до завершення P2.

## English summary

The exact FPC 3.3.1 x86_64-embedded snapshot is pinned by SHA-256, source commit, and compiler version. A Pascal unit compiles, links into the existing UEFI/QEMU image without no-op RTL stubs, and boots with a byte-identical serial transcript. The QEMU kernel executes an indirect Microsoft x64 ABI function-pointer call and a Pascal callback, checking register arguments, stack alignment, shadow space, and nonvolatile registers. Separately, program probes classify five startup hooks for a minimal program and 30 dependencies for a threadvar/exception program. The bounded UNIT path is proven; full PROGRAM lifecycle and Pascal-side BootInfo validation remain separate work. No production runtime migration is authorized by this evidence.
