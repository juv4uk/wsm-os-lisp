#!/usr/bin/env bash
# RED/GREEN witness: MMIO ABI symbols must be provided by the pure assembly
# target (ADR-004) so that CML-generated MMIO calls link and execute.
#
# RED state (before this slice): CML emits `call wsm_mmio_capability` but the
# target links with the entry+runtime objects only, which do not export it.
# The link therefore fails with an undefined reference — i.e. the MMIO ABI
# declared in docs/TARGET-ABI.md is not actually satisfiable.
#
# GREEN state (after this slice): `wsm_mmio_capability/read32/write32` exist
# in src/runtime.s and a CML-compiled MMIO fixture links cleanly.
#
# This gate is structural: it asserts the ABI boundary is satisfiable, without
# depending on a particular device address.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" == "--expect-red" ]]; then
  EXPECT_RED=1
else
  EXPECT_RED=0
fi

# Resolve CML binary (same priority as the #33 behaviour gate).
CML=""
if [[ -x "$ROOT_DIR/../cml/target/release/cml" ]]; then
  CML="$ROOT_DIR/../cml/target/release/cml"
elif command -v cml >/dev/null 2>&1; then
  CML="$(command -v cml)"
else
  echo "MMIO-ABI-BOUNDED: FAIL (no CML binary)"
  exit 1
fi

work=$(mktemp -d /tmp/wsm-mmio.XXXXXX)
trap 'rm -rf "$work"' EXIT

# Minimal MMIO consumer: a write to BAR+20 then a read of BAR+20. The exact
# value/address do not matter for the link witness; it must exercise the ABI.
printf '(mmio-read32 (mmio-capability) 20)\n' > "$work/fixture.lisp"

if ! "$CML" x86-asm "$work/fixture.lisp" > "$work/fixture.s" 2>"$work/cml.err"; then
  echo "MMIO-ABI-BOUNDED: FAIL (CML compile error)" >&2
  cat "$work/cml.err" >&2
  exit 1
fi

# The generated asm must actually request the MMIO substrate symbols.
if ! grep -q 'call wsm_mmio_capability' "$work/fixture.s"; then
  echo "MMIO-ABI-BOUNDED: FAIL (CML did not emit wsm_mmio_capability)" >&2
  exit 1
fi

as --64 "$work/fixture.s" -o "$work/fixture.o"
as --64 "$ROOT_DIR/src/entry.s" -o "$work/entry.o"
as --64 "$ROOT_DIR/src/runtime.s" -o "$work/runtime.o"

set +e
ld -m elf_x86_64 -T "$ROOT_DIR/src/linker.ld" \
  "$work/entry.o" "$work/runtime.o" "$work/fixture.o" \
  -o "$work/kernel.elf" >"$work/ld.out" 2>&1
ld_status=$?
set -e

if [[ "$EXPECT_RED" == 1 ]]; then
  if [[ "$ld_status" -ne 0 ]] && grep -q 'undefined reference to .wsm_mmio_' "$work/ld.out"; then
    echo "MMIO-ABI-BOUNDED: RED CONFIRMED (link fails on wsm_mmio_* symbols)"
    exit 0
  fi
  echo "MMIO-ABI-BOUNDED: FAIL (expected RED, but link succeeded)" >&2
  cat "$work/ld.out" >&2
  exit 1
fi

if [[ "$ld_status" -ne 0 ]]; then
  echo "MMIO-ABI-BOUNDED: FAIL (link error)" >&2
  cat "$work/ld.out" >&2
  exit 1
fi

echo "MMIO-ABI-BOUNDED: PASS (CML-generated MMIO call links against pure-asm target)"
exit 0