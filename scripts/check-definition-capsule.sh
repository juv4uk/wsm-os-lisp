#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CML_BIN="${CML_BIN:-}"
if [[ -z "$CML_BIN" ]]; then
    if [[ -x "$ROOT_DIR/../cml/target/release/cml" ]]; then
        CML_BIN="$ROOT_DIR/../cml/target/release/cml"
    elif [[ -x "/home/agents/GitHub/cml/target/release/cml" ]]; then
        CML_BIN="/home/agents/GitHub/cml/target/release/cml"
    elif command -v cml >/dev/null 2>&1; then
        CML_BIN="$(command -v cml)"
    fi
fi

if [[ -z "$CML_BIN" || ! -x "$CML_BIN" ]]; then
    echo "ERROR: CML compiler binary not found at ${CML_BIN:-<unset>}" >&2
    echo "Set CML_BIN or build cml at ../cml" >&2
    exit 1
fi

tmp_dir=$(mktemp -d /tmp/wsm-capsule.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT

# 1. Compile fixture.lisp using CML
"$CML_BIN" x86-asm "$ROOT_DIR/artifacts/fixture.lisp" > "$tmp_dir/fixture.s"

# Compare generated assembly with committed fixture.s
if ! cmp -s "$tmp_dir/fixture.s" "$ROOT_DIR/artifacts/fixture.s"; then
    echo "ERROR: generated fixture.s differs from committed artifacts/fixture.s" >&2
    diff -u "$tmp_dir/fixture.s" "$ROOT_DIR/artifacts/fixture.s" >&2
    exit 1
fi

# 2. Assemble with GNU as
as --64 "$tmp_dir/fixture.s" -o "$tmp_dir/fixture.o"

# Compare symbol table with committed fixture.o
nm_gen=$(nm "$tmp_dir/fixture.o")
nm_com=$(nm "$ROOT_DIR/artifacts/fixture.o")
if [[ "$nm_gen" != "$nm_com" ]]; then
    echo "ERROR: assembled symbols differ from committed artifacts/fixture.o" >&2
    exit 1
fi

echo "Definition capsule and committed M4 bundle are deterministic and consistent."
