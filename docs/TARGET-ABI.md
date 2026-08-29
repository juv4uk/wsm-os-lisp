# wsm-os x86_64 target ABI v1

The source of truth is the dependency-free `no_std` crate
`crates/wsm-os-target`. [`target-contract.wsm`](../target-contract.wsm) is a
generated projection checked byte-for-byte by the crate tests. CML should
consume the crate rather than retype numeric tags.

## Value word

Values are 64-bit little-endian words with three low tag bits.

| Tag | Value | Meaning |
|---|---:|---|
| `cons` | `000` | non-zero, 16-byte-aligned pointer owned by runtime heap |
| `nil` | `001` | immediate `()` and the only false value |
| `true` | `010` | canonical true immediate |
| `fixnum` | `011` | signed 61-bit payload |
| `symbol` | `100` | non-zero, image-local interned symbol id |

The remaining tags are reserved. CML must reject a source form needing an
unratified value kind before emitting assembly.

An aligned pointer shape alone is not enough to dereference a cons. The
runtime must also prove that the address names a complete cell within the
active heap range.

## Cons cell

```text
offset 0: car, one 64-bit Value word
offset 8: cdr, one 64-bit Value word
cell size/alignment: 16 bytes
```

The first allocator is bounded and monotonic. Exhaustion calls the structured
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

Runtime operations receive the context as their first argument. Exact v1
signatures are:

```c
Value wsm_cons(RuntimeContext *, Value car, Value cdr);
Value wsm_car(RuntimeContext *, Value pair);
Value wsm_cdr(RuntimeContext *, Value pair);
Value wsm_eq(RuntimeContext *, Value left, Value right);
Value wsm_atom(RuntimeContext *, Value value);
void  wsm_fail(RuntimeContext *, uint32_t error_code) /* noreturn */;
```

The context layout is deliberately opaque to generated code. This lets hosted
and boot runtimes use the same emitted object without exposing allocator or
serial internals to CML.

## Error ABI

| Code | Meaning |
|---:|---|
| 1 | out of memory |
| 2 | type error |
| 3 | invalid/unresolved symbol id |
| 4 | ABI invariant violation |

These first codes are target-runtime errors. They do not claim complete
my-lisp 3.0 `ErrorKind` parity. Later mappings require explicit conformance
fixtures.

## Frozen first fixture

```lisp
(cons (quote A) (quote B))
```

Canonical my-lisp result:

```text
(A . B)
```

The contract pins both repository SHAs used to establish this boundary. A
future pin update changes evidence metadata only unless observable language or
target semantics also change.
