#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
contract="$ROOT_DIR/contracts/wsm-target-contract/target-contract.lisp"

case "${1:-}" in
  boxed-tag)
    value="$(sed -n 's/.*(boxed \. \([0-9][0-9]*\)).*/\1/p' "$contract" | head -n1)"
    ;;
  version)
    value="$(sed -n 's/^(version \. \([0-9][0-9]*\)).*/\1/p' "$contract" | head -n1)"
    ;;
  *)
    echo "usage: $0 {boxed-tag|version}" >&2
    exit 2
    ;;
esac

if [[ -z "$value" || ! "$value" =~ ^[0-9]+$ ]]; then
  echo "TARGET-CONTRACT-PARSE-FAIL: could not resolve $1 from $contract" >&2
  exit 1
fi

printf '%s\n' "$value"
