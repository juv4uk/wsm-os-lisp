#!/usr/bin/env python3
"""#66 — consume relocated CML safepoint-PC bindings without enabling GC.

Parent #65 validates CML_GC_ROOT_MAP_V1 and proves that symbolic labels alone
cannot authorize collection. This child consumes the linked binary
.wsm_gc_root_pc_bind section emitted by cml#433 and binds records by site id.

Binary record (little-endian, 16 bytes):
    u64 site_id
    u64 final_pc
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
import struct
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
WIRE_PATH = HERE / "research-gc-root-map-wire-consumer.py"


def load_wire():
    spec = importlib.util.spec_from_file_location("gc_root_wire", WIRE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def parse_pc_bindings(data: bytes) -> dict[int, int]:
    if len(data) % 16:
        raise ValueError("PC binding section length must be a multiple of 16")

    bindings: dict[int, int] = {}
    seen_pcs: set[int] = set()
    for offset in range(0, len(data), 16):
        site_id, final_pc = struct.unpack_from("<QQ", data, offset)
        if site_id in bindings:
            raise ValueError("duplicate PC binding site id")
        if final_pc == 0:
            raise ValueError("resolved final PC must be non-zero")
        if final_pc in seen_pcs:
            raise ValueError("duplicate resolved final PC")
        bindings[site_id] = final_pc
        seen_pcs.add(final_pc)
    return bindings


def bind_by_site_id(records, bindings: dict[int, int]):
    wire = load_wire()
    expected = {record.site_id for record in records}
    actual = set(bindings)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise ValueError(f"PC binding site set mismatch: missing={missing} extra={extra}")

    bound = []
    for record in records:
        root_record = wire.load_abi().RootRecord(
            return_pc=bindings[record.site_id],
            allocator_kind=record.allocator_kind,
            frame_size=record.frame_size,
            stack_offsets=record.stack_offsets,
            register_roots=record.register_roots,
            certificate_kind=record.certificate_kind,
            version=1,
            certified_empty=record.certified_empty,
        )
        root_record.validate()
        bound.append(root_record)
    return tuple(bound)


def link_binding_section(text_base: str) -> bytes:
    source = r"""
.text
.globl _start
_start:
    call wsm_cons
.Lgc_return_0:
    nop
    call wsm_cons
.Lgc_return_1:
    nop
    call wsm_closure_new
.Lgc_return_2:
    nop
wsm_cons:
    ret
wsm_closure_new:
    ret

.section .wsm_gc_root_pc_bind,"a",@progbits
.p2align 3
.quad 0
.quad .Lgc_return_0
.quad 1
.quad .Lgc_return_1
.quad 2
.quad .Lgc_return_2
"""
    with tempfile.TemporaryDirectory(prefix="wsm-gc-pc-bind-") as tmp:
        tmp = Path(tmp)
        asm = tmp / "witness.s"
        obj = tmp / "witness.o"
        elf = tmp / "witness.elf"
        raw = tmp / "bindings.bin"
        asm.write_text(source)

        subprocess.run(["as", "--64", str(asm), "-o", str(obj)], check=True)
        subprocess.run(
            ["ld", "-m", "elf_x86_64", "-e", "_start", f"-Ttext={text_base}",
             str(obj), "-o", str(elf)],
            check=True,
        )
        subprocess.run(
            ["objcopy", "-O", "binary", "--only-section=.wsm_gc_root_pc_bind",
             str(elf), str(raw)],
            check=True,
        )
        return raw.read_bytes()


def assert_rejects(fragment: str, fn) -> None:
    try:
        fn()
    except ValueError as exc:
        if fragment not in str(exc):
            raise AssertionError(f"expected {fragment!r}, got {exc!r}") from exc
    else:
        raise AssertionError(f"expected rejection containing {fragment!r}")


def main() -> None:
    wire = load_wire()
    manifest = """CML_GC_ROOT_MAP_V1
site id=0 label=.Lgc_return_0 allocator=wsm_cons kind=runtime-call-structured frame=64 stack=16,40 regs=%rdx,%rsi
site id=1 label=.Lgc_return_1 allocator=wsm_cons kind=pack-rest-bounded frame=48 stack=8,24 regs=%rdx,%rsi
site id=2 label=.Lgc_return_2 allocator=wsm_closure_new kind=closure-new-bounded frame=32 stack=- regs=%rdx
"""
    records = wire.parse_manifest(manifest)

    low_data = link_binding_section("0x100000")
    high_data = link_binding_section("0x200000")
    low = parse_pc_bindings(low_data)
    high = parse_pc_bindings(high_data)

    assert sorted(low) == [0, 1, 2]
    assert sorted(high) == [0, 1, 2]
    assert all(high[site] - low[site] == 0x100000 for site in low)

    low_bound = bind_by_site_id(records, low)
    high_bound = bind_by_site_id(records, high)
    assert [r.stack_offsets for r in low_bound] == [r.stack_offsets for r in high_bound]
    assert [r.register_roots for r in low_bound] == [r.register_roots for r in high_bound]

    abi = wire.load_abi()
    table = abi.RootMap(low_bound)
    assert table.lookup(low[0], "wsm_cons").status is abi.LookupStatus.CERTIFIED
    assert table.lookup(low[1], "wsm_cons").status is abi.LookupStatus.CERTIFIED
    assert table.lookup(low[2], "wsm_closure_new").status is abi.LookupStatus.CERTIFIED
    assert (
        table.lookup(low[2], "wsm_cons").status
        is abi.LookupStatus.ALLOCATOR_KIND_MISMATCH
    )
    assert table.lookup(low[0] + 1, "wsm_cons").status is abi.LookupStatus.NOT_A_SAFEPOINT

    assert_rejects("multiple of 16", lambda: parse_pc_bindings(low_data + b"\x00"))
    assert_rejects(
        "duplicate PC binding site id",
        lambda: parse_pc_bindings(low_data + low_data[:16]),
    )

    zero_pc = bytearray(low_data)
    zero_pc[8:16] = b"\x00" * 8
    assert_rejects("non-zero", lambda: parse_pc_bindings(bytes(zero_pc)))

    duplicate_pc = bytearray(low_data)
    duplicate_pc[24:32] = duplicate_pc[8:16]
    assert_rejects("duplicate resolved final PC", lambda: parse_pc_bindings(bytes(duplicate_pc)))

    assert_rejects(
        "site set mismatch",
        lambda: bind_by_site_id(records, {0: low[0]}),
    )
    assert_rejects(
        "site set mismatch",
        lambda: bind_by_site_id(records, {0: low[0], 1: low[1], 9: 0x900000}),
    )

    print("GC-ROOT-PC-BINDING=PASS")
    print("PRODUCER-BINDING=ELF-RELOCATION")
    print("RUNTIME-KEY=FINAL-PC+ALLOCATOR-KIND")
    print("CLOSURE-NEW-POSITIVE=PASS")
    print("SYMBOL-TABLE-LOOKUP=0")
    print("DISASSEMBLY-GUESSING=0")
    print("MISSING/EXTRA/DUPLICATE-BINDING=REJECTED")
    print("COLLECTOR-ENABLED=0")
    print("SEMANTIC-AUTHORITY=NONE")


if __name__ == "__main__":
    main()
