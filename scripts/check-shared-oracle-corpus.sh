#!/usr/bin/env bash
set -euo pipefail

lock_file="contracts/my-lisp/compiler-corpus.lock.my"
observation_lane="m5c-tail-call-fixture"

fail() {
  printf 'SHARED-ORACLE-FAIL: %s\n' "$1" >&2
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
print(" ".join(selected))
PY
)

repository=${lock_values[0]}
corpus_path=${lock_values[1]}
revision=${lock_values[2]}
read -r -a ordinals <<< "${lock_values[3]}"

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

assert_equal() {
  [[ "$1" == "$2" ]]
}

passed=0
for ordinal in "${ordinals[@]}"; do
  case_dir="$work_dir/case-$ordinal"
  generated_dir="$case_dir/generated"
  mkdir -p "$generated_dir"
  source_file="$case_dir/source.wsm"
  expected_file="$case_dir/expected.txt"
  record_file="$case_dir/record.txt"

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
if expr is None:
    raise SystemExit("selected compiler-corpus record has no expr")
if expected is None or error is not None:
    raise SystemExit("first bare-metal shared set requires value-producing records")

Path(source_out).write_text(expr + "\n", encoding="utf-8")
Path(expected_out).write_text(expected + "\n", encoding="utf-8")
Path(record_out).write_text(record + "\n", encoding="utf-8")
PY

  expected=$(tr -d '\r\n' < "$expected_file")
  [[ -n "$expected" ]] || fail "empty oracle observation for compiler-corpus[$ordinal]"

  # Current bounded target observation capability admits canonical `t` only.
  # This is an explicit substrate support boundary, not a copied semantic
  # expectation: each expected value above was extracted from upstream.
  if [[ "$expected" != "t" ]]; then
    fail "compiler-corpus[$ordinal] is outside the current canonical-t target observation slice"
  fi

  cp "$source_file" "artifacts/$observation_lane.wsm"
  WSM_FIXTURE="$observation_lane" cargo run --quiet -p m4-generator -- --output-dir "$generated_dir"
  cp "$generated_dir/$observation_lane.s" "artifacts/$observation_lane.s"
  cp "$generated_dir/$observation_lane.o" "artifacts/$observation_lane.o"

  hosted=$(WSM_FIXTURE="$observation_lane" cargo run --quiet -p wsm-os-hosted)
  assert_equal "$expected" "$hosted" \
    || fail "hosted observation '$hosted' differs from pinned oracle '$expected' for compiler-corpus[$ordinal]"

  # Exercise the same comparator with deliberate in-memory corruption for
  # every selected row. The gate must reject it while the overall run stays green.
  if assert_equal "${expected}__deliberate_mutation__" "$hosted"; then
    fail "deliberately mutated expectation was accepted for compiler-corpus[$ordinal]"
  fi
  printf 'SHARED-ORACLE-MUTATION-DETECTED: compiler-corpus[%s] wrong expected value rejected.\n' "$ordinal"

  WSM_FIXTURE="$observation_lane" cargo build --quiet -p wsm-os-kernel --target x86_64-unknown-none
  image="$case_dir/shared-oracle-uefi.img"
  cargo run --quiet -p wsm-os-image -- \
    target/x86_64-unknown-none/debug/wsm-os-kernel \
    "$image"
  [[ -s "$image" ]] || fail "shared-oracle UEFI image was not produced for compiler-corpus[$ordinal]"

  qemu_expected="$case_dir/qemu-expected.txt"
  printf 'WSM-OS BOOT schema=1 arch=x86_64 status=ok\nWSM-OS RESULT schema=1 value=%s status=ok\n' \
    "$expected" > "$qemu_expected"

  qemu_output=$(WSM_QEMU_TRANSCRIPT="$qemu_expected" scripts/run-qemu-uefi.sh "$image")
  qemu_value=$(printf '%s\n' "$qemu_output" \
    | sed -n 's/^WSM-OS RESULT schema=1 value=\(.*\) status=ok$/\1/p')
  assert_equal "$expected" "$qemu_value" \
    || fail "QEMU observation '$qemu_value' differs from pinned oracle '$expected' for compiler-corpus[$ordinal]"

  printf 'SHARED-ORACLE-PASS: my-lisp@%s compiler-corpus[%s] oracle=%s hosted=%s qemu=%s\n' \
    "$revision" "$ordinal" "$expected" "$hosted" "$qemu_value"
  passed=$((passed + 1))
done

printf 'SHARED-ORACLE-SET-PASS: revision=%s cases=%s\n' "$revision" "$passed"

# Every pinned compiler-corpus row must be accounted for, even when the target
# cannot execute it yet. This is deliberately a capability ledger, not a copy
# of semantic expected values: classifications are derived from the upstream
# record shape at CI time. Nothing may silently disappear between "confirmed"
# and "unsupported".
python3 - "$corpus_file" "${ordinals[*]}" <<'PY'
import ast
import re
import sys
from pathlib import Path

corpus, selected_text = sys.argv[1:]
selected = {int(item) for item in selected_text.split()}
records = [
    line.strip()
    for line in Path(corpus).read_text(encoding="utf-8").splitlines()
    if line.lstrip().startswith("((") and "(compiler-corpus . t)" in line
]
if not records:
    raise SystemExit("SHARED-ORACLE-COVERAGE-FAIL: pinned compiler corpus is empty")
if any(index >= len(records) for index in selected):
    raise SystemExit("SHARED-ORACLE-COVERAGE-FAIL: selected ordinal outside pinned corpus")

def string_field(record, name):
    match = re.search(rf'\({re.escape(name)}\s+\.\s+("(?:\\.|[^"\\])*")\)', record)
    return ast.literal_eval(match.group(1)) if match else None

confirmed = 0
unsupported = 0
for index, record in enumerate(records):
    expected = string_field(record, "expected")
    error = string_field(record, "error")
    if index in selected:
        if expected != "t" or error is not None:
            raise SystemExit(
                f"SHARED-ORACLE-COVERAGE-FAIL: selected compiler-corpus[{index}] "
                "does not fit current canonical-t observation capability"
            )
        status = "confirmed:end-to-end-canonical-t"
        confirmed += 1
    elif error is not None:
        status = "unsupported:error-observation"
        unsupported += 1
    elif expected == "()":
        status = "unsupported:nil-observation"
        unsupported += 1
    elif expected is not None and re.fullmatch(r"[+-]?\d+", expected):
        status = "unsupported:generic-fixnum-observation"
        unsupported += 1
    elif expected is not None and re.fullmatch(r"[+-]?\d+/\d+", expected):
        status = "unsupported:exact-rational-representation"
        unsupported += 1
    elif expected is not None and expected.startswith("("):
        status = "unsupported:compound-value-observation"
        unsupported += 1
    elif expected is not None:
        status = "unsupported:symbol-or-other-value-observation"
        unsupported += 1
    else:
        raise SystemExit(
            f"SHARED-ORACLE-COVERAGE-FAIL: compiler-corpus[{index}] has no classified observation"
        )
    print(f"SHARED-ORACLE-COVERAGE: compiler-corpus[{index}] status={status}")

if confirmed != len(selected) or confirmed + unsupported != len(records):
    raise SystemExit("SHARED-ORACLE-COVERAGE-FAIL: coverage accounting is incomplete")
print(
    f"SHARED-ORACLE-COVERAGE-PASS: total={len(records)} "
    f"confirmed={confirmed} explicit-unsupported={unsupported}"
)
PY
