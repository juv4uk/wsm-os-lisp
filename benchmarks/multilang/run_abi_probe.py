#!/usr/bin/env python3
"""Build a tiny C static library and call it from Free Pascal through C ABI."""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
C_SOURCE = ROOT / "benchmarks/multilang/c_probe.c"
PAS_SOURCE = ROOT / "benchmarks/multilang/pascal_caller.pas"
EXPECTED = "abi=cdecl i32 scalar result=439"

def require(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise RuntimeError(f"required tool not found: {name}")
    return path

def run(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=30)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(args)}\n{result.stdout}")
    return result

def main() -> int:
    gcc = require("gcc")
    ar = require("ar")
    fpc = require("fpc")
    with tempfile.TemporaryDirectory(prefix="wsm-pascal-c-abi-") as temp:
        work = Path(temp)
        obj = work / "c_probe.o"
        library = work / "libprobe.a"
        binary = work / "abi_probe"
        run([gcc, "-std=c11", "-O0", "-Wall", "-Wextra", "-Werror",
             "-c", str(C_SOURCE), "-o", str(obj)], work)
        run([ar, "rcs", str(library), str(obj)], work)
        build = run([fpc, "-B", "-O-", f"-FE{work}", f"-FU{work}",
                     f"-Fl{work}", f"-o{binary}", str(PAS_SOURCE)], work)
        result = run([str(binary)], work)
        output = result.stdout.strip()
        if output != EXPECTED:
            raise RuntimeError(f"unexpected output: {output!r}; expected {EXPECTED!r}")
        print("PASCAL-C-ABI-PASS")
        print(output)
        print("C archive: libprobe.a")
        print("Pascal compiler output:")
        print(build.stdout.strip())
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"PASCAL-C-ABI-FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
