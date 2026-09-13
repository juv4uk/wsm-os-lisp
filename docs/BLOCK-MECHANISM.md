# WSM block mechanism v0 / Механізм блоків WSM v0

> [!IMPORTANT]
> **Architectural Ratification (2026-09-14, [ADR-004](ADR-004-LISP-ASSEMBLY-PURE-ARCHITECTURE.md)):**
> The former `crates/wsm-os-block` Rust implementation has been retired under the zero-Rust directive.
> Production storage and block mechanisms are implemented directly in Lisp, interfacing
> with low-level disk/controller registers through pure assembly capability primitives.
> / Колишню реалізацію `crates/wsm-os-block` на Rust вилучено відповідно до директиви RUST = 0.
> Механізми збереження та роботи з блоками реалізуються безпосередньо на Lisp, взаємодіючи
> з регістрами контролерів через чисті асемблерні capability-примітиви.

`wsm-os-block` was the initial specification for the filesystem roadmap F5.
It defines fixed-size block storage for opaque bytes.

`wsm-os-block` — початкова специфікація для дорожньої карти файлової системи F5.
Вона визначає зберігання непрозорих байтів у блоках фіксованого розміру.


## On-block format / Формат блока

Each block is exactly `block_size` bytes. The first 16 bytes are:

```text
0..4    magic = WSMB
4       format version = 1
5..8    reserved = zero
8..12   payload length, little-endian u32
12..16  FNV-1a u32 checksum of payload
16..    payload, then zero padding
```

`block_size` is bounded to `16..=1 MiB`; invalid geometry is rejected before
the medium allocates a block buffer.

Кожен блок має рівно `block_size` bytes. Перші 16 bytes — header із magic,
версією, reserved-полем, довжиною payload і FNV-1a checksum. FNV-1a тут лише
виявляє пошкодження; автентичність або криптографічна цілісність не заявляються.

`block_size` обмежений діапазоном `16..=1 MiB`; неправильна геометрія
відхиляється до виділення буфера.

## API boundary / Межа API

```text
read_block(index) -> Result<Block, BlockError>
write_block(index, bytes) -> Result<(), BlockError>
flush() -> Result<(), BlockError>
```

The medium rejects invalid geometry, out-of-range indices, oversized payloads,
unwritten blocks, malformed headers, truncation, and checksum mismatch. `flush`
uses the hosted file's `sync_data`; this is not yet a power-loss durability
witness.

Механізм відхиляє неправильну геометрію, індекси поза межами, завеликий
payload, невикористані блоки, malformed headers, truncation і checksum mismatch.
`flush` використовує hosted `sync_data`; це ще не доказ стійкості до power loss.

## Evidence / Доказ

The crate currently proves fifteen small properties: round-trip after flush,
bounds/payload rejection, distinction between unwritten and corrupt blocks,
malformed-header rejection, truncated-block rejection, and byte-identical
images for identical writes, explicit flush-failure propagation, reopen after
flush, rejection of a partially persisted block, and an explicit injected
partial-write failure, plus broker rejection of unknown media, invalid geometry,
and path traversal. These are
F5 mechanism evidence;
they do not prove WSM FS reconstruction, journal replay, root publication,
QEMU integration, or real-device persistence.

Крейт наразі доводить п’ятнадцять малих властивостей: round-trip після flush,
відхилення bounds/payload, розрізнення unwritten і corrupt block, відхилення
malformed header, відхилення truncated block і byte-identical image для
однакових записів, явне поширення помилки flush, читання після reopen,
відхилення частково записаного блока, явна injected partial-write failure,
а також відхилення невідомого medium, неправильної geometry і path traversal.
Це
evidence механізму F5, а не
доказ реконструкції WSM FS, journal replay, root publication, QEMU чи реального
пристрою.

The hosted broker now provides a minimal path/geometry capability boundary:
logical media are registered under a broker root and grants are required to
open them. This is not a complete OS sandbox, device authorization system,
revocation protocol, or power-loss durability witness.

Hosted broker тепер дає мінімальну межу capability для path/geometry: logical
media реєструються під broker root, а для відкриття потрібен grant. Це не
повна OS sandbox, авторизація пристроїв, протокол відкликання чи доказ
power-loss durability.
