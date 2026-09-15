#!/usr/bin/env bash
set -euo pipefail

# TARGET-OBSERVER-GENERALIZE-1 (issue #33) behavioural witness.
#
# Compiles a fixture with THREE distinct symbols through CML and proves the
# bare-metal target serializes the third symbol (id outside the former
# 12/20 hardcode window) through the same generic sym<id> renderer.
#
#   fixture: (cons (quote A) (cons (quote B) (quote C)))
#   CML interning (BTreeMap order): A=1 -> 12, B=2 -> 20, C=3 -> 28
#   expected transcript: value=(sym1 . (sym2 . sym3))
#
# On pre-fix main the hardcoded dispatch (12->A, 20->B) could not name C;
# it fell through the generic path printing the raw decoded id. This witness
# locks the current bounded behaviour against future fixture-specific name
# embeds in ASM transport.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CML="${CML_BIN:-}"
if [[ -z "$CML" ]]; then
  if [[ -x "$ROOT_DIR/../cml/target/release/cml" ]]; then
    CML="$ROOT_DIR/../cml/target/release/cml"
  elif command -v cml >/dev/null 2>&1; then
    CML="$(command -v cml)"
  else
    echo "TARGET-OBSERVER-BEHAVIOUR: SKIP (no CML binary; set CML_BIN)" >&2
    exit 0
  fi
fi

work=$(mktemp -d /tmp/wsm-observer.XXXXXX)
trap 'rm -rf "$work"' EXIT

src="$work/fixture.lisp"
printf '(cons (quote A) (cons (quote B) (quote C)))\n' > "$src"

"$CML" x86-asm "$src" > "$work/fixture.s" 2>"$work/cml.err" || {
  echo "TARGET-OBSERVER-BEHAVIOUR: FAIL (CML compile error)" >&2
  cat "$work/cml.err" >&2
  exit 1
}

# The third symbol C must encode to an id beyond 12/20, proving the fixture
# exercises the generic path, not the former hardcode.  Enforce it at setup.
if ! grep -q 'movabsq $28, %rax' "$work/fixture.s"; then
  echo "TARGET-OBSERVER-BEHAVIOUR: FAIL (CML emit changed; expected C id 28 present)" >&2
  exit 1
fi

as --64 "$work/fixture.s" -o "$work/fixture.o"
bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/fixture.o" "$work/image.img" >/dev/null

printf 'WSM-OS BOOT schema=1 arch=x86_64 status=ok\nWSM-OS RESULT schema=1 value=(sym1 . (sym2 . sym3)) status=ok\n' \
  > "$work/expected.txt"

observed="$(WSM_QEMU_TRANSCRIPT="$work/expected.txt" bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/image.img" 2>"$work/qemu.err")" || {
  echo "TARGET-OBSERVER-BEHAVIOUR: FAIL (QEMU transcript mismatch)" >&2
  cat "$work/qemu.err" >&2
  exit 1
}

printf '%s\n' "$observed"
echo "TARGET-OBSERVER-BEHAVIOUR: PASS (foreign symbol id serialized as sym<id> through generic renderer)"