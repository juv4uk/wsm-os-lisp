#!/usr/bin/env python3
"""Project one WSM QEMU serial observation into the SENS L3 conformance envelope.

This script owns no SENS meaning. It copies program/identity/oracle facts from one
validated L0 row, normalizes the already-observed WSM result, computes the shared
canonical observable digest, and emits an L3 row. A caller may additionally pass
SENS's own validate.py; that validator remains the schema authority.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

SCHEMA = "sens-execution-conformance/v1"
RESULT_RE = re.compile(r"^WSM-OS RESULT schema=1 value=(.*) status=ok$")


def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def structured_digest(value: object) -> str:
    return sha256_text(canonical_json(value))


def read_one_json_row(path: Path) -> dict[str, object]:
    rows = [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if len(rows) != 1:
        raise ValueError(f"{path}: expected exactly one JSON row, got {len(rows)}")
    row = rows[0]
    if not isinstance(row, dict):
        raise ValueError(f"{path}: row must be an object")
    return row


def check_l0_oracle(row: dict[str, object]) -> None:
    if row.get("schema") != SCHEMA:
        raise ValueError(f"oracle row schema must be {SCHEMA}")
    if row.get("producer_layer") != "L0":
        raise ValueError("oracle row must be producer_layer=L0")
    if row.get("parity_status") != "ORACLE":
        raise ValueError("oracle row must have parity_status=ORACLE")
    if row.get("legacy_identity_used") is not False:
        raise ValueError("oracle row must forbid legacy identity")
    observable = row.get("observable")
    if not isinstance(observable, dict):
        raise ValueError("oracle row observable must be an object")
    expected = structured_digest(observable)
    if row.get("observable_digest") != expected:
        raise ValueError("oracle row observable_digest does not match canonical observable")
    if row.get("oracle_digest") != expected:
        raise ValueError("L0 oracle_digest must equal observable_digest")


def qemu_observable(transcript: str) -> dict[str, object]:
    values: list[str] = []
    for raw in transcript.splitlines():
        match = RESULT_RE.match(raw.strip())
        if match:
            values.append(match.group(1))
    if len(values) != 1:
        raise ValueError(
            f"expected exactly one successful WSM-OS RESULT line, got {len(values)}"
        )

    return {
        "result_kind": "VALUE",
        "value": values[0],
        "output": "",
        "error_kind": None,
        "order_trace": [],
        "mechanism_status": "CALLABLE",
    }


def project(
    oracle: dict[str, object],
    transcript: str,
    producer: str,
) -> dict[str, object]:
    check_l0_oracle(oracle)
    observed = qemu_observable(transcript)
    observed_digest = structured_digest(observed)
    oracle_digest = oracle["oracle_digest"]
    parity = "PASS" if observed_digest == oracle_digest else "FAIL"

    # Copy semantic/program authority fields from the oracle unchanged. WSM owns
    # only the observed L3 row and its producer identity.
    row = {
        "schema": oracle["schema"],
        "case_id": oracle["case_id"],
        "contract": oracle["contract"],
        "upstream_sha": oracle["upstream_sha"],
        "producer_layer": "L3",
        "producer": producer,
        "program_encoding": oracle["program_encoding"],
        "program": oracle["program"],
        "program_digest": oracle["program_digest"],
        "identity_trace": oracle["identity_trace"],
        "identity_trace_digest": oracle["identity_trace_digest"],
        "observable": observed,
        "observable_digest": observed_digest,
        "oracle_digest": oracle_digest,
        "parity_status": parity,
        "evidence_scope": oracle["evidence_scope"],
        "exhaustive_bound": oracle["exhaustive_bound"],
        "legacy_identity_used": False,
    }
    return row


def run_validator(validator: Path, row_path: Path, contract: str) -> None:
    result = subprocess.run(
        [sys.executable, str(validator), "--contract", contract, str(row_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"SENS conformance validator rejected L3 row\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def selftest() -> int:
    observable = {
        "result_kind": "VALUE",
        "value": "(A . B)",
        "output": "",
        "error_kind": None,
        "order_trace": [],
        "mechanism_status": "CALLABLE",
    }
    program = "(synthetic-current-case)"
    identity_trace = [{"domain": 3, "bits": "111"}]
    case_identity = {
        "contract": "11.8",
        "program_encoding": "canonical-source",
        "program": program,
    }
    oracle = {
        "schema": SCHEMA,
        "case_id": "case-" + sha256_text(canonical_json(case_identity)),
        "contract": "11.8",
        "upstream_sha": "0" * 40,
        "producer_layer": "L0",
        "producer": "sens-oracle:selftest",
        "program_encoding": "canonical-source",
        "program": program,
        "program_digest": sha256_text(program),
        "identity_trace": identity_trace,
        "identity_trace_digest": structured_digest(identity_trace),
        "observable": observable,
        "observable_digest": structured_digest(observable),
        "oracle_digest": structured_digest(observable),
        "parity_status": "ORACLE",
        "evidence_scope": "fixture",
        "exhaustive_bound": None,
        "legacy_identity_used": False,
    }

    good = project(
        oracle,
        "WSM-OS BOOT schema=1 arch=x86_64 status=ok\n"
        "WSM-OS RESULT schema=1 value=(A . B) status=ok\n",
        "wsm-os-lisp@selftest:qemu",
    )
    if good["parity_status"] != "PASS":
        raise AssertionError("equal QEMU observable did not PASS")

    bad = project(
        oracle,
        "WSM-OS BOOT schema=1 arch=x86_64 status=ok\n"
        "WSM-OS RESULT schema=1 value=(A . C) status=ok\n",
        "wsm-os-lisp@selftest:qemu",
    )
    if bad["parity_status"] != "FAIL":
        raise AssertionError("different QEMU observable did not FAIL")

    print("qemu-sens-conformance projection selftest: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--oracle-row", type=Path)
    parser.add_argument("--transcript", type=Path)
    parser.add_argument("--producer", type=str)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--validator", type=Path)
    parser.add_argument("--require-pass", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    required = {
        "--oracle-row": args.oracle_row,
        "--transcript": args.transcript,
        "--producer": args.producer,
        "--out": args.out,
    }
    missing = [name for name, value in required.items() if value is None]
    if missing:
        parser.error("missing required arguments: " + ", ".join(missing))

    oracle = read_one_json_row(args.oracle_row)
    transcript = args.transcript.read_text(encoding="utf-8")
    row = project(oracle, transcript, args.producer)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    if args.validator is not None:
        run_validator(args.validator, args.out, str(row["contract"]))

    print(
        "WSM-QEMU-SENS-L3 "
        f"case={row['case_id']} parity={row['parity_status']} "
        f"observable={row['observable_digest']} oracle={row['oracle_digest']}"
    )

    if args.require_pass and row["parity_status"] != "PASS":
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
