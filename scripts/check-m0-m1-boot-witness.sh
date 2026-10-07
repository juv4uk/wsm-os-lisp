#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

fixture_obj="${WSM_M0_FIXTURE_OBJ:-artifacts/fixture.o}"
expected_transcript="${WSM_M0_EXPECTED_TRANSCRIPT:-artifacts/qemu-serial-transcript.txt}"
machine_profile="${WSM_M0_MACHINE_PROFILE:-contracts/qemu-m0-machine-profile.lisp}"
handoff_manifest="${WSM_M0_HANDOFF_MANIFEST:-${WSM_M0_SEMANTIC_MANIFEST:-}}"
oracle_row="${WSM_M0_ORACLE_ROW:-}"
sens_validator="${SENS_CONFORMANCE_VALIDATOR:-}"
producer="${WSM_M0_PRODUCER:-wsm-os-lisp@unversioned:qemu-m0-m1}"
require_semantic="${WSM_M0_REQUIRE_SEMANTIC:-0}"
out_dir="${WSM_M0_OUT_DIR:-target/m0-m1-boot-witness}"

fail() {
  printf 'M0-M1-BOOT-WITNESS-FAIL: %s\n' "$1" >&2
  exit 1
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

monotonic_ns() {
  python3 - <<'PY'
import time
print(time.monotonic_ns())
PY
}

for required in "$fixture_obj" "$expected_transcript" "$machine_profile"; do
  [[ -s "$required" ]] || fail "missing required input $required"
done

case "$require_semantic" in
  0|1) ;;
  *) fail "WSM_M0_REQUIRE_SEMANTIC must be 0 or 1" ;;
esac

for optional in "$handoff_manifest" "$oracle_row" "$sens_validator"; do
  if [[ -n "$optional" && ! -s "$optional" ]]; then
    fail "declared evidence input does not exist or is empty: $optional"
  fi
done

if [[ "$require_semantic" == 1 ]]; then
  [[ -n "$handoff_manifest" ]] || fail "full M0/M1 mode requires WSM_M0_HANDOFF_MANIFEST"
  [[ -n "$oracle_row" ]] || fail "full M0/M1 mode requires WSM_M0_ORACLE_ROW"
  [[ -n "$sens_validator" ]] || fail "full M0/M1 mode requires SENS_CONFORMANCE_VALIDATOR"
fi

rm -rf "$out_dir"
mkdir -p "$out_dir"

image_a="$out_dir/boot-a.img"
image_b="$out_dir/boot-b.img"
canonical_a="$out_dir/boot-a.canonical.img"
canonical_b="$out_dir/boot-b.canonical.img"
report_a="$out_dir/boot-a.canonicalization.json"
report_b="$out_dir/boot-b.canonicalization.json"
transcript_a="$out_dir/boot-a.serial.txt"
transcript_b="$out_dir/boot-b.serial.txt"
l3_a="$out_dir/boot-a.sens-l3.jsonl"
l3_b="$out_dir/boot-b.sens-l3.jsonl"

scripts/build-uefi-image.sh "$fixture_obj" "$image_a" >/dev/null
scripts/build-uefi-image.sh "$fixture_obj" "$image_b" >/dev/null

python3 scripts/canonicalize-gpt-image.py "$image_a" "$canonical_a" --report "$report_a" >/dev/null
python3 scripts/canonicalize-gpt-image.py "$image_b" "$canonical_b" --report "$report_b" >/dev/null

canonical_sha_a="$(sha256_file "$canonical_a")"
canonical_sha_b="$(sha256_file "$canonical_b")"
if [[ "$canonical_sha_a" != "$canonical_sha_b" ]]; then
  fail "repeated image build is not canonical-byte-identical after GPT normalization ($canonical_sha_a != $canonical_sha_b)"
fi

start_a="$(monotonic_ns)"
WSM_QEMU_TRANSCRIPT="$expected_transcript" scripts/run-qemu-uefi.sh "$image_a" >"$transcript_a"
end_a="$(monotonic_ns)"

start_b="$(monotonic_ns)"
WSM_QEMU_TRANSCRIPT="$expected_transcript" scripts/run-qemu-uefi.sh "$image_b" >"$transcript_b"
end_b="$(monotonic_ns)"

if ! cmp -s "$transcript_a" "$transcript_b"; then
  diff -u "$transcript_a" "$transcript_b" >&2 || true
  fail "reboot transcript differs across identical pinned inputs"
fi

# This comparison is a mechanism/reproducibility guard only. In full M0/M1
# mode the semantic verdict comes from the SENS L0 oracle digest below.
if ! cmp -s "$transcript_a" "$expected_transcript"; then
  diff -u "$expected_transcript" "$transcript_a" >&2 || true
  fail "observed transcript differs from the declared mechanism transcript"
fi

fixture_sha="$(sha256_file "$fixture_obj")"
expected_sha="$(sha256_file "$expected_transcript")"
machine_sha="$(sha256_file "$machine_profile")"
transcript_sha="$(sha256_file "$transcript_a")"
raw_image_sha_a="$(sha256_file "$image_a")"
raw_image_sha_b="$(sha256_file "$image_b")"

