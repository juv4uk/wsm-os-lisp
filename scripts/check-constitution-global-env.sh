#!/usr/bin/env bash
# Constitution global-environment gate.
#
# Proves the bounded target global definition table through three nucleus
# witnesses booted on the unchanged UEFI/QEMU target:
#
#   defs     ordinary + mutual recursion through name lookup, live redefinition
#            that does not consume capacity
#   unbound  lookup of a never-bound name is a named SYMBOL condition
#   full     binding past the arena capacity is a named OOM condition
#
# Scope: MECHANISM evidence only. These fixtures are hand-written target
# assembly (fixture-provenance = hand-written-assembly); CML emission, oracle
# parity and hosted parity are tracked by CONSTITUTION-GLOBAL-ENV-PARITY.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

out_dir="${WSM_GLOBAL_ENV_OUT_DIR:-target/constitution-global-env}"

fail() {
  printf 'CONSTITUTION-GLOBAL-ENV-FAIL: %s\n' "$1" >&2
  exit 1
}

rm -rf "$out_dir"
mkdir -p "$out_dir"

for name in defs unbound full; do
  fixture="artifacts/nucleus-witness-global-${name}-fixture"
  transcript="${fixture}-qemu-serial-transcript.txt"

  [[ -s "${fixture}.s" ]] || fail "missing ${fixture}.s"
  [[ -s "${fixture}.lisp" ]] || fail "missing ${fixture}.lisp source projection"
  [[ -s "$transcript" ]] || fail "missing $transcript"

  as --64 "${fixture}.s" -o "${out_dir}/${name}.o" \
    || fail "assemble ${name}"

  bash scripts/build-uefi-image.sh "${out_dir}/${name}.o" "${out_dir}/${name}.img" \
    >/dev/null || fail "image ${name}"

  WSM_QEMU_TRANSCRIPT="$transcript" \
  WSM_QEMU_RAW_SERIAL_COPY="${out_dir}/${name}-serial.log" \
    bash scripts/run-qemu-uefi.sh "${out_dir}/${name}.img" >/dev/null \
    || fail "qemu ${name}"

  printf 'PASS %-8s %s\n' "$name" "$(tr -d '\r' < "${out_dir}/${name}-serial.log" | grep '^WSM-OS ' | tr '\n' ' ')"
done

echo "CONSTITUTION-GLOBAL-ENV-PASS: 3/3 witnesses (defs, unbound, full)"
