# F6 read-only filesystem adapter / Read-only adapter F6

`wsm-os-fs-adapter` is the boundary between the opaque `wsm-os-block` medium
and a higher-level WSM envelope/reconstruction implementation.

`wsm-os-fs-adapter` — межа між непрозорим block medium і вищим шаром WSM
envelope/reconstruction.

## Ownership / Власність

```text
wsm-os-block       → fixed blocks, checksum, flush, corruption errors
wsm-os-fs-adapter  → bounded record extraction and atomic validation handoff
my-lisp            → WSM envelope meaning and root reconstruction
wsm-os             → boot/runtime integration
```

Adapter deliberately does not parse or evaluate WSM values. Its
`read_validated_image` function reads non-empty blocks and calls a supplied
validator for each record. Any validation failure aborts the whole result;
there is no partial image return.

Adapter навмисно не парсить і не виконує WSM values. `read_validated_image`
читає непорожні blocks і викликає переданий validator для кожного record.
Будь-яка validation failure відхиляє весь результат; partial image не
повертається.

## Evidence / Доказ

The current crate tests prove reopen/read of two records and atomic rejection
of a rejected record. They do not yet prove the real `my-lisp` envelope parser,
root reconstruction, power-loss durability, or device ordering.

Поточні crate-тести доводять reopen/read двох records і atomic rejection
відхиленого record. Вони ще не доводять реальний parser envelopes із
`my-lisp`, root reconstruction, power-loss durability або ordering пристрою.

The `wsm-fs-image-reader` binary now provides a bounded producer/consumer
witness: it accepts exactly two non-empty UTF-8 records, writes and flushes a
file-backed image, reopens it, and validates the envelope prefix atomically.
This is only a framing/medium witness; it deliberately does not claim WSM
reconstruction or semantic validation.

`wsm-fs-image-reader` тепер дає bounded producer/consumer witness: приймає
рівно два непорожні UTF-8 records, записує і flush-ить file-backed image,
повторно відкриває її та атомарно перевіряє envelope prefix. Це лише witness
межі framing/medium; він навмисно не заявляє WSM reconstruction або semantic
validation.

## Next integration contract / Наступний контракт інтеграції

The next witness must provide a real validator callback backed by the canonical
`my-lisp` envelope format and compare the reconstructed root/content-id. The
adapter API itself should remain generic; WSM semantics must not be copied into
this crate.

Наступний witness має надати справжній validator callback на основі canonical
формату envelopes `my-lisp` і порівняти реконструйований root/content-id.
Сам adapter API має залишатися generic; WSM semantics не копіюються в цей
crate.
