#!/usr/bin/env bash
set -euo pipefail

lock_file="contracts/my-lisp/compiler-corpus.lock.my"
observation_lane="m5c-tail-call-fixture"
provenance_root="target/shared-oracle-provenance"

fail() {
  printf 'SHARED-PROVENANCE-FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$lock_file" ]] || fail "missing $lock_file"

readarray -t lock_values < <(python3 - "$lock_file" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
revision = re.search(r'\(revision\s+"([0-9a-f]{40})"\)', text)
ordinals = re.search(r'\(compiler-corpus-ordinals\s+\(([0-9\s]+)\)\)', text)
path = re.search(r'\(path\s+([^\s\)]+)\)', text)
repository = re.search(r'\(repository\s+([^\s\)]+)\)', text)
if not all((revision, ordinals, path, repository)):
    raise SystemExit("invalid compiler-corpus lock")
selected = [item for item in ordinals.group(1).split() if item]
if not selected:
    raise SystemExit("compiler-corpus selector is empty")
print(repository.group(1))
print(path.group(1))
print(revision.group(1))
print(selected[0])
PY
)

repository=${lock_values[0]}
corpus_path=${lock_values[1]}
revision=${lock_values[2]}
ordinal=${lock_values[3]}

work_dir=$(mktemp -d)
backup_dir="$work_dir/original"
mkdir -p "$backup_dir"

restore() {
  for ext in wsm s o; do
    if [[ -f "$backup_dir/$observation_lane.$ext" ]]; then
      cp "$backup_dir/$observation_lane.$ext" "artifacts/$observation_lane.$ext"
    fi
  done
  rm -rf "$work_dir"
}
trap restore EXIT

for ext in wsm s o; do
  [[ -f "artifacts/$observation_lane.$ext" ]] \
    || fail "missing committed observation-lane artifact artifacts/$observation_lane.$ext"
  cp "artifacts/$observation_lane.$ext" "$backup_dir/$observation_lane.$ext"
done

corpus_file="$work_dir/conformance.my"
if [[ -n "${MY_LISP_CORPUS_FILE:-}" ]]; then
  cp "$MY_LISP_CORPUS_FILE" "$corpus_file"
else
  raw_url="https://raw.githubusercontent.com/$repository/$revision/$corpus_path"
  curl --fail --silent --show-error --location "$raw_url" -o "$corpus_file" \
    || fail "cannot fetch pinned oracle corpus $repository@$revision:$corpus_path"
fi

source_file="$work_dir/source.wsm"
expected_file="$work_dir/expected.txt"
record_file="$work_dir/record.txt"

python3 - "$corpus_file" "$ordinal" "$source_file" "$expected_file" "$record_file" <<'PY'
import ast
import re
import sys
from pathlib import Path

corpus, ordinal, source_out, expected_out, record_out = sys.argv[1:]
ordinal = int(ordinal)
records = [
    line.strip()
    for line in Path(corpus).read_text(encoding="utf-8").splitlines()
    if line.lstrip().startswith("((") and "(compiler-corpus . t)" in line
]
if ordinal >= len(records):
    raise SystemExit(f"compiler-corpus ordinal {ordinal} out of range ({len(records)} records)")
record = records[ordinal]

def string_field(name):
    match = re.search(rf'\({re.escape(name)}\s+\.\s+("(?:\\.|[^"\\])*")\)', record)
    return ast.literal_eval(match.group(1)) if match else None

expr = string_field("expr")
expected = string_field("expected")
error = string_field("error")
if expr is None or expected is None or error is not None:
    raise SystemExit("selected provenance fixture must be a value-producing compiler-corpus row")
Path(source_out).write_text(expr + "\n", encoding="utf-8")
Path(expected_out).write_text(expected + "\n", encoding="utf-8")
Path(record_out).write_text(record + "\n", encoding="utf-8")
PY

expected=$(tr -d '\r\n' < "$expected_file")
[[ "$expected" == "t" ]] \
  || fail "first provenance slice requires the already-admitted canonical-t observation"

cp "$source_file" "artifacts/$observation_lane.wsm"

gen_a="$work_dir/generated-a"
gen_b="$work_dir/generated-b"
mkdir -p "$gen_a" "$gen_b"
WSM_FIXTURE="$observation_lane" cargo run --quiet -p m4-generator -- --output-dir "$gen_a"
WSM_FIXTURE="$observation_lane" cargo run --quiet -p m4-generator -- --output-dir "$gen_b"

for suffix in s o manifest.json definition-capsule.json; do
  left="$gen_a/$observation_lane-$suffix"
  right="$gen_b/$observation_lane-$suffix"
  if [[ "$suffix" == "s" || "$suffix" == "o" ]]; then
    left="$gen_a/$observation_lane.$suffix"
    right="$gen_b/$observation_lane.$suffix"
  fi
  [[ -f "$left" && -f "$right" ]] || fail "generator omitted $suffix provenance artifact"
  cmp -s "$left" "$right" || fail "same pinned source did not rebuild deterministic $suffix"
done
printf 'SHARED-PROVENANCE-DETERMINISM-PASS: source->asm/object/metadata byte-identical.\n'

cp "$gen_a/$observation_lane.s" "artifacts/$observation_lane.s"
cp "$gen_a/$observation_lane.o" "artifacts/$observation_lane.o"

hosted=$(WSM_FIXTURE="$observation_lane" cargo run --quiet -p wsm-os-hosted)
[[ "$hosted" == "$expected" ]] \
  || fail "hosted observation '$hosted' differs from pinned oracle '$expected'"

WSM_FIXTURE="$observation_lane" cargo build --quiet -p wsm-os-kernel --target x86_64-unknown-none
kernel="target/x86_64-unknown-none/debug/wsm-os-kernel"
[[ -s "$kernel" ]] || fail "kernel artifact missing"

image_a="$work_dir/shared-oracle-provenance-a.img"
image_b="$work_dir/shared-oracle-provenance-b.img"
cargo run --quiet -p wsm-os-image -- "$kernel" "$image_a"
cargo run --quiet -p wsm-os-image -- "$kernel" "$image_b"
[[ -s "$image_a" && -s "$image_b" ]] || fail "UEFI image rebuild omitted an output"
cmp -s "$image_a" "$image_b" \
  || fail "same pinned kernel did not rebuild a byte-identical UEFI image"
printf 'SHARED-PROVENANCE-IMAGE-DETERMINISM-PASS: repeated UEFI image build is byte-identical.\n'
image="$image_a"

qemu_expected="$work_dir/qemu-expected.txt"
printf 'WSM-OS BOOT schema=1 arch=x86_64 status=ok\nWSM-OS RESULT schema=1 value=%s status=ok\n' \
  "$expected" > "$qemu_expected"
qemu_output=$(WSM_QEMU_TRANSCRIPT="$qemu_expected" scripts/run-qemu-uefi.sh "$image")
qemu_observed="$work_dir/qemu-observed.txt"
printf '%s\n' "$qemu_output" > "$qemu_observed"
qemu_value=$(printf '%s\n' "$qemu_output" \
  | sed -n 's/^WSM-OS RESULT schema=1 value=\(.*\) status=ok$/\1/p')
[[ "$qemu_value" == "$expected" ]] \
  || fail "QEMU observation '$qemu_value' differs from pinned oracle '$expected'"

bundle="$provenance_root/case-$ordinal"
rm -rf "$bundle"
mkdir -p "$bundle"
cp "$source_file" "$bundle/source.wsm"
cp "$record_file" "$bundle/upstream-record.txt"
cp "$gen_a/$observation_lane.s" "$bundle/generated.s"
cp "$gen_a/$observation_lane.o" "$bundle/generated.o"
cp "$gen_a/$observation_lane-manifest.json" "$bundle/generator-manifest.json"
cp "$gen_a/$observation_lane-definition-capsule.json" "$bundle/definition-capsule.json"
cp "$kernel" "$bundle/kernel.elf"
cp "$image" "$bundle/uefi.img"
cp "$qemu_observed" "$bundle/qemu-transcript.txt"
printf '%s\n' "$hosted" > "$bundle/hosted-observation.txt"

python3 - \
  "$bundle" "$repository" "$corpus_path" "$revision" "$ordinal" "$expected" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
repository, corpus_path, revision, ordinal, expected = sys.argv[2:]
manifest = json.loads((bundle / "generator-manifest.json").read_text(encoding="utf-8"))
capsule = json.loads((bundle / "definition-capsule.json").read_text(encoding="utf-8"))

def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

source_sha = sha(bundle / "source.wsm")
asm_sha = sha(bundle / "generated.s")
object_sha = sha(bundle / "generated.o")
manifest_sha = sha(bundle / "generator-manifest.json")
capsule_sha = sha(bundle / "definition-capsule.json")
kernel_sha = sha(bundle / "kernel.elf")
image_sha = sha(bundle / "uefi.img")
qemu_sha = sha(bundle / "qemu-transcript.txt")
hosted_sha = sha(bundle / "hosted-observation.txt")
record_sha = sha(bundle / "upstream-record.txt")

if source_sha != manifest["source_file_digest"]:
    raise SystemExit("generator manifest source digest does not match exact upstream source")
if asm_sha != manifest["assembly_digest"]:
    raise SystemExit("generator manifest assembly digest mismatch")
if object_sha != manifest["object_digest"]:
    raise SystemExit("generator manifest object digest mismatch")

abi_digest = manifest["target_contract_digest"]
capsule_abi = capsule["contracts"]["target_abi"]["digest"]
if abi_digest != capsule_abi:
    raise SystemExit("target ABI digest diverges between generator manifest and definition capsule")

record = {
    "schema": "wsm-os-lisp-shared-oracle-provenance",
    "schema_version": 1,
    "oracle": {
        "repository": repository,
        "path": corpus_path,
        "revision": revision,
        "compiler_corpus_ordinal": int(ordinal),
        "upstream_record_sha256": record_sha,
        "source_file_sha256": source_sha,
        "expected_observation": expected,
    },
    "cml_lowering": {
        "cml_revision": manifest["cml_sha"],
        "admission_path": "cml::parser::parse -> cml::lower::lower_program_with_tail_calls -> X86FreestandingBackend::compile_program",
        "admission_evidence": "generator completed at pinned CML revision; generated manifest binds source/asm/object",
        "generator_manifest_sha256": manifest_sha,
        "definition_capsule_sha256": capsule_sha,
        "assembly_sha256": asm_sha,
        "object_sha256": object_sha,
        "deterministic_rebuild": "byte-identical",
    },
    "target": {
        "target_contract_sha256": abi_digest,
        "target_abi_schema": capsule["contracts"]["target_abi"]["schema"],
        "target_abi_version": capsule["contracts"]["target_abi"]["version"],
        "kernel_sha256": kernel_sha,
        "uefi_image_sha256": image_sha,
        "uefi_image_rebuild": "byte-identical",
    },
    "observation": {
        "hosted_sha256": hosted_sha,
        "qemu_transcript_sha256": qemu_sha,
        "value": expected,
    },
    "files": {
        "source": "source.wsm",
        "upstream_record": "upstream-record.txt",
        "assembly": "generated.s",
        "object": "generated.o",
        "generator_manifest": "generator-manifest.json",
        "definition_capsule": "definition-capsule.json",
        "kernel": "kernel.elf",
        "uefi_image": "uefi.img",
        "hosted_observation": "hosted-observation.txt",
        "qemu_transcript": "qemu-transcript.txt",
    },
}
(bundle / "provenance.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

python3 - "$bundle" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
record_path = bundle / "provenance.json"

def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def load():
    return json.loads(record_path.read_text(encoding="utf-8"))

def verify(record):
    files = record["files"]
    manifest = json.loads((bundle / files["generator_manifest"]).read_text(encoding="utf-8"))
    capsule = json.loads((bundle / files["definition_capsule"]).read_text(encoding="utf-8"))
    checks = [
        (sha(bundle / files["source"]), record["oracle"]["source_file_sha256"], "source"),
        (sha(bundle / files["assembly"]), record["cml_lowering"]["assembly_sha256"], "assembly"),
        (sha(bundle / files["object"]), record["cml_lowering"]["object_sha256"], "object"),
        (sha(bundle / files["kernel"]), record["target"]["kernel_sha256"], "kernel"),
        (sha(bundle / files["uefi_image"]), record["target"]["uefi_image_sha256"], "image"),
        (sha(bundle / files["qemu_transcript"]), record["observation"]["qemu_transcript_sha256"], "transcript"),
    ]
    for actual, expected, label in checks:
        if actual != expected:
            raise ValueError(f"{label} digest mismatch")
    if manifest["source_file_digest"] != record["oracle"]["source_file_sha256"]:
        raise ValueError("manifest/source provenance mismatch")
    if manifest["object_digest"] != record["cml_lowering"]["object_sha256"]:
        raise ValueError("manifest/object provenance mismatch")
    if manifest["target_contract_digest"] != record["target"]["target_contract_sha256"]:
        raise ValueError("manifest/ABI provenance mismatch")
    if capsule["contracts"]["target_abi"]["digest"] != record["target"]["target_contract_sha256"]:
        raise ValueError("capsule/ABI provenance mismatch")

record = load()
verify(record)
print("SHARED-PROVENANCE-BASELINE-PASS: machine-readable chain verifies.")

# Object tamper must be detected.
object_path = bundle / record["files"]["object"]
original = object_path.read_bytes()
object_path.write_bytes(original + b"tamper")
try:
    verify(record)
except ValueError:
    print("SHARED-PROVENANCE-TAMPER-DETECTED: object substitution rejected.")
else:
    raise SystemExit("object substitution was accepted")
finally:
    object_path.write_bytes(original)

# ABI digest substitution must be detected against both independent metadata projections.
mutated = json.loads(json.dumps(record))
mutated["target"]["target_contract_sha256"] = "0" * 64
try:
    verify(mutated)
except ValueError:
    print("SHARED-PROVENANCE-TAMPER-DETECTED: ABI digest substitution rejected.")
else:
    raise SystemExit("ABI digest substitution was accepted")

# Image tamper must be detected.
image_path = bundle / record["files"]["uefi_image"]
original = image_path.read_bytes()
image_path.write_bytes(original + b"tamper")
try:
    verify(record)
except ValueError:
    print("SHARED-PROVENANCE-TAMPER-DETECTED: image substitution rejected.")
else:
    raise SystemExit("image substitution was accepted")
finally:
    image_path.write_bytes(original)

verify(record)
print("SHARED-PROVENANCE-PASS: source->CML->asm/object->ABI->kernel/image->QEMU transcript bound and tamper-checked.")
PY

printf 'SHARED-PROVENANCE-RECORD: %s/provenance.json\n' "$bundle"
