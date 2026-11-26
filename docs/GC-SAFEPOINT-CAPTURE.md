# GC safepoint capture: keeping the compiler's proof until the allocator reads it

Status: **mechanism witness, executed in QEMU**. Issue #71
(`GC-ENTRY-CAPTURE-1`), parent #64, collector lane #60, root protocol #61.

```text
LAYER = MECHANISM
SEMANTIC AUTHORITY = NONE
```

This document describes what the target now records at every allocation, why
it records it there, and what is still missing before a collector may run.

---

## 1. The problem in one instruction

A precise collector needs to know exactly which words are roots. For a call
into an allocator, that knowledge belongs to the **call site**: the compiler
knows which registers hold live Lisp values at that point, and it can publish
that as a record keyed by the return address.

The target destroys that evidence immediately:

```asm
wsm_cons:
    movq 16(%rdi), %rax     # the prologue starts here
```

One instruction later `%rax` and `%rcx` are gone, and the return PC is only
recoverable from the stack if you know the frame layout — which is exactly what
you no longer know. So the capture has to happen **before** the first clobber,
as the first thing the allocator does.

There is a second, subtler failure this design refuses. If a site has no
record, the tempting shortcut is to treat it as "nothing to trace". That turns a
missing proof into a silent lie: the program keeps running with roots the
collector will not see, and the corruption appears much later, somewhere else.
So absence and emptiness are different states, and the runtime names them
differently (`NOT-A-SAFEPOINT` vs `CERTIFIED`).

## 2. What is captured

A rewriteable save area in `.bss` (`wsm_gc_safepoint`, 48 bytes), written by
both `wsm_cons` and `wsm_closure_new` before any other instruction:

| Offset | Field | Value |
| --- | --- | --- |
| +0 | `return_pc` | `*(entry_rsp)` — the final PC of the call site |
| +8 | `caller_rsp_at_call` | `entry_rsp + 8` |
| +16 | `entry rsi` | certified candidate for cons; **not** a root for closure |
| +24 | `entry rdx` | certified candidate for both allocators |
| +32 | `allocator_kind` | 1 cons, 2 closure |
| +36 | `state` | 0 none, 1 CERTIFIED, 2 NOT-A-SAFEPOINT, 3 INVALID |
| +40 | `captures` | CERTIFIED captures so far (observation only) |

Three deliberate omissions:

* **`%rdi` / `%r12` (`RuntimeContext*`) is not captured.** It is the runtime's
  own handle, not a language value. Promoting it to a root would make the
  collector keep the runtime alive through itself.
* **The stack is never scanned.** No conservative fallback: only certified
  registers are recorded.
* **No pointer-looking word is touched.** A dead value in `%rcx` or on the
  stack stays exactly where it is; it is neither saved nor followed.

## 3. The root map

`wsm_gc_root_map_register(ctx, table, count, pc_base)` installs one map per
session. It fails closed on a null table, a null base, a zero count, or a count
above 4096.

Each entry is 16 bytes:

| Offset | Field | Meaning |
| --- | --- | --- |
| +0 | `u64 pc_offset` | `final_pc - pc_base` |
| +8 | `u8 allocator_kind` | which allocator this site enters |
| +9 | `u8 rsi_root` | 1 if `%rsi` is a live root here |
| +10 | `u8 rdx_root` | 1 if `%rdx` is a live root here |
| +11 | `u8 reserved` | zero |
| +12 | `u32 reserved` | zero |

Offsets rather than absolute addresses: the same map then survives any link
layout, and a fixture can build it with two labels in its own section.

## 4. Classification law

At allocator entry, after capture:

```text
map not registered            -> NOT-A-SAFEPOINT   (allocate normally)
no entry for (pc, kind)       -> NOT-A-SAFEPOINT   (allocate normally)
entry kind != current kind    -> ABI, source 0x47430001, value = site offset
closure entry with rsi_root=1 -> ABI, source 0x47430002, value = 0
pc below declared pc_base     -> ABI, source 0x47430002, value = 0
otherwise                     -> CERTIFIED          (captures += 1)
```

