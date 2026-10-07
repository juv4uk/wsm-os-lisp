#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

fixture_obj="${WSM_M0_FIXTURE_OBJ:-artifacts/fixture.o}"
expected_transcript="${WSM_M0_EXPECTED_TRANSCRIPT:-artifacts/qemu-serial-transcript.txt}"
machine_profile="${WSM_M0_MACHINE_PROFILE:-contracts/qemu-m0-machine-profile.lisp}"
semantic_manifest="${WSM_M0_SEMANTIC_MANIFEST:-}"
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

if [[ "$require_semantic" == 1 && -z "$semantic_manifest" ]]; then
  fail "full M0/M1 mode requires WSM_M0_SEMANTIC_MANIFEST"
fi
if [[ -n "$semantic_manifest" && ! -s "$semantic_manifest" ]]; then
  fail "semantic manifest does not exist or is empty: $semantic_manifest"
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

if ! cmp -s "$transcript_a" "$expected_transcript"; then
  diff -u "$expected_transcript" "$transcript_a" >&2 || true
  fail "observed transcript differs from the declared expected transcript"
fi

fixture_sha="$(sha256_file "$fixture_obj")"
expected_sha="$(sha256_file "$expected_transcript")"
machine_sha="$(sha256_file "$machine_profile")"
transcript_sha="$(sha256_file "$transcript_a")"
raw_image_sha_a="$(sha256_file "$image_a")"
raw_image_sha_b="$(sha256_file "$image_b")"

semantic_sha=""
completion="MECHANISM-SMOKE"
if [[ -n "$semantic_manifest" ]]; then
  semantic_sha="$(sha256_file "$semantic_manifest")"
  completion="SEMANTIC-BOUND"
fi
if [[ "$require_semantic" == 1 ]]; then
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
  "$semantic_manifest" "$semantic_sha" \
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
    semantic_manifest_path,
    semantic_manifest_sha,
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
    "schema_version": 1,
    "completion": completion,
    "fixture_artifact": {
        "path": fixture_path,
        "sha256": fixture_sha,
    },
    "machine_profile": {
        "path": machine_profile_path,
        "sha256": machine_profile_sha,
    },
    "semantic_domain": None
    if not semantic_manifest_path
    else {
        "manifest": semantic_manifest_path,
        "sha256": semantic_manifest_sha,
    },
    "expected_transcript": {
        "path": expected_path,
        "sha256": expected_sha,
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
    printf 'M0-M1-BOOT-WITNESS-PASS: completion=%s canonical_image=%s witness=%s semantic_domain=UNBOUND\n' \
      "$completion" "$canonical_sha_a" "$witness_json"
    ;;
  *)
    printf 'M0-M1-BOOT-WITNESS-PASS: completion=%s canonical_image=%s witness=%s semantic_domain=%s\n' \
      "$completion" "$canonical_sha_a" "$witness_json" "$semantic_sha"
    ;;
esac
