# Bounded global definitions on the WSM OS Lisp target

Status: **mechanism witness, executed in QEMU**. Constitution line
(`WSM-OS-CONSTITUTION-GLOBAL-ENV-DEFS`), mechanism slice
(`WSM-OS-CONSTITUTION-GLOBAL-ENV-MECHANISM`).

This document records what the target now does, what it deliberately does not
do, and how the claim is reproduced. It is not a language contract: names,
binding laws and error identity remain SENS/`my-lisp` authority. This
repository owns only the target mechanism.

---

## 1. Why a definition table at all

The escaping-closure witness (`nucleus-witness-escaping-closure-fixture`)
proved that a closure can outlive its defining call. It could not prove the
next constitutional fact: a program is a set of named definitions that refer to
each other, including **before** either body has run.

Mutual recursion is the sharp case. If `f` is compiled to an absolute call
into `g`, then whichever definition is compiled first refers to something that
does not exist yet. Resolving the callee **by name at call time** removes the
ordering problem without adding a linker to the target.

So the mechanism has exactly two operations — bind a name, resolve a name —
plus one observation used by the witness (how many names are bound).

## 2. Representation

`RuntimeContext` (see `src/entry.s::runtime_context`) gains three fields:

| Offset | Field | Meaning |
| --- | --- | --- |
| +72 | `def_base` | pointer to a fixed-capacity arena owned by the target |
| +80 | `def_capacity` | number of 16-byte entries the arena holds (256) |
| +88 | `def_len` | number of entries currently bound |

Each entry is 16 bytes:

| Offset | Field | Meaning |
| --- | --- | --- |
| +0 | `u32 name_id` | symbol id carried by the name word (`word >> 3`) |
| +4 | `u32 reserved` | always zero; keeps the value word 8-byte aligned |
| +8 | `u64 value` | tagged WSM word bound to that name |

The arena lives in `.bss` (`def_arena`, 4096 bytes) and is initialised to zero
by the loader, so `def_len = 0` needs no boot-time loop.

Why 16 bytes and not 8 or 24: the value word must stay 8-byte aligned inside a
16-byte stride so a slot can be read with a single `movq` at a compile-time
offset from a shifted index (`index << 4`). A packed 12-byte entry would force
unaligned loads and make every lookup a multi-instruction sequence on a target
that has no unaligned-store forgiveness guarantee.

## 3. Primitives (target ABI v8 calling convention)

```text
Word   wsm_def_bind(RuntimeContext* ctx, Word name, Word value)   RDI RSI RDX -> RAX
Word   wsm_def_ref (RuntimeContext* ctx, Word name)               RDI RSI     -> RAX
uint64 wsm_def_count(RuntimeContext* ctx)                         RDI         -> RAX
```

`wsm_def_bind` returns the bound word unchanged, so a definition form can
evaluate to its own value. `wsm_def_ref` returns only the stored value word:
the name word itself is never returned, which keeps name identity separate from
value identity.

## 4. Laws and the fail-closed matrix

| Situation | Result |
| --- | --- |
| name tag is not `100` (symbol) | `TYPE` condition, offending value = the rejected name |
| name id is `0` | `TYPE` condition (id 0 is not an admissible name) |
| name already bound | value replaced in the existing slot; capacity unchanged |
| name not bound | `SYMBOL` condition, offending value = the name word |
| `def_len == def_capacity`, new name | `OOM` condition, offending value `0` |
| `def_len == def_capacity`, existing name | rebind succeeds (no new slot needed) |

Two of these choices are deliberate and worth stating plainly:

* **Unbound is `SYMBOL`, never `NIL`.** `NIL` is a value; using it for "no
  binding" would make `(f)` and `(f)` where `f` is bound to `NIL`
  indistinguishable at the target.
* **Table exhaustion is `OOM`, not `OVERFLOW`.** `OVERFLOW` is the arithmetic
  condition. A full arena is the same kind of event as a full cons or closure
  arena, and `wsm_cons` / `wsm_closure_new` already report that as `OOM` with
  offending value `0`. Consistency here matters more than the name.

