# TARGET-OBSERVER-AUDIT — issue #33, 2026-09-15

Status: completed (RED confirmed → GREEN implemented → regression verified)

## Audit mapping: observation paths → classification

### Old Rust M5A/M5B/tail/closure dispatch paths
- `wsm-os-kernel::kernel_main` fixture-name dispatch → **already-removed** (ADR-004, zero Rust)
- Hardcoded error variant test (`run-qemu-serial-emit-lisp`) → **already-removed**
- `.gitignore` cleanup of old `kernel_main` artifacts → completed in `36f6e6d`

### Current authority leaks (RED on main `4992f02`)

**Leak 1: Dead hardcoded expected value row**
- `entry.s:11-14` → `msg_result_ab`: static string `"WSM-OS RESULT schema=1 value=(A . B) status=ok\n"`
- Defined but never referenced in .text
- Classification: **stale target-local expected value**

**Leak 2: Fixture-specific symbol name literals**
- `entry.s:68-74` → `msg_sym_a` ("A"), `msg_sym_b` ("B")
- Emitted by `.Lp_symbol` for symbol IDs 12 and 20
- Symbol IDs come from CML interning of fixture `(cons (quote A) (quote B))`: A=1→encoded 12, B=2→encoded 20
- Classification: **target-authored expected Lisp semantics** (fixture identity embedded in target)

**Leak 3: Hardcoded symbol ID dispatch**
- `.Lp_symbol` contained `cmpq $12` → `je .Lp_sym_a`, `cmpq $20` → `je .Lp_sym_b`
- Fixture-specific IDs (12, 20) dispatched to fixture-specific names ('A', 'B')
- Unknown IDs fell through to generic `sym<id>` path — that was the only bounded behavior
- Classification: **target-authored fixture-derived symbol name mapping**

### What's correct (already bounded, kept)
- `nil` → `"nil"` (canonical, not fixture-specific)
- `t` → `"t"` (canonical, not fixture-specific)
- Cons → `(car . cdr)` structural (observable)
- Fixnum → decimal (observable)
- `check-shared-oracle-corpus.sh`: bounded observations only (t/nil/fixnum), expected from pinned compiler-corpus lock → **Lisp-owned observer** ✓
- `check-semantic-authority.sh`: WSM_CANONICAL_T, ERR_OOM/TYPE/ABI, no floats → **Lisp-owned contract** ✓

### External harness (allowed, carries expected representation)
- `artifacts/oracle-transcript.txt` → `(A . B)` — hosted oracle output, Lisp-owned authority for names
- `rebuild-and-run-qemu.sh` → compares serial transcript against file → external harness
- Per #33: harness may hold expected *representation*, but target must not independently own the semantic truth

## RED result (pre-fix)

Script: `scripts/check-target-observer-bounded.sh`

Three checks, all FAIL on main `4992f02`:
1. `msg_result_ab` present → FAIL (dead hardcoded expected literal)
2. `msg_sym_a`/`msg_sym_b` present → FAIL (target-authored fixture symbol names)
3. `cmp $0xc`/`cmp $0x14` in print_value disasm → FAIL (hardcoded fixture symbol ID dispatch)

**Verdict: RED (target carries fixture-derived expected truth)**

## GREEN implemented

1. Removed `msg_result_ab` dead literal
2. Removed `msg_sym_a`/`msg_sym_b` literals; added generic `msg_sym_prefix` ("sym")
3. `.Lp_symbol`: removed `cmp $12`/`cmp $20` dispatch; single generic path prints `sym` + decoded id
4. Updated `artifacts/qemu-serial-transcript.txt` baseline to observable format

### Observable format after GREEN

Target serializes only what it observes: decoded symbol id as `sym<id>`.
For fixture `(cons (quote A) (quote B))`: target prints `(sym1 . sym2)`.
Names (1↔A, 2↔B) live in CML interning (compiler-owned), not in target.

## Regression evidence (all GREEN)

| Gate | Result |
|---|---|
| `check-target-observer-bounded.sh` | PASS |
| `check-target-observer-behaviour.sh` (fixture A/B/C, C id=28) | PASS: `value=(sym1 . (sym2 . sym3))` |
| `check-semantic-authority.sh` | PASS |
| `check-no-rust.sh` | PASS |
| `check-runtime-symbols.sh` | PASS |
| `check-cml-provenance.sh` | PASS |
| `check-definition-capsule.sh` | PASS |
| `check-role-authority.sh` | PASS |
| `check-task-dag.sh` | PASS |
| `rebuild-and-run-qemu.sh` (standard fixture) | `value=(sym1 . sym2)`, EXIT 0 |

The behavioural witness compiles `(cons (quote A) (cons (quote B) (quote C)))`
through CML: ids A=1, B=2, C=3 (encoded 12/20/28). C is outside the former
hardcoded 12/20 window; the generic renderer serializes it correctly as `sym3`.

## Pre-existing issue found (out of #33 scope)

`scripts/check-shared-oracle-corpus.sh` requires `artifacts/m5c-tail-call-fixture.wsm`
but the observation-lane artifacts were migrated to `.lisp` (commit `b4efa3a`).
The script fails with `SHARED-ORACLE-FAIL: missing committed observation-lane
artifact` on main regardless of #33. Filed separately; not fixed in this scope.