#!/usr/bin/env bash
# Keep current CML source pin separate from the generator provenance of
# committed historical boot fixtures. Never relabel an old object as new code.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CML_CURRENT_SHA=$(grep -oP '(?<=\(cml-revision ")[0-9a-f]{40}(?="\))' \
    "$ROOT_DIR/contracts/cml.lock")
FIXTURE_CML_SHA=$(grep -oP '(?<=\(fixture-cml-revision ")[0-9a-f]{40}(?="\))' \
    "$ROOT_DIR/contracts/fixture-cml.lock")
MANIFEST_SHA=$(grep -oP '(?<="cml_sha": ")[0-9a-f]{40}(?=")' \
    "$ROOT_DIR/artifacts/fixture-manifest.json" | head -1)

if [[ -z "$CML_CURRENT_SHA" || -z "$FIXTURE_CML_SHA" || -z "$MANIFEST_SHA" ]]; then
    echo "ERROR: missing current CML pin or historical fixture provenance" >&2
    exit 1
fi

echo "current CML source rev    : $CML_CURRENT_SHA"
echo "fixture generator rev     : $FIXTURE_CML_SHA"
echo "fixture manifest rev      : $MANIFEST_SHA"

if [[ "$FIXTURE_CML_SHA" != "$MANIFEST_SHA" ]]; then
    echo "FAIL: historical fixture provenance does not match its manifest" >&2
    exit 1
fi

if [[ "$CML_CURRENT_SHA" == "$FIXTURE_CML_SHA" ]]; then
    echo "FAIL: current source pin unexpectedly collapsed into historical fixture provenance" >&2
    exit 1
fi

grep -Fq '(x86-legacy-sid8-dispatch . retired)' "$ROOT_DIR/contracts/cml.lock"
grep -Fq '(fixture-status . historical-pre-contract-12)' "$ROOT_DIR/contracts/fixture-cml.lock"

echo "OK: current CML x86 SID8 retirement and historical fixture provenance are separately pinned."
