#!/usr/bin/env bash
set -euo pipefail

bundle=${1:-target/shared-oracle-provenance/case-1}
record="$bundle/provenance.json"
kernel="$bundle/kernel.elf"
image_a="$bundle/uefi.img"
canonicalizer="scripts/canonicalize-gpt-image.py"

fail() {
  printf 'UEFI-REPRODUCIBILITY-FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$record" ]] || fail "missing provenance record $record"
[[ -s "$kernel" ]] || fail "missing provenance kernel $kernel"
[[ -s "$image_a" ]] || fail "missing provenance image $image_a"
[[ -f "$canonicalizer" ]] || fail "missing GPT canonicalizer"

# This variance model is deliberately pinned to the exact dependency mechanism
# we audited. A dependency change must be re-audited instead of silently
# inheriting this allowance.
readarray -t image_stack < <(python3 - <<'PY'
import tomllib
from pathlib import Path

lock = tomllib.loads(Path("Cargo.lock").read_text(encoding="utf-8"))
versions = {p["name"]: p["version"] for p in lock["package"] if p["name"] in {"bootloader", "gpt"}}
print(versions.get("bootloader", ""))
print(versions.get("gpt", ""))
PY
)
bootloader_version=${image_stack[0]}
gpt_version=${image_stack[1]}
[[ "$bootloader_version" == "0.11.17" ]] \
  || fail "GPT variance model requires audited bootloader 0.11.17, found '$bootloader_version'"
[[ "$gpt_version" == "3.1.0" ]] \
  || fail "GPT variance model requires audited gpt 3.1.0, found '$gpt_version'"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

image_b="$work_dir/rebuilt.img"
canonical_a="$bundle/uefi.canonical.img"
canonical_b="$work_dir/rebuilt.canonical.img"
report_a="$bundle/uefi-canonicalization.json"
report_b="$work_dir/rebuilt-canonicalization.json"

cargo run --quiet -p wsm-os-image -- "$kernel" "$image_b"
[[ -s "$image_b" ]] || fail "rebuild did not produce a UEFI image"

python3 "$canonicalizer" "$image_a" "$canonical_a" --report "$report_a"
python3 "$canonicalizer" "$image_b" "$canonical_b" --report "$report_b"

if cmp -s "$image_a" "$image_b"; then
  raw_status="byte-identical"
else
  raw_status="different-before-gpt-canonicalization"
fi

cmp -s "$canonical_a" "$canonical_b" \
  || fail "same kernel differs outside audited GPT identity/CRC variance"
printf 'UEFI-REPRODUCIBILITY-CANONICAL-PASS: repeated image build matches after GPT identity canonicalization.\n'

# Prove the allowance cannot hide a payload change. Flip one byte well inside
# the first EFI partition, canonicalize again, and require the witness to break.
tampered="$work_dir/payload-tampered.img"
tampered_canonical="$work_dir/payload-tampered.canonical.img"
cp "$image_b" "$tampered"
python3 - "$tampered" "$report_b" <<'PY'
import json
import sys
from pathlib import Path

image_path = Path(sys.argv[1])
report = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
data = bytearray(image_path.read_bytes())
partition_start = int(report["first_partition_lba"]) * int(report["sector_size"])
offset = partition_start + 4096
if offset >= len(data):
    raise SystemExit("payload tamper offset is outside image")
data[offset] ^= 0x01
image_path.write_bytes(data)
PY
python3 "$canonicalizer" "$tampered" "$tampered_canonical"
if cmp -s "$canonical_a" "$tampered_canonical"; then
  fail "GPT canonicalization hid a deliberate EFI-partition payload mutation"
fi
printf 'UEFI-REPRODUCIBILITY-PAYLOAD-TAMPER-DETECTED: non-GPT payload mutation remains visible.\n'

# Bind the reproducibility result into the same machine-readable provenance
# record produced by check-shared-oracle-provenance.sh.
python3 - \
  "$record" "$report_a" "$report_b" "$raw_status" \
  "$bootloader_version" "$gpt_version" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

record_path, report_a_path, report_b_path, raw_status, bootloader_version, gpt_version = sys.argv[1:]
record_path = Path(record_path)
record = json.loads(record_path.read_text(encoding="utf-8"))
a = json.loads(Path(report_a_path).read_text(encoding="utf-8"))
b = json.loads(Path(report_b_path).read_text(encoding="utf-8"))

expected_allowed = [
    "gpt.disk_guid",
    "gpt.partition_unique_guid",
    "gpt.partition_array_crc32",
    "gpt.header_crc32",
]
if a["allowed_variance"] != expected_allowed or b["allowed_variance"] != expected_allowed:
    raise SystemExit("canonicalizer allowed-variance vocabulary changed")
if a["canonical_sha256"] != b["canonical_sha256"]:
    raise SystemExit("canonical image digests differ")
if a["raw_sha256"] != record["target"]["uefi_image_sha256"]:
    raise SystemExit("canonicalization report is not bound to provenance image")

canonical_path = record_path.parent / "uefi.canonical.img"
h = hashlib.sha256(canonical_path.read_bytes()).hexdigest()
if h != a["canonical_sha256"]:
    raise SystemExit("persisted canonical image digest mismatch")

record["target"]["uefi_image_rebuild"] = {
    "status": "canonical-byte-identical",
    "raw_status": raw_status,
    "canonical_sha256": a["canonical_sha256"],
    "rebuilt_raw_sha256": b["raw_sha256"],
    "normalization_schema": a["schema"],
    "normalization_schema_version": a["schema_version"],
    "allowed_variance": expected_allowed,
    "mechanism": {
        "bootloader_version": bootloader_version,
        "gpt_version": gpt_version,
        "reason": "fresh GPT disk and partition UUIDv4 identities with derived GPT CRC32 fields",
    },
    "payload_tamper_witness": "rejected-after-same-canonicalization",
}
record["files"]["uefi_canonical_image"] = "uefi.canonical.img"
record["files"]["uefi_canonicalization"] = "uefi-canonicalization.json"
record_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

printf 'UEFI-REPRODUCIBILITY-PASS: raw=%s allowed=gpt-identity+derived-crc record=%s\n' \
  "$raw_status" "$record"
