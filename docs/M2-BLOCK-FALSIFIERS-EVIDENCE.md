# M2 virtio-blk fail-closed evidence (#82)

The positive data path is already proved by the sector-0 roundtrip witness:

```
IN fresh zero -> OUT 512 bytes -> FLUSH -> IN same bytes
```

This companion matrix attacks the dynamic failure points without creating a second transport implementation.

## Dynamic falsifiers

The same QEMU roundtrip probe is rebuilt with one test-only mutation at a time. Every case must return the bounded failure observation and leave sector 0 unchanged:

- queue size unsupported;
- invalid queue/notify geometry;
- FLUSH treated as unavailable;
- forced finite completion timeout;
- nonzero VirtIO request status.

## Failures excluded by construction

Three issue obligations are already structurally closed rather than represented by a second runtime input surface:

- DMA translation unavailable is proved fail-closed by #84;
- descriptor/ring address overflow is eliminated because every published address is an in-page offset inside #84's proved contiguous 4096-byte physical arena;
- the admitted request constructor has no sector argument and writes literal sector 0, so an out-of-bound sector cannot enter this first bounded transport vertical.

The last point is deliberate: broader sector addressing must introduce its own bound contract before it can become an input.

## Claim boundary

Passing this matrix closes the first real block-I/O mechanism only. It does not prove clean-restart persistence; that remains #77.