Rebinding in place is what makes redefinition cheap and observationally clean:
redefining a live function changes what later lookups return, but does not
consume capacity and does not move any other binding.

## 5. Executed evidence

Gate: `bash scripts/check-constitution-global-env.sh` (CI:
`.github/workflows/constitution-global-env.yml`). Three witnesses boot the
unchanged UEFI/QEMU target.

| Witness | Program | Observed serial |
| --- | --- | --- |
| `defs` | `f`/`g` mutually recursive through name lookup, then `f` redefined | `WSM-OS RESULT schema=1 value=(sym5 . (sym6 . nil)) status=ok` |
| `unbound` | resolve a name that was never bound | `WSM-OS CONDITION schema=1 kind=SYMBOL source=0 value=44` |
| `full` | 256 names bound, then a 257th | `WSM-OS CONDITION schema=1 kind=OOM source=0 value=0` |

The `defs` witness also asserts, inside the fixture, that redefinition left the
bound-name count at 2; a violation is reported as an `ABI` condition carrying
the observed count, so the fixture cannot pass while silently consuming slots.

Reproduce:

```bash
sudo apt-get install -y --no-install-recommends \
  qemu-system-x86 ovmf mtools dosfstools gdisk binutils
bash scripts/check-constitution-global-env.sh
```

## 6. What this does not claim

* **Not CML-emitted.** These three fixtures are hand-written target assembly
  (`fixture-provenance = hand-written-assembly`). The sibling `.lisp` files are
  the intended source projections, not admitted compiler input.
* **No oracle or hosted parity.** Nothing here compares the target against the
  `my-lisp` oracle or hosted generated code. That is
  `WSM-OS-CONSTITUTION-GLOBAL-ENV-PARITY`.
* **No GC interaction.** The table is not a root set yet; the collector task
  (`WSM-OS-CONSTITUTION-GC-OOM`) must enumerate it before any heap compaction.
* **No image persistence.** Bindings live in `.bss` and are not saved or
  restored.
* **No name syntax.** Names are symbol ids; interning, packages and textual
  names belong to the reader task, not to the target table.

## 7. Follow-ups

1. `WSM-OS-CONSTITUTION-GLOBAL-ENV-PARITY` — CML emission of the same three
   shapes, oracle rows, hosted parity, capsule and manifest.
2. `WSM-OS-CONSTITUTION-GC-OOM` — root enumeration must include `def_arena`.
3. Reader/meta-eval — textual names become symbol ids at read time, so the
   table never learns about text.

---

## Українською: стислий виклад

Цільова машина тепер має **обмежену таблицю глобальних визначень**: 256
записів по 16 байтів у `.bss`, з полями `name_id` та `value` окремо, тому ім'я
ніколи не повертається як значення. Дві примітиви — `wsm_def_bind` і
`wsm_def_ref` — плюс `wsm_def_count` для спостереження.

Ключове рішення: виклик розв'язує ім'я **в момент виклику**, а не при
компіляції. Саме це дає взаємну рекурсію без лінкера: `f` може згадувати `g`,
якого ще не існує, бо `g` шукається за іменем під час виконання.

Три закони, перевірені в QEMU:

* незв'язане ім'я — це умова `SYMBOL` з цим іменем як значенням, **не `NIL`**
  (`NIL` — це значення, і плутати їх не можна);
* переповнення таблиці — це `OOM`, як і вичерпання арени cons/closure, а не
  арифметичний `OVERFLOW`;
* перевизначення займає той самий слот, тому не витрачає ємність і не зсуває
  інші зв'язування.

Що **не** доведено: ці фікстури — рукописний ассемблер, а не емісія CML; немає
паритету з оракулом і hosted-кодом; таблиця ще не є коренем для GC; зв'язування
не зберігаються в образі системи; текстових імен (інтернування) тут немає.