handoff_sha=""
oracle_sha=""
l3_sha=""
completion="MECHANISM-SMOKE"

if [[ -n "$handoff_manifest" ]]; then
  handoff_sha="$(sha256_file "$handoff_manifest")"
  completion="HANDOFF-BOUND"
fi

if [[ -n "$oracle_row" ]]; then
  oracle_sha="$(sha256_file "$oracle_row")"
  completion="ORACLE-BOUND"
fi

if [[ "$require_semantic" == 1 ]]; then
  python3 scripts/project-qemu-observation-to-sens-conformance.py \
    --oracle-row "$oracle_row" \
    --transcript "$transcript_a" \
    --producer "$producer" \
    --out "$l3_a" \
    --validator "$sens_validator" \
    --require-pass
  python3 scripts/project-qemu-observation-to-sens-conformance.py \
    --oracle-row "$oracle_row" \
    --transcript "$transcript_b" \
    --producer "$producer" \
    --out "$l3_b" \
    --validator "$sens_validator" \
    --require-pass
  cmp -s "$l3_a" "$l3_b" || fail "reboot L3 conformance row is not deterministic"
  l3_sha="$(sha256_file "$l3_a")"
  completion="M0-M1"
fi

duration_a_ms=$(( (end_a - start_a) / 1000000 ))
duration_b_ms=$(( (end_b - start_b) / 1000000 ))

witness_json="$out_dir/witness.json"
python3 - \
  "$witness_json" \
  "$fixture_obj" "$fixture_sha" \
  "$expected_transcript" "$expected_sha" \
  "$machine_profile" "$machine_sha" \
  "$handoff_manifest" "$handoff_sha" \
  "$oracle_row" "$oracle_sha" \
  "$l3_a" "$l3_sha" \
  "$canonical_sha_a" "$raw_image_sha_a" "$raw_image_sha_b" \
  "$transcript_sha" "$duration_a_ms" "$duration_b_ms" "$completion" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

(
    output_path,
    fixture_path,
    fixture_sha,
    expected_path,
    expected_sha,
    machine_profile_path,
    machine_profile_sha,
    handoff_manifest_path,
    handoff_manifest_sha,
    oracle_row_path,
    oracle_row_sha,
    l3_path,
    l3_sha,
    canonical_image_sha,
    raw_image_sha_a,
    raw_image_sha_b,
    transcript_sha,
    duration_a_ms,
    duration_b_ms,
    completion,
) = sys.argv[1:]

stable = {
    "schema": "wsm-os-m0-m1-boot-witness",
    "schema_version": 2,
    "completion": completion,
    "fixture_artifact": {
        "path": fixture_path,
        "sha256": fixture_sha,
    },
    "machine_profile": {
        "path": machine_profile_path,
        "sha256": machine_profile_sha,
    },
    "compiler_handoff": None
    if not handoff_manifest_path
    else {
        "manifest": handoff_manifest_path,
        "sha256": handoff_manifest_sha,
    },
    "semantic_oracle": None
    if not oracle_row_path
    else {
        "row": oracle_row_path,
        "sha256": oracle_row_sha,
    },
    "l3_conformance": None
    if not l3_sha
    else {
        "row": l3_path,
        "sha256": l3_sha,
    },
    "mechanism_expected_transcript": {
        "path": expected_path,
        "sha256": expected_sha,
        "semantic_authority": False,
    },
    "canonical_image_sha256": canonical_image_sha,
    "observed_transcript_sha256": transcript_sha,
    "reboot_equivalence": "exact-transcript",
}
stable_bytes = json.dumps(stable, sort_keys=True, separators=(",", ":")).encode("utf-8")
stable["witness_digest_sha256"] = hashlib.sha256(stable_bytes).hexdigest()
stable["diagnostics"] = {
    "raw_image_sha256": [raw_image_sha_a, raw_image_sha_b],
    "boot_duration_ms": [int(duration_a_ms), int(duration_b_ms)],
    "timing_affects_verdict": False,
    "raw_image_digest_affects_verdict": False,
}
Path(output_path).write_text(
    json.dumps(stable, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

case "$completion" in
  MECHANISM-SMOKE)
    printf 'M0-M1-BOOT-WITNESS-PASS: completion=%s canonical_image=%s witness=%s oracle=UNBOUND\n' \
      "$completion" "$canonical_sha_a" "$witness_json"
    ;;
  M0-M1)
    printf 'M0-M1-BOOT-WITNESS-PASS: completion=%s canonical_image=%s witness=%s l3=%s\n' \
      "$completion" "$canonical_sha_a" "$witness_json" "$l3_sha"
    ;;
  *)
    printf 'M0-M1-BOOT-WITNESS-PASS: completion=%s canonical_image=%s witness=%s\n' \
      "$completion" "$canonical_sha_a" "$witness_json"
    ;;
esac
