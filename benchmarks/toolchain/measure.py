#!/usr/bin/env python3
"""Reproducible compile+run loop comparison for FPC and C compilers.

This is a small toolchain latency probe, not a language-performance benchmark.
All implementations compute the same checksum. Compiler flags are intentionally
unoptimized to model the fast-feedback edit/compile/test loop.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
C_SOURCE = ROOT / "benchmarks/toolchain/probe.c"
PAS_SOURCE = ROOT / "benchmarks/toolchain/probe.pas"
EXPECTED = "result=47999989"
RUNS = int(os.environ.get("WSM_TOOLCHAIN_RUNS", "15"))
OUT = Path(os.environ.get("WSM_TOOLCHAIN_OUT", "target/toolchain-iteration-benchmark"))
OUT.mkdir(parents=True, exist_ok=True)

def command_version(command: str) -> str:
    executable = shutil.which(command)
    if not executable:
        raise RuntimeError(f"required compiler not found: {command}")
    args = [executable, "-iV"] if command == "fpc" else ([executable, "-v"] if command == "tcc" else [executable, "--version"])
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False, timeout=10)
    line = next((line.strip() for line in result.stdout.splitlines() if line.strip()), "unknown")
    return line[:240]

def percentile90(values: list[float]) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(0.90 * len(ordered)) - 1)]

def run_checked(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=True, timeout=30)

def main() -> int:
    if RUNS < 5:
        raise RuntimeError("WSM_TOOLCHAIN_RUNS must be at least 5")

    specs = [
        ("fpc", ["fpc", "-O-", "-vw", "-FE{out}", "-FU{out}", "-o{bin}", str(PAS_SOURCE)]),
        ("tcc", ["tcc", "-std=c99", "-Wall", str(C_SOURCE), "-o", "{bin}"]),
        ("clang", ["clang", "-std=c99", "-O0", "-Wall", "-Wextra", "-Werror", str(C_SOURCE), "-o", "{bin}"]),
        ("gcc", ["gcc", "-std=c99", "-O0", "-Wall", "-Wextra", "-Werror", str(C_SOURCE), "-o", "{bin}"]),
    ]
    sources = {
        "c_sha256": hashlib.sha256(C_SOURCE.read_bytes()).hexdigest(),
        "pascal_sha256": hashlib.sha256(PAS_SOURCE.read_bytes()).hexdigest(),
    }
    versions = {name: command_version(name) for name, _ in specs}
    samples: list[dict[str, object]] = []

    for name, template in specs:
        for index in range(1, RUNS + 1):
            state = "cold" if index == 1 else "warm"
            with tempfile.TemporaryDirectory(prefix=f"wsm-{name}-") as temp:
                work = Path(temp)
                binary = work / "probe"
                args = [part.format(out=str(work), bin=str(binary)) for part in template]
                started = time.perf_counter_ns()
                built = run_checked(args, work)
                compiled = time.perf_counter_ns()
                executed = run_checked([str(binary)], work)
                finished = time.perf_counter_ns()
                output = executed.stdout.strip()
                if output != EXPECTED:
                    raise RuntimeError(
                        f"{name} run {index}: output {output!r}, expected {EXPECTED!r}; "
                        f"compiler stderr={built.stderr[-1000:]!r}"
                    )
                samples.append({
                    "compiler": name,
                    "run": index,
                    "cache_state": state,
                    "compile_ms": round((compiled - started) / 1_000_000, 3),
                    "build_test_ms": round((finished - started) / 1_000_000, 3),
                    "binary_bytes": binary.stat().st_size,
                    "output": output,
                })

    raw = OUT / "samples.tsv"
    with raw.open("w", encoding="utf-8") as stream:
        stream.write("compiler\trun\tcache_state\tcompile_ms\tbuild_test_ms\tbinary_bytes\toutput\n")
        for row in samples:
            stream.write(
                f"{row['compiler']}\t{row['run']}\t{row['cache_state']}\t"
                f"{row['compile_ms']}\t{row['build_test_ms']}\t"
                f"{row['binary_bytes']}\t{row['output']}\n"
            )

    summary = {
        "schema": 1,
        "host": {
            "system": platform.platform(),
            "machine": platform.machine(),
            "python": sys.version.split()[0],
            "cpu_count": os.cpu_count(),
        },
        "runs_per_compiler": RUNS,
        "compiler_versions": versions,
        "source_sha256": sources,
        "flags": {
            "fpc": "-O- -vw (native Linux target)",
            "tcc": "-std=c11 -Wall (TCC default fast compile)",
            "clang": "-std=c11 -O0 -Wall -Wextra -Werror",
            "gcc": "-std=c11 -O0 -Wall -Wextra -Werror",
        },
        "note": "Unoptimized fast-feedback probe; not a production performance comparison.",
        "results": {},
    }
    for name, _ in specs:
        warm = [row for row in samples if row["compiler"] == name and row["cache_state"] == "warm"]
        summary["results"][name] = {
            "compile_p50_ms": statistics.median(float(row["compile_ms"]) for row in warm),
            "compile_p90_ms": percentile90([float(row["compile_ms"]) for row in warm]),
            "build_test_p50_ms": statistics.median(float(row["build_test_ms"]) for row in warm),
            "build_test_p90_ms": percentile90([float(row["build_test_ms"]) for row in warm]),
            "binary_bytes": warm[-1]["binary_bytes"],
            "warm_samples": len(warm),
            "cold_first_run": next(row for row in samples if row["compiler"] == name and row["cache_state"] == "cold"),
        }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    print("compiler\tcompile_p50_ms\tcompile_p90_ms\tbuild_test_p50_ms\tbuild_test_p90_ms\tbinary_bytes")
    for name in (name for name, _ in specs):
        result = summary["results"][name]
        print(f"{name}\t{result['compile_p50_ms']:.3f}\t{result['compile_p90_ms']:.3f}\t"
              f"{result['build_test_p50_ms']:.3f}\t{result['build_test_p90_ms']:.3f}\t"
              f"{result['binary_bytes']}")
    print(f"raw samples: {raw}")
    print(f"summary: {OUT / 'summary.json'}")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.SubprocessError, RuntimeError, ValueError) as exc:
        print(f"TOOLCHAIN-BENCH-FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
