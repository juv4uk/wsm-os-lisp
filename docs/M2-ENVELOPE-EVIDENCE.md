# M2 canonical framed persistence envelope (#95)

This slice sits above the completed virtio-blk mechanism and confirmed same-disk clean restart. It deliberately adds **one data-format contract**, not a filesystem.

## Exact 512-byte frame

| Offset | Size | Field |
|---:|---:|---|
| 0 | 8 | ASCII magic `WSMENV01` |
| 8 | 4 | little-endian version = 1 |
| 12 | 4 | little-endian header length = 32 |
| 16 | 4 | little-endian payload length, bounded to 480 |
| 20 | 4 | FNV-1a32 of payload |
| 24 | 8 | reserved = 0 |
| 32 | variable | opaque payload |
| remainder | - | zero padding |

The first admitted payload is exactly 16 opaque bytes: `SENS-Q6B-PAYLOAD`.

FNV-1a32 is used only as the in-format corruption checksum. It is not treated as a cryptographic identity. CI separately records SHA-256 for the sector, payload, boot images, runtime source and machine profile.

## Authority boundary

The block/envelope layer may prove:
- framing;
- length bounds;
- checksum integrity;
- clean-restart survival;
- corruption rejection.

It may **not** decide what the payload means. The payload remains opaque until a later F6 adapter/reconstruction slice supplies an upstream validator/evaluator.

No native/runtime pointer is persisted.

## Negative matrix

A valid Boot-A image is copied and independently mutated. A fresh Boot-B verifier must reject:
- wrong magic;
- wrong version;
- wrong header length;
- declared payload length beyond the remaining sector;
- checksum mismatch;
- payload corruption without checksum update.

Every negative verifier is read-only and CI requires the entire mutated image digest to remain unchanged across the failed boot.

## Claim boundary

Passing this witness earns:
**canonical framed sector survives clean restart and corruption fails closed**.

It does not earn:
- filesystem semantics;
- SENS semantic parity;
- crash/power-loss durability.
