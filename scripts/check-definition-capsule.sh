#!/usr/bin/env bash
set -euo pipefail

first=$(mktemp -d)
second=$(mktemp -d)
tampered=$(mktemp -d)
trap 'rm -rf "$first" "$second" "$tampered"' EXIT

cargo run --quiet -p m4-generator -- --output-dir "$first"
cargo run --quiet -p m4-generator -- --output-dir "$second"

for artifact in fixture.wsm fixture.s fixture.o fixture-manifest.json fixture-definition-capsule.json; do
  cmp "$first/$artifact" "$second/$artifact"
  cmp "artifacts/$artifact" "$first/$artifact"
done

cargo run --quiet -p m4-generator -- --verify artifacts

cp -a "$first/." "$tampered/"
sed -i 's/"inspectable_metadata": true/"inspectable_metadata": false/' \
  "$tampered/fixture-definition-capsule.json"
if cargo run --quiet -p m4-generator -- --verify "$tampered" >/dev/null 2>&1; then
  echo "ERROR: mismatched definition capsule was accepted" >&2
  exit 1
fi

echo "Definition capsule and committed M4 bundle are deterministic and consistent."
