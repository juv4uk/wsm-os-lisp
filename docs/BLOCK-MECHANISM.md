# WSM block mechanism v0 / Механізм блоків WSM v0

`wsm-os-block` is a hosted, file-backed mechanism-only prototype for the
filesystem roadmap F5. It stores opaque bytes in fixed-size blocks. It does
not know WSM values, names, roots, journal events, or evaluation.

`wsm-os-block` — hosted прототип механізмного рівня F5 на file-backed medium.
Він зберігає непрозорі bytes у блоках фіксованого розміру й не знає про
значення WSM, імена, roots, journal-події чи evaluation.

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

```rust
read_block(index) -> Result<Vec<u8>, BlockError>
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

The crate currently proves seven small properties: round-trip after flush,
bounds/payload rejection, distinction between unwritten and corrupt blocks,
malformed-header rejection, truncated-block rejection, and byte-identical
images for identical writes, and explicit flush-failure propagation. These are
F5 mechanism evidence;
they do not prove WSM FS reconstruction, journal replay, root publication,
QEMU integration, or real-device persistence.

Крейт наразі доводить сім малих властивостей: round-trip після flush,
відхилення bounds/payload, розрізнення unwritten і corrupt block, відхилення
malformed header, відхилення truncated block і byte-identical image для
однакових записів і явне поширення помилки flush. Це evidence механізму F5, а не
доказ реконструкції WSM FS, journal replay, root publication, QEMU чи реального
пристрою.
