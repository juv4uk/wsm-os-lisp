# Consuming a root-map wire record at the allocation boundary

Status: **mechanism/boundary witness, executed in QEMU**. Issue #64
(`GC-ROOT-MAP-CONSUME-1`), parent root protocol #61, collector lane #60,
capture layer #71.

```text
LAYER = MECHANISM / BOUNDARY
SEMANTIC AUTHORITY = NONE
```

---

## 1. What changed since #71

#71 proved that the allocator can capture its entry state and classify it
against a map of **site offsets**. That is a runtime-internal representation.

A compiler cannot emit it directly: the compiler names a label, and only the
linker knows the final address. #64 therefore adds the boundary the compiler
actually writes — `CML_GC_ROOT_MAP_V1` — plus a binding table that resolves
`label -> final_pc`, and validates every record before it can influence
anything.

The runtime keeps one internal record layout. The wire differs from it in a
single word: the first field is a label id on the wire and a resolved site
offset internally. Registration copies and resolves; the allocator only ever
sees resolved records.

## 2. Wire format

Header, 32 bytes:

| Offset | Field | Value |
| --- | --- | --- |
| +0 | `u32 magic` | `0x4752434D` (`GCRM`) |
| +4 | `u16 version` | 1 |
| +6 | `u16 entry_count` | 1..256 |
| +8 | `u32 stride` | 32 |
| +12 | `u32 flags` | 0 |
| +16 | `u64 pc_base` | base for site offsets |
| +24 | `u64 reserved` | 0 |

Entry, 32 bytes each:

| Offset | Field | Meaning |
| --- | --- | --- |
| +0 | `u32 label_id` | resolved through the binding table |
| +4 | `u8 allocator_kind` | 1 cons, 2 closure |
| +5 | `u8 register_mask` | bit0 `%rsi`, bit1 `%rdx` |
| +6 | `u8 certified_empty` | 1 = this site provably has no roots |
| +7 | `u8 stack_root_count` | at most 2 in v1 |
| +8 | `u64 frame_size` | certified caller frame size |
| +16 | `u32 stack_offset[0]` | word-aligned, inside the frame |
| +20 | `u32 stack_offset[1]` | |
| +24 | `u64 reserved` | 0 |

Binding row, 16 bytes: `u32 label_id`, `u32 reserved`, `u64 final_pc`.

## 3. Validation happens before allocation, not during it

`wsm_gc_wire_register(ctx, wire, bindings, count)` fails closed on:

| Condition | Condition line |
| --- | --- |
| bad magic, version, stride, entry count, or null pc_base | `ABI source=0x47430006` |
| two binding rows with the same label | `ABI source=0x47430003 value=<label>` |
| wire label with no binding row | `ABI source=0x47430005 value=<label>` |
| two labels resolving to the same final PC | `ABI source=0x47430007 value=<offset>` |
| unaligned or out-of-frame stack root, unaligned frame size, more than 2 stack roots | `ABI source=0x47430004` |
| `certified_empty` together with declared roots, or zero roots without it | `ABI source=0x47430006` |
| kind outside {1,2}, register mask above 3 | `ABI source=0x47430006` |

Two reasons this is eager rather than lazy:

* a malformed map is a **compiler defect**, and it should surface once, at
  registration, not as a wrong answer during the thousandth allocation;
* the allocator path must stay short. Validation on every allocation would put
  a loop over records between the program and its memory.

The per-site classification from #71 is unchanged: `CERTIFIED`,
`NOT-A-SAFEPOINT`, `INVALID` (kind mismatch, closure claiming `%rsi`), and now
`CERTIFIED-EMPTY`.

## 4. Why "certified empty" is its own state

The #62 research witness is explicit: a zero-root certificate must say so, and
`certified_empty` may not coexist with declared roots. Otherwise "no roots" and
"no record" collapse into the same word, and the collector cannot tell a site
where the compiler proved nothing is live from a site the compiler never
described.

`NOT-A-SAFEPOINT` therefore means *no metadata*; `CERTIFIED-EMPTY` means
*metadata that proves emptiness*. Allocation behaves identically in both — that
is the point of separating them.

## 5. Relation to how mature toolchains do it

LLVM's stack map section carries exactly this shape: a header with version and
record count, records keyed by an instruction offset, and per-value locations
encoded as register / frame offset / indirect. Its documentation also states
the split used here — the runtime parses the section once and re-encodes it in
its own format, because the wire is a compiler artifact, not a runtime data
structure. (https://llvm.org/docs/StackMaps.html, https://llvm.org/docs/Statepoints.html)

What LLVM has and this slice does not: multiple functions per module, constant
locations, live-out register lists, and relocation pairs for derived pointers.
Those become relevant when the machine has a moving collector; the current
substrate has a bump arena and no relocation.

## 6. Executed evidence

Gate: `bash scripts/check-gc-root-map-wire.sh` (CI:
`.github/workflows/gc-root-map-wire.yml`).

| Witness | Observed serial |
| --- | --- |
| `certified` | `WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok` |
| `empty` | `WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok` |
| `unknown-label` | `WSM-OS CONDITION schema=1 kind=ABI source=1195573253 value=9` |
| `bad-stack` | `WSM-OS CONDITION schema=1 kind=ABI source=1195573252 value=0` |
| `dup-label` | `WSM-OS CONDITION schema=1 kind=ABI source=1195573251 value=1` |

The `certified` witness also asserts, inside the target, that the recorded
stack-root address equals `caller_rsp_at_call + certified_offset`, so the
address arithmetic is proven and not merely stored.

The #71 gate still passes unchanged against the widened record; its three
fixtures were re-emitted with the 32-byte entry and produce the same
transcripts.

## 7. What this does not claim

* No collector: no mark, no sweep, no free list, no stack scan.
* No CML emission: the five wire records are hand-written fixtures
  (`fixture-provenance = hand-written-assembly`). What is proven is that the
  runtime *can* consume such a record and rejects malformed ones; producing it
  is the compiler's task.
* No environment/closure edges: the map describes roots, not object graphs.
* No persistence: the resolved map lives in `.bss` for one boot session.

## 8. Next

`#61 GC-ROOT-PROTOCOL-1` can now specify the exact CML↔WSM root contract on top
of a consumer that already refuses bad metadata. `GC-OOM` follows #60.

---

## Українською: стислий виклад

Компілятор не може видати «зсув від бази» — він знає лише **мітку**, а
фінальну адресу знає лінкер. Тому з'явився шов `CML_GC_ROOT_MAP_V1`: заголовок
(magic, версія, кількість записів, stride, `pc_base`), записи по 32 байти з
`label_id`, видом алокатора, маскою регістрів, прапорцем `certified_empty`,
розміром кадру й до двох зсувів стекових коренів, і окрема таблиця
`label → final_pc`.

Ключове рішення: **валідація відбувається один раз, при реєстрації, а не на
кожній алокації**. Погана карта — це дефект компілятора, і він має проявитися
одразу, а не як неправильна відповідь на тисячній алокації. Алокатор же мусить
лишатися коротким.

Окремо названо `CERTIFIED-EMPTY`: сертифікат «тут коренів точно немає» — це не
те саме, що «запису немає». Якби ці два стани злилися в один, збирач не
відрізнив би точку, де компілятор довів порожнечу, від точки, яку компілятор
не описав взагалі.

Що **не** доведено: жодного mark/sweep; записи карт написані руками, а не
видані CML (доведено саме те, що runtime **може** спожити такий запис і
відкидає некоректні); граф об'єктів (середовища замикань) не описується;
карта не зберігається між завантаженнями.
