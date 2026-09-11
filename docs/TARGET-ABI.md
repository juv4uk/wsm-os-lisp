# wsm-os-lisp x86_64 target ABI — contract v2

The source of truth is the dependency-free `no_std`
[`wsm-os-target`](https://github.com/juv4uk/wsm-target-contract) crate in the
neutral `wsm-target-contract` repository. Its `target-contract.wsm` is a
generated projection checked byte-for-byte by crate tests. CML and this
runtime consume that package rather than carrying separate numeric copies.

The target ABI describes representation and mechanism. It is **not** a second
language specification: `my-lisp` owns WSM meaning, while `cml` admits and
lowers that meaning into this target representation.

## Value word

Values are 64-bit little-endian words with three low tag bits.

| Tag | Bits | Target meaning |
|---|---:|---|
| `cons` | `000` | non-zero, 16-byte-aligned pointer owned by runtime heap |
| `nil` | `001` | immediate `()` and the only false WSM value |
| `true` | `010` | **reserved legacy representation; not admitted as WSM `t`** |
| `fixnum` | `011` | signed 61-bit exact integer payload |
| `symbol` | `100` | non-zero, image-local interned symbol id; canonical `t` is `Symbol(SYMBOL_ID_MAX)` |
| `closure` | `101` | pointer to a runtime-owned bounded closure descriptor |
| `capability` | `110` | opaque, nonce-bearing substrate capability descriptor |
| reserved | `111` | unadmitted |

The important semantic boundary is deliberate: the bit pattern historically
named `Tag::True` remains reserved in target-contract v2 for representation
history, but it is **not a second truth value**. Canonical WSM `t` is the
ordinary symbol `t`, encoded as `CANONICAL_T = Symbol(SYMBOL_ID_MAX)`. Runtime,
hosted rendering, QEMU result validation and future backends must fail closed
if the legacy immediate is presented as semantic truth.

An aligned pointer shape alone is not enough to dereference a cons or closure.
The runtime must also prove that the address names a complete object within
the active arena range.

## Cons and closure cells

```text
cons:
  offset 0: car, one 64-bit Value word
  offset 8: cdr, one 64-bit Value word
  size/alignment: 16 bytes

closure descriptor:
  offset 0: definition_id (u32)
  offset 8: environment_ref (Value)
  size/alignment: 16 bytes
```

The first allocators are bounded and monotonic. Exhaustion calls the structured
failure path; it never wraps or returns address zero.

## Function ABI

Generated functions use the integer subset of System V AMD64. The public
entry is:

```c
Value wsm_entry(RuntimeContext *context);
```

- `rdi`: opaque runtime context on entry;
- `rax`: returned Value word;
- stack: 16-byte aligned before every call;
- red zone: forbidden;
- direction flag: clear;
- normal System V callee-saved registers remain preserved.

Runtime imports are versioned mechanism. Current contract v2 includes:

```c
Value    wsm_cons(RuntimeContext *, Value car, Value cdr);
Value    wsm_car(RuntimeContext *, Value pair);
Value    wsm_cdr(RuntimeContext *, Value pair);
Value    wsm_eq(RuntimeContext *, Value left, Value right);
Value    wsm_atom(RuntimeContext *, Value value);
Value    wsm_closure_new(RuntimeContext *, uint32_t definition_id, Value environment_ref);
uint32_t wsm_closure_definition(RuntimeContext *, Value closure);
Value    wsm_closure_environment(RuntimeContext *, Value closure);
Value    wsm_pci_config_capability(RuntimeContext *);
Value    wsm_pci_config_read16(RuntimeContext *, Value capability, Value bus, Value device,
                              Value function, Value offset);
Value    wsm_mmio_capability(RuntimeContext *);
Value    wsm_mmio_read32(RuntimeContext *, Value capability, Value offset);
Value    wsm_mmio_write32(RuntimeContext *, Value capability, Value offset, Value value);
void     wsm_fail(RuntimeContext *, uint32_t error_code, Value offending_value,
                  uint32_t source_id) /* noreturn */;
```

The context layout is deliberately opaque to generated code. Device
capabilities are mechanism, not language identities: a privileged import may
act only on a descriptor that decodes correctly **and** matches an active
nonce-bearing grant provisioned by the substrate. Legacy numeric capability
IDs are not an alternate authority path.

## Error ABI

| Code | Meaning |
|---:|---|
| 1 | out of memory |
| 2 | type error |
| 3 | invalid/unresolved symbol id |
| 4 | ABI invariant violation |
| 5 | exact numeric overflow |

These are admitted target observations, not permission for a backend to invent
new language errors. An unknown numeric error code must not become a new
semantic category; it is an ABI violation. Exact integers are never silently
narrowed or coerced through `f32`/`f64` in the semantic runtime path.

## Frozen first fixture

```lisp
(cons (quote A) (quote B))
```

Canonical my-lisp result:

```text
(A . B)
```

The evidence ladder remains explicit: hosted execution and QEMU execution must
agree with the pinned `my-lisp` observation. A later physical-hardware run is
a separate evidence graduation for the same pinned artifact.

---

# wsm-os-lisp x86_64 цільовий ABI — контракт v2

Джерелом істини є незалежний `no_std`-крейт
[`wsm-os-target`](https://github.com/juv4uk/wsm-target-contract) у нейтральному
репозиторії `wsm-target-contract`. Його `target-contract.wsm` є згенерованою
проекцією, яку тести перевіряють байт-у-байт. CML і цей runtime споживають
один пакет замість локальних копій числових констант.

Target ABI описує представлення і механізм. Це **не друга специфікація мови**:
`my-lisp` володіє значенням WSM, а `cml` лише допускає і знижує його в це
машинне представлення.

## Слово значення

Значення — 64-бітне little-endian слово з трьома молодшими бітами тегу.

| Тег | Біти | Значення на target-рівні |
|---|---:|---|
| `cons` | `000` | ненульовий 16-байтно вирівняний вказівник на runtime heap |
| `nil` | `001` | immediate `()` і єдине хибне значення WSM |
| `true` | `010` | **зарезервоване legacy-представлення; не є WSM `t`** |
| `fixnum` | `011` | точне знакове 61-бітне ціле |
| `symbol` | `100` | ненульовий image-local symbol id; канонічне `t` = `Symbol(SYMBOL_ID_MAX)` |
| `closure` | `101` | вказівник на bounded closure descriptor, яким володіє runtime |
| `capability` | `110` | opaque nonce-bearing capability, виданий substrate |
| зарезервовано | `111` | не допускається |

Ключова семантична межа навмисна: бітовий шаблон, історично названий
`Tag::True`, лишається reserved legacy representation у target-contract v2,
але **не є другою істиною**. Канонічне WSM `t` — звичайний символ `t`, тобто
`CANONICAL_T = Symbol(SYMBOL_ID_MAX)`. Runtime, hosted renderer, QEMU-validator
і майбутні backends мають fail-closed відхиляти legacy immediate як семантичне
`t`.

Одного вирівняного pointer shape недостатньо для dereference `cons` або
closure. Runtime також мусить довести, що адреса належить повному об'єкту в
активній arena.

## Cons і closure

```text
cons:
  offset 0: car, одне 64-бітне Value
  offset 8: cdr, одне 64-бітне Value
  size/alignment: 16 байт

closure descriptor:
  offset 0: definition_id (u32)
  offset 8: environment_ref (Value)
  size/alignment: 16 байт
```

Алокатори bounded і monotonic. Вичерпання переходить у structured failure;
ніякого wraparound чи нульової адреси.

## ABI функцій

Згенерований код використовує integer-підмножину System V AMD64:

```c
Value wsm_entry(RuntimeContext *context);
```

`rdi` містить opaque runtime context, результат повертається в `rax`, стек
вирівнюється до 16 байт перед call, red zone заборонений.

Поточний contract v2 містить механічні imports `cons/car/cdr/eq/atom`, bounded
closure operations, PCI/MMIO capability operations та структурований
`wsm_fail(context, error_code, offending_value, source_id)`. Ці imports не
створюють нових мовних примітивів.

Capability має силу лише тоді, коли коректно декодується у поточний descriptor
і збігається з активним nonce-bearing grant, виданим substrate. Старий numeric
capability ID не є альтернативним шляхом authority.

## ABI помилок

| Код | Значення |
|---:|---|
| 1 | нестача пам'яті |
| 2 | помилка типу |
| 3 | недійсний/нерозв'язаний symbol id |
| 4 | порушення ABI |
| 5 | переповнення точного числа |

Ці коди є допущеними target observations, а не дозволом backend-у винаходити
нові помилки мови. Невідомий numeric error code не може стати новою semantic
category — це ABI violation. Точні integer-значення не можуть тихо звужуватись
або проходити через `f32`/`f64` у semantic runtime path.

## Заморожена перша фікстура

```lisp
(cons (quote A) (quote B))
```

Канонічний результат `my-lisp`:

```text
(A . B)
```

Hosted і QEMU execution мають збігатися з pinned `my-lisp` observation.
Пізніший запуск на фізичному обладнанні є окремим підвищенням класу доказу для
того самого зафіксованого артефакту.