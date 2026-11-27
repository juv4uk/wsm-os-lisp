#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT_DIR/artifacts/fixture-manifest.json"
CAPSULE="$ROOT_DIR/artifacts/fixture-definition-capsule.json"
SOURCE="$ROOT_DIR/artifacts/fixture.lisp"
ASSEMBLY="$ROOT_DIR/artifacts/fixture.s"
OBJECT="$ROOT_DIR/artifacts/fixture.o"
CURRENT_LOCK="$ROOT_DIR/contracts/cml.lock"
FIXTURE_LOCK="$ROOT_DIR/contracts/fixture-cml.lock"

# The committed M4 boot fixture predates Contract 12.0. The current CML pin
# intentionally rejects its historical flat SID call; therefore never compile
# this file with the current compiler and never relabel the old ELF as new.
# Verify the historical provenance and the exact committed bytes instead.
python3 - "$MANIFEST" "$CAPSULE" "$SOURCE" "$ASSEMBLY" "$OBJECT" "$CURRENT_LOCK" "$FIXTURE_LOCK" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

manifest_path, capsule_path, source_path, assembly_path, object_path, current_lock_path, fixture_lock_path = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text())
capsule = json.loads(capsule_path.read_text())
current_lock = current_lock_path.read_text()
fixture_lock = fixture_lock_path.read_text()

def field(text: str, pattern: str, label: str) -> str:
    match = re.search(pattern, text)
    if not match:
        raise SystemExit(f"FAIL: missing {label} in provenance lock")
    return match.group(1)

current_cml = field(current_lock, r'\(cml-revision "([0-9a-f]{40})"\)', "current CML pin")
fixture_cml = field(fixture_lock, r'\(fixture-cml-revision "([0-9a-f]{40})"\)', "historical fixture CML pin")
if fixture_cml != manifest.get("cml_sha"):
    raise SystemExit("FAIL: fixture generator revision disagrees with historical manifest")
if fixture_cml != capsule.get("contracts", {}).get("cml", {}).get("revision"):
    raise SystemExit("FAIL: fixture generator revision disagrees with definition capsule")
if fixture_cml == current_cml:
    raise SystemExit("FAIL: historical fixture provenance was accidentally collapsed into current CML pin")
if "(fixture-status . historical-pre-contract-12)" not in fixture_lock:
    raise SystemExit("FAIL: fixture provenance is not marked historical")
if "(x86-legacy-sid8-dispatch . retired)" not in current_lock:
    raise SystemExit("FAIL: current CML lock does not retire x86 SID8 dispatch")

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

checks = [
    (source_path, manifest.get("source_file_digest"), "source file"),
    (assembly_path, manifest.get("assembly_digest"), "assembly"),
    (object_path, manifest.get("object_digest"), "object"),
]
for path, expected, label in checks:
    if not path.is_file():
        raise SystemExit(f"FAIL: missing historical fixture {label}: {path}")
    actual = sha(path)
    if actual != expected:
        raise SystemExit(f"FAIL: historical fixture {label} SHA-256 mismatch: {actual} != {expected}")

capsule_artifacts = capsule.get("artifacts", {})
for label, path, digest_key in [
    ("assembly", assembly_path, "assembly_digest"),
    ("object", object_path, "object_digest"),
]:
    record = capsule_artifacts.get(label, {})
    if record.get("digest") != manifest.get(digest_key):
        raise SystemExit(f"FAIL: capsule {label} digest disagrees with fixture manifest")
    if record.get("path") != f"artifacts/{path.name}":
        raise SystemExit(f"FAIL: capsule {label} path disagrees with committed fixture")

source_record = capsule.get("source", {})
if source_record.get("path") != "artifacts/fixture.lisp":
    raise SystemExit("FAIL: capsule source path mismatch")
if source_record.get("file_digest") != manifest.get("source_file_digest"):
    raise SystemExit("FAIL: capsule source file digest mismatch")
if source_record.get("semantic_digest") != manifest.get("source_semantic_digest"):
    raise SystemExit("FAIL: capsule semantic digest mismatch")
if capsule.get("contracts", {}).get("target_abi", {}).get("digest") != manifest.get("target_contract_digest"):
    raise SystemExit("FAIL: capsule historical target ABI digest disagrees with manifest")

print(f"CURRENT-CML-PIN: {current_cml}")
print(f"HISTORICAL-FIXTURE-CML-PIN: {fixture_cml}")
print("Definition capsule: PASS (historical artifact provenance and committed bytes are exact).")
print("Current CML compilation is independently tested by the Contract 12 D1 v11 workflow.")
PY

# The old object remains a boot smoke fixture only. Verify that its exported
# entry and its sole runtime import match the historical capsule manifest.
defined="$(nm -g --defined-only "$OBJECT" | awk '{print $3}' | sort)"
undefined="$(nm -u "$OBJECT" | awk '{print $2}' | sort)"
[[ "$defined" == "wsm_entry" ]] || {
  echo "FAIL: historical fixture exports unexpected symbols: $defined" >&2
  exit 1
}
[[ "$undefined" == "wsm_cons" ]] || {
  echo "FAIL: historical fixture imports unexpected symbols: $undefined" >&2
  exit 1
}

echo "Historical M4 boot fixture is byte-verified; it is not current Contract 12 compiler evidence."
