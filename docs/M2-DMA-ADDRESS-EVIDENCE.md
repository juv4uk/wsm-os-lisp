# M2 DMA address evidence (#84)

Status: **bounded mechanism proof complete**.

This evidence exists only to unblock the first real virtio-blk virtqueue in #82. It does not create a SENS/WSM semantic operation and it does not add raw addresses to the CML target ABI.

## Proven construction

The pure x86-64 runtime reserves exactly one 4096-byte, 4096-aligned target-owned arena. At boot it walks the active CR3 page tables in reverse, using the already-proved boot physical-memory direct map only to read page-table pages. It supports 4 KiB, 2 MiB and 1 GiB leaves.

The runtime translates both the first and last byte of the arena and accepts the arena only when:

- both translations exist;
- the physical start is non-zero and 4096-aligned;
- the inclusive physical end is exactly start + 4095;
- no arithmetic or mapping invariant fails.

The resulting physical start is target-only state for later virtqueue programming.

## Evidence boundary

Ordinary WSM-OS output exposes only the bounded probe result. A test-only assembler flag adds one separate line:

```
WSM-M2 DMA schema=1 virtual=<u64> physical=<u64> length=4096 pages=1 status=1
```

The line is captured into the CI evidence artifact and never participates in the `WSM-OS RESULT` semantic schema.

## Falsifiers

The QEMU witness proves independent fail-closed mutations for:

- missing physical-memory direct map;
- forced page-table translation failure;
- forced virtual misalignment;
- forced zero physical result;
- forced non-contiguous physical end.

Two candidate failures are excluded by construction rather than merely tested:

- partial-page crossing cannot occur because the arena is exactly one page and starts at `.p2align 12`;
- for a u64 4096-aligned start, `start + 4095` cannot overflow; the greatest possible aligned start is `2^64 - 4096`, whose inclusive end is exactly `2^64 - 1`.

## Handoff

#82 may consume the proved `[physical_start, 4096]` arena for descriptor, driver, device and request buffers. Queue negotiation, notification, completion, sector I/O and FLUSH remain #82-owned.