`0x4743xxxx` is the GC source-code family, alongside the MMIO `0x4D494Fxx`
family, so a GC-metadata failure is distinguishable from a Lisp semantic
failure and from a device failure in the same condition line.

Allocation and OOM behaviour is unchanged on every path. **No collector runs.**

## 5. Executed evidence

Gate: `bash scripts/check-gc-safepoint-capture.sh` (CI:
`.github/workflows/gc-safepoint-capture.yml`).

| Witness | Observed serial |
| --- | --- |
| `certified` | `WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok` |
| `absent` | `WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok` |
| `kind-mismatch` | `WSM-OS CONDITION schema=1 kind=ABI source=1195573249 value=55` |
| `closure-rsi` | `WSM-OS CONDITION schema=1 kind=ABI source=1195573250 value=0` |

`value=55` is the site offset `0x40 - 0x9` in the mismatch fixture, cross-checked
against `objdump -d` of the object rather than taken from the transcript.

The `certified` fixture also asserts, inside the target, that the state is
`CERTIFIED` and that exactly two captures were recorded; a violation surfaces
as an `ABI` condition carrying the observed value, so the witness cannot pass by
silently classifying nothing.

## 6. What this does not claim

* No mark, no sweep, no free list, no collector activation.
* No collector selection (mark-sweep vs semispace stays open in #59).
* No stack root discovery and no conservative scan.
* No CML-produced map: the four maps are hand-written in the fixtures
  (`fixture-provenance = hand-written-assembly`). Consuming a real
  `CML_GC_ROOT_MAP_V1` record is #64.
* No semantic authority: nothing here decides what a program means.

## 7. Handoff

GREEN here is what #64 needs in order to say the runtime can consume root
metadata at the real call boundary. The remaining ladder:

```text
#71 capture          <- this document
#64 consume a real CML map (label -> final PC binding, duplicate keys, kinds)
#61 root protocol    (exact CML <-> WSM roots at safe points)
#60 collector        (mark-sweep + free list under the SENS reachability law)
GC-OOM              (constitution task: live capture survival + deliberate OOM)
```

---

## Українською: стислий виклад

Точний збирач сміття може початися лише з коренів, які компілятор засвідчив
для **конкретної точки виклику**. Алокатор — останнє місце, де це свідчення ще
існує: одна інструкція прологу, і повернення-адреса вже не відновлюється.

Тому `wsm_cons` і `wsm_closure_new` першою ж дією зберігають у rewriteable-зону
`wsm_gc_safepoint` рівно те, що можна знати напевно: `return_pc`,
`caller_rsp_at_call`, вхідні `%rsi`/`%rdx`, вид алокатора. `%rdi`/`%r12`
(покажчик на RuntimeContext) навмисно **не** стає коренем, а стек не
сканується взагалі — жодного консервативного запасного шляху.

Класифікація має три різні стани, і це головне рішення:

* `CERTIFIED` — запис у карті коренів збігається за (pc, вид алокатора);
* `NOT-A-SAFEPOINT` — метаданих немає, алокація йде як раніше;
* `INVALID` — метадані є, але суперечать цій точці → відмова з умовою `ABI`
  (`source=0x47430001` — не той вид алокатора, `0x47430002` — некоректна карта).

Окремо названо те, що здається дрібницею, але є справжньою пасткою: **відсутність
запису не можна трактувати як «коренів немає»**. Це перетворило б відсутній доказ
на тиху брехню, і збирач не побачив би живі значення — а зіпсується щось зовсім
в іншому місці й значно пізніше.

Що **не** доведено: жодного mark/sweep, жодного free-list, жодного вибору
збирача; карта коренів у фікстурах написана руками, а не видана CML; стек як
джерело коренів не обробляється. Наступний щабель — #64: спожити справжній
`CML_GC_ROOT_MAP_V1` із прив'язкою «мітка → фінальний PC».
