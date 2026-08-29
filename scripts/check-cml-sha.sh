#!/usr/bin/env bash
# Verify the CML SHA provenance chain:
#
#   wsm-os-target::CML_SHA
#     == Cargo rev in m4-generator/Cargo.toml
#     == cml-sha in target-contract.wsm
#     == cml_sha in artifacts/manifest.json
#
# Any mismatch is a provenance break: the artifact manifest would record a
# different CML than the binary that was actually compiled.
set -euo pipefail

fail=0

# Extract the contract constant (single source of truth).
CONTRACT_SHA=$(grep 'pub const CML_SHA' crates/wsm-os-target/src/lib.rs \
    | grep -oP '(?<=")[0-9a-f]{40}(?=")')

if [[ -z "$CONTRACT_SHA" ]]; then
    echo "ERROR: could not extract CML_SHA from wsm-os-target/src/lib.rs" >&2
    exit 1
fi

echo "Contract CML_SHA : $CONTRACT_SHA"

# m4-generator Cargo.toml
M4_SHA=$(grep -oP '(?<=rev = ")[0-9a-f]{40}(?=")' \
    crates/m4-generator/Cargo.toml | head -1)
echo "m4-generator rev : $M4_SHA"
if [[ "$M4_SHA" != "$CONTRACT_SHA" ]]; then
    echo "MISMATCH: m4-generator Cargo rev != CML_SHA" >&2
    fail=1
fi

# target-contract.wsm
CONTRACT_WSM_SHA=$(grep -oP '(?<=cml-sha \. ")[0-9a-f]{40}(?=")' \
    target-contract.wsm | head -1)
echo "target-contract  : $CONTRACT_WSM_SHA"
if [[ "$CONTRACT_WSM_SHA" != "$CONTRACT_SHA" ]]; then
    echo "MISMATCH: target-contract.wsm cml-sha != CML_SHA" >&2
    fail=1
fi

# committed artifact manifest
MANIFEST_SHA=$(grep -oP '(?<="cml_sha": ")[0-9a-f]{40}(?=")' \
    artifacts/manifest.json | head -1)
echo "artifact manifest: $MANIFEST_SHA"
if [[ "$MANIFEST_SHA" != "$CONTRACT_SHA" ]]; then
    echo "MISMATCH: artifacts/manifest.json cml_sha != CML_SHA" >&2
    fail=1
fi

if [[ $fail -eq 0 ]]; then
    echo "OK: CML SHA provenance chain is consistent ($CONTRACT_SHA)"
else
    echo "FAIL: CML SHA provenance chain is broken — update all four locations together." >&2
    echo "  wsm-os-target/src/lib.rs  pub const CML_SHA" >&2
    echo "  crates/m4-generator/Cargo.toml  rev = ..." >&2
    echo "  target-contract.wsm  cml-sha . ..." >&2
    echo "  artifacts/manifest.json  cml_sha" >&2
    exit 1
fi
