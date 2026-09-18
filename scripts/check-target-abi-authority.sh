#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PIN_FILE="$ROOT/target-abi-pin.lisp"
RUNTIME="$ROOT/src/runtime.s"
PROFILE="$ROOT/target-profile.lisp"

PIN=$(sed -n 's/.*(commit \. "\([0-9a-f]\{40\}\)").*/\1/p' "$PIN_FILE")
SCHEMA=$(sed -n 's/.*(schema \. "\([^"]*\)").*/\1/p' "$PIN_FILE")
VERSION=$(sed -n 's/.*(version \. \([0-9][0-9]*\)).*/\1/p' "$PIN_FILE")
EXPECTED_SHA=$(sed -n 's/.*(projection-sha256 \. "\([0-9a-f]\{64\}\)").*/\1/p' "$PIN_FILE")

[ -n "$PIN" ] && [ -n "$SCHEMA" ] && [ -n "$VERSION" ] && [ -n "$EXPECTED_SHA" ] || {
  echo "target ABI pin is incomplete" >&2
  exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git -C "$TMP" init -q
git -C "$TMP" remote add origin https://github.com/juv4uk/wsm-target-contract.git
git -C "$TMP" fetch -q --depth 1 origin "$PIN"
git -C "$TMP" checkout -q FETCH_HEAD
ACTUAL=$(git -C "$TMP" rev-parse HEAD)
[ "$ACTUAL" = "$PIN" ] || {
  echo "target ABI pin mismatch: expected=$PIN actual=$ACTUAL" >&2
  exit 1
}

PROJECTION="$TMP/target-contract.lisp"
ACTUAL_SHA=$(sha256sum "$PROJECTION" | awk '{print $1}')
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || {
  echo "target ABI projection digest mismatch" >&2
  echo "expected=$EXPECTED_SHA" >&2
  echo "actual=$ACTUAL_SHA" >&2
  exit 1
}

grep -Fq "(schema . \"$SCHEMA\")" "$PROJECTION"
grep -Fq "(version . $VERSION)" "$PROJECTION"
grep -Fq "(boxed . 7)" "$PROJECTION"
grep -Fq "(kinds-defined-so-far . (string game-handle rational))" "$PROJECTION"
grep -Fq "wsm_rational_new" "$PROJECTION"
grep -Fq "wsm_rational_numerator" "$PROJECTION"
grep -Fq "wsm_rational_denominator" "$PROJECTION"
grep -Fq "(numeric-overflow . 5)" "$PROJECTION"

# Locally implemented subset must agree exactly with the pinned neutral authority.
grep -Fq ".set WSM_TAG_MASK,            7" "$RUNTIME"
grep -Fq ".set WSM_TAG_CONS,            0" "$RUNTIME"
grep -Fq ".set WSM_TAG_NIL,             1" "$RUNTIME"
grep -Fq ".set WSM_TAG_FIXNUM,          3" "$RUNTIME"
grep -Fq ".set WSM_TAG_SYMBOL,          4" "$RUNTIME"
grep -Fq ".set WSM_TAG_CLOSURE,         5" "$RUNTIME"
grep -Fq ".set WSM_TAG_CAPABILITY,      6" "$RUNTIME"
grep -Fq ".set ERR_OOM,                 1" "$RUNTIME"
grep -Fq ".set ERR_TYPE,                2" "$RUNTIME"
grep -Fq ".set ERR_SYMBOL,              3" "$RUNTIME"
grep -Fq ".set ERR_ABI,                 4" "$RUNTIME"
grep -Fq ".set ERR_OVERFLOW,            5" "$RUNTIME"

# Ratified v6 features may remain explicitly unsupported by this P0 runtime.
grep -Fq "(excludes . (lambda application closure strings bytes bignum rational reader evaluator gc))" "$PROFILE"

echo "TARGET-ABI-V6-GREEN pin=$PIN schema=$SCHEMA version=$VERSION sha256=$ACTUAL_SHA"
