# ДОКАЗ МАШИННОГО ПРИМІТИВУ LISP: RDTSC (VERTICAL SLICE)
# LISP MACHINE PRIMITIVE EVIDENCE: RDTSC (VERTICAL SLICE)

**Дата:** 2026-09-14  
**Статус:** ПІДТВЕРДЖЕНО (CONFIRMED) / QEMU WITNESS PASS  
**Архітектура:** Pure Lisp + CML + x86-64 Machine Primitive (Zero Rust, Zero C Runtime)

---

## 1. УКРАЇНСЬКА ВЕРСІЯ (UKRAINIAN VERSION)

### Мета та архітектурний принцип
Цей документ фіксує виконання фундаментальної директиви власника:
> **LISP Є ЄДИНИМ ДЖЕРЕЛОМ СИСТЕМНОЇ ЛОГІКИ. ASM Є ЛИШЕ БЕЗПОСЕРЕДНІМ МАШИННИМ МЕХАНІЗМОМ.**
> **Ми не переписуємо ОС з Rust на assembler. Ми будуємо ОС на Lisp, якому assembler дає доступ до фізичної машини.**

Жодних трансляторів `Rust -> ASM` чи `C -> ASM`. Жодного проміжного runtime на Rust чи C у production pipeline.

### Вертикальний зріз (Vertical Slice)
Реалізовано наскрізний ланцюжок від виразу мовою Lisp до виконання фізичної інструкції процесора `rdtsc`:

```text
               Lisp джерело
         (def ticks (rdtsc)) ticks
                     │
                     ▼
           Canon Semantic Registry
       ID 1153: (en rdtsc) / (uk такти-процесора)
                     │
                     ▼
                    CML
        Ir::MachinePrim(MachineOp::Rdtsc)
                     │
                     ▼
       Згенерований чистий x86-64 ассемблер
          .s файл із інструкцією `rdtsc`
                     │
                     ▼
        Freestanding Builder (as + ld)
   Лінк виключно з мінімальним субстратом (entry.s + runtime.s)
                     │
                     ▼
               UEFI GPT Образ
                     │
                     ▼
                   QEMU
                     │
                     ▼
        Реальне значення тактів CPU
      WSM-OS RESULT value=27782023910
```

### Докази виконання (Evidence)

1. **Семантичний канон (`my-lisp`):**
   - У `lib/surface/semantic-registry.lisp` додано запис:
     `(1153 (en rdtsc stable) (uk такти-процесора stable) (sa kāla-spanda candidate))`
   - Згенеровано проекцію `lib/generated/meta-semantic-registry.lisp`.

2. **Компілятор CML (`cml`):**
   - Додано `MachineOp::Rdtsc` та `Ir::MachinePrim` до IR.
   - Розпізнавання семантичного ID 1153 як машинного примітиву з нульовою арністю.
   - Пряме зниження (lowering) в інструкції x86-64:
     ```asm
     rdtsc
     shlq $32, %rdx
     orq %rdx, %rax
     movabsq $0x0FFFFFFFFFFFFFFF, %rcx
     andq %rcx, %rax
     shlq $3, %rax
     orq $3, %rax
     ```
   - Цикли зчитуються в `EDX:EAX`, об'єднуються в 64-бітне ціле, маскуються під діапазон фікснуму і тегуються як канонічний Fixnum (tag 3).

3. **Згенерований асемблер (`artifacts/rdtsc-fixture.s`):**
   ```asm
   .text
   .globl wsm_entry
   .type wsm_entry, @function
   wsm_entry:
       pushq %r12
       subq $32, %rsp
       movq %rdi, %r12
       rdtsc
       shlq $32, %rdx
       orq %rdx, %rax
       movabsq $0x0FFFFFFFFFFFFFFF, %rcx
       andq %rcx, %rax
       shlq $3, %rax
       orq $3, %rax
       movq %rax, .Ldata_word_0(%rip)
       movq .Ldata_word_0(%rip), %rax
       addq $32, %rsp
       popq %r12
       ret
   .size wsm_entry, .-wsm_entry
   .section .bss
   .align 8
   .Ldata_word_0:
       .quad 0
   .section .note.GNU-stack,"",@progbits
   ```

4. **Результат запуску QEMU (`scripts/rebuild-and-run-rdtsc-qemu.sh`):**
   ```text
   WSM-OS BOOT schema=1 arch=x86_64 status=ok
   WSM-OS RESULT schema=1 value=27782023910 status=ok
   SUCCESS: Witness passed. Read 27782023910 CPU ticks directly from physical hardware.
   ```

---

## 2. ENGLISH VERSION

### Purpose and Architecture Principle
This document records the completion of the owner's foundational directive:
> **LISP IS THE SOLE SOURCE OF SYSTEM LOGIC. ASM IS ONLY THE DIRECT MACHINE MECHANISM.**
> **We do not rewrite the OS from Rust to assembly. We build the OS in Lisp, with assembly granting direct access to the physical machine.**

Zero `Rust -> ASM` or `C -> ASM` source translators. Zero intermediate Rust or C runtime in the production pipeline.

### Vertical Slice Verification
An end-to-end vertical slice from Lisp source code down to physical CPU execution of the `rdtsc` instruction:
1. **Lisp Source:** `(def ticks (rdtsc)) ticks`
2. **Canon Registry:** ID 1153 maps both English `rdtsc` and Ukrainian `такти-процесора`.
3. **CML Compiler:** Lowers directly to `Ir::MachinePrim(MachineOp::Rdtsc)`.
4. **Assembly Emission:** Generates raw x86-64 instructions (`rdtsc`, bit shifting, canonical WSM Fixnum tagging).
5. **Freestanding Link:** GNU `as` + GNU `ld` links only `entry.o` + `runtime.o` + `rdtsc-fixture.o`.
6. **UEFI Boot & QEMU Witness:** Boots via OVMF, runs `wsm_entry`, outputs the live tick counter `value=27782023910` via COM1 serial.
