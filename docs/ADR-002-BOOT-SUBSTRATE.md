# ADR-002: Boot Substrate Selection

**Status:** ACCEPTED AND EXECUTABLE
**Date:** 2026-08-29

## Context

`wsm-os` targets the owner's Gigabyte H170-Gaming 3 through UEFI and uses QEMU
as the first machine witness. The initial implementation temporarily used
`bootloader` 0.9 with `cargo bootimage`, which produced a real legacy image but
contradicted the accepted UEFI design. Documenting that implementation as the
final decision would remove the contradiction only on paper while preserving
the wrong target path.

## Decision

Use `bootloader` and `bootloader_api` **exactly 0.11.17**:

- `wsm-os-kernel` depends only on `bootloader_api` and exposes the v0.11
  `fn(&'static mut BootInfo) -> !` entry point;
- the hosted `wsm-os-image` tool depends on the UEFI-only `bootloader` feature
  and converts the already-built kernel ELF into a FAT/GPT UEFI disk image;
- `cargo bootimage`, the v0.9 kernel API, and an implicit Cargo runner are not
  part of this path.

The toolchain is pinned to **nightly-2026-07-27** with `rust-src`,
`llvm-tools-preview`, and `x86_64-unknown-none`. This date matches the
`bootloader` 0.11.17 release window. The moving 2026-08-29 nightly was tested
and rejected because its UEFI link failed on an unresolved `wcslen` symbol.

## Boundaries

- The kernel owns WSM runtime/entry semantics, not disk-image construction.
- The image tool owns packaging only; it does not parse or evaluate WSM.
- QEMU firmware selection, serial capture, `isa-debug-exit`, and timeout are
  explicit test-harness responsibilities in M3C.
- Creating a non-empty UEFI image proves image construction, not successful
  boot, serial output, oracle parity, or physical-hardware parity.

## Licensing

`bootloader` and `bootloader_api` are dual-licensed `MIT OR Apache-2.0`.
This is compatible with the repository's MIT policy. Dependency source and
license remain recorded by Cargo; no third-party source is copied into this
repository.

## Required evidence

```text
kernel using bootloader_api 0.11.17
  -> x86_64-unknown-none ELF
  -> UefiBoot image builder 0.11.17
  -> non-empty UEFI disk image
```

The next M3C task must boot that exact image under QEMU/OVMF and produce the
versioned serial witness. It must not fall back to a BIOS image.

## Primary sources

- [`bootloader` README](https://github.com/rust-osdev/bootloader)
- [`v0.9` migration guide](https://github.com/rust-osdev/bootloader/blob/main/docs/migration/v0.9.md)
- [`bootloader` v0.11.17 release commit](https://github.com/rust-osdev/bootloader/commit/ec8a8b4b59bd94f3c0280adc1bcdae530251b003)

---

# ADR-002: Вибір boot-субстрату (український переклад)

**Статус:** ПРИЙНЯТО І ВИКОНУВАНО
**Дата:** 2026-08-29

## Контекст

`wsm-os` націлений на материнську плату власника Gigabyte H170-Gaming 3 через
UEFI і використовує QEMU як першого машинного свідка. Початкова реалізація
тимчасово використала `bootloader` 0.9 з `cargo bootimage`, що створювало
справжній legacy-образ, але суперечило прийнятому UEFI-дизайну. Зафіксувати
цю реалізацію як остаточне рішення усунуло б суперечність лише на папері,
зберігаючи при цьому хибний цільовий шлях.

## Рішення

Використовувати `bootloader` та `bootloader_api` **рівно 0.11.17**:

- `wsm-os-kernel` залежить лише від `bootloader_api` і надає точку входу v0.11
  `fn(&'static mut BootInfo) -> !`;
- хостовий інструмент `wsm-os-image` залежить лише від UEFI-функції `bootloader`
  і перетворює вже зібраний kernel ELF на FAT/GPT UEFI дисковий образ;
- `cargo bootimage`, kernel-API v0.9 та неявний Cargo-runner не входять у цей
  шлях.

Toolchain зафіксовано на **nightly-2026-07-27** з `rust-src`,
`llvm-tools-preview` та `x86_64-unknown-none`. Ця дата збігається з вікном
релізу `bootloader` 0.11.17. Рухливий nightly 2026-08-29 тестувався і був
відхилений, бо його UEFI-лінк провалився на нерозв'язаному символі `wcslen`.

## Межі

- Kernel володіє семантикою WSM рантайму/входу, а не конструюванням дискового
  образу.
- Інструмент образу володіє лише пакуванням; він не розбирає й не обчислює WSM.
- Вибір QEMU-прошивки, захоплення serial, `isa-debug-exit` і таймаут — явні
  обов'язки тестового harness'а в M3C.
- Створення непорожнього UEFI-образу доводить конструювання образу, а не
  успішне завантаження, serial-вивід, parity з оракулом чи parity з фізичним
  залізом.

## Ліцензування

`bootloader` та `bootloader_api` мають подвійну ліцензію `MIT OR Apache-2.0`.
Це сумісно з політикою MIT у репозиторії. Джерело й ліцензія залежностей
залишаються під контролем Cargo; жоден third-party код не копіюється в цей
репозиторій.

## Необхідний evidence

```text
kernel, що використовує bootloader_api 0.11.17
  -> x86_64-unknown-none ELF
  -> UefiBoot image builder 0.11.17
  -> непорожній UEFI дисковий образ
```

Наступна задача M3C має завантажити саме цей образ під QEMU/OVMF і видати
версійний serial-свідок. Вона не повинна відкочуватися на BIOS-образ.

## Першоджерела

- [README `bootloader`](https://github.com/rust-osdev/bootloader)
- [міграційний гайд v0.9](https://github.com/rust-osdev/bootloader/blob/main/docs/migration/v0.9.md)
- [релізний коміт `bootloader` v0.11.17](https://github.com/rust-osdev/bootloader/commit/ec8a8b4b59bd94f3c0280adc1bcdae530251b003)
