#!/usr/bin/env python3
"""#64 — consume CML_GC_ROOT_MAP_V1 without enabling collection.

The compiler-side manifest names symbolic return labels. Those labels are not
runtime PCs by themselves. This witness parses/validates the wire and requires
an explicit label->final-PC binding before reusing #62's RootRecord/RootMap law.
"""

from __future__ import annotations

from dataclasses import dataclass
import importlib.util
import sys
from pathlib import Path
from typing import Mapping

HERE = Path(__file__).resolve().parent
ABI_PATH = HERE / "research-gc-root-map-abi.py"
REWRITEABLE_REGS = frozenset({"%rsi", "%rdx"})


def load_abi():
    spec = importlib.util.spec_from_file_location("gc_root_map_abi", ABI_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@dataclass(frozen=True)
class ProducerRecord:
    site_id: int
    return_label: str
    allocator_kind: str
    certificate_kind: str
    frame_size: int
    stack_offsets: tuple[int, ...]
    register_roots: tuple[str, ...]

    @property
    def certified_empty(self) -> bool:
        return not self.stack_offsets and not self.register_roots

    def validate(self) -> None:
        if self.site_id < 0:
            raise ValueError("site id must be non-negative")
        if self.return_label != f".Lgc_return_{self.site_id}":
            raise ValueError("return label does not match site id")
        if not self.allocator_kind:
            raise ValueError("allocator kind must be non-empty")
        if not self.certificate_kind:
            raise ValueError("certificate kind must be non-empty")
        if self.frame_size < 0 or self.frame_size % 8 != 0:
            raise ValueError("frame size must be a non-negative word multiple")
        if tuple(sorted(self.stack_offsets)) != self.stack_offsets:
            raise ValueError("stack offsets must be sorted")
        if len(set(self.stack_offsets)) != len(self.stack_offsets):
            raise ValueError("duplicate stack offset")
        for offset in self.stack_offsets:
            if offset < 0 or offset % 8 != 0:
                raise ValueError("stack offset must be aligned and non-negative")
            if offset + 8 > self.frame_size:
                raise ValueError("stack offset lies outside certified frame")
        if tuple(sorted(self.register_roots)) != self.register_roots:
            raise ValueError("register roots must be sorted")
        if len(set(self.register_roots)) != len(self.register_roots):
            raise ValueError("duplicate register root")
        for reg in self.register_roots:
            if reg not in REWRITEABLE_REGS:
                raise ValueError(f"unsupported rewriteable register: {reg}")


def parse_list(raw: str, *, integer: bool):
    if raw == "-":
        return ()
    parts = raw.split(",")
    if integer:
        try:
            return tuple(int(part) for part in parts)
        except ValueError as exc:
            raise ValueError("invalid integer list") from exc
    return tuple(parts)


def parse_manifest(text: str) -> tuple[ProducerRecord, ...]:
    lines = text.splitlines()
    if not lines or lines[0] != "CML_GC_ROOT_MAP_V1":
        raise ValueError("unsupported root-map manifest version")

    records: list[ProducerRecord] = []
    seen_ids: set[int] = set()
    seen_labels: set[str] = set()
    required = {"id", "label", "allocator", "kind", "frame", "stack", "regs"}

    for raw in lines[1:]:
        if not raw:
            continue
        if not raw.startswith("site "):
            raise ValueError("invalid root-map record prefix")
        fields: dict[str, str] = {}
        for token in raw[5:].split():
            if "=" not in token:
                raise ValueError("invalid root-map token")
            key, value = token.split("=", 1)
            if key in fields:
                raise ValueError("duplicate root-map field")
            fields[key] = value
        if set(fields) != required:
            raise ValueError("root-map field set mismatch")

        try:
            site_id = int(fields["id"])
            frame_size = int(fields["frame"])
        except ValueError as exc:
            raise ValueError("invalid numeric root-map field") from exc

        record = ProducerRecord(
            site_id=site_id,
            return_label=fields["label"],
            allocator_kind=fields["allocator"],
            certificate_kind=fields["kind"],
            frame_size=frame_size,
            stack_offsets=parse_list(fields["stack"], integer=True),
            register_roots=parse_list(fields["regs"], integer=False),
        )
        record.validate()
        if record.site_id in seen_ids:
            raise ValueError("duplicate root-map site id")
        if record.return_label in seen_labels:
            raise ValueError("duplicate root-map return label")
        seen_ids.add(record.site_id)
        seen_labels.add(record.return_label)
        records.append(record)

    if [record.site_id for record in records] != sorted(record.site_id for record in records):
        raise ValueError("root-map records must be sorted by site id")
    return tuple(records)


def bind_final_pcs(records: tuple[ProducerRecord, ...], symbols: Mapping[str, int]):
    abi = load_abi()
    bound = []
    seen_pcs: set[int] = set()
    for record in records:
        if record.return_label not in symbols:
            raise ValueError(f"unresolved return label: {record.return_label}")
        return_pc = symbols[record.return_label]
        if return_pc <= 0:
            raise ValueError("resolved return PC must be positive")
        if return_pc in seen_pcs:
            raise ValueError("duplicate resolved return PC")
        seen_pcs.add(return_pc)

        root_record = abi.RootRecord(
            return_pc=return_pc,
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


def assert_rejects(fragment: str, fn) -> None:
    try:
        fn()
    except ValueError as exc:
        if fragment not in str(exc):
            raise AssertionError(f"expected {fragment!r}, got {exc!r}") from exc
    else:
        raise AssertionError(f"expected rejection containing {fragment!r}")


def main() -> None:
    abi = load_abi()
    manifest = """CML_GC_ROOT_MAP_V1
site id=0 label=.Lgc_return_0 allocator=wsm_cons kind=runtime-call-structured frame=64 stack=16,40 regs=%rdx,%rsi
site id=1 label=.Lgc_return_1 allocator=wsm_cons kind=pack-rest-bounded frame=48 stack=8,24 regs=%rdx,%rsi
"""
    records = parse_manifest(manifest)
    assert len(records) == 2

    # Symbolic labels are not runtime addresses. Explicit binding is mandatory.
    symbols = {
        ".Lgc_return_0": 0x401050,
        ".Lgc_return_1": 0x401090,
    }
    bound = bind_final_pcs(records, symbols)
    table = abi.RootMap(bound)

    assert table.lookup(0x401050, "wsm_cons").status is abi.LookupStatus.CERTIFIED
    assert table.lookup(0x401090, "wsm_cons").status is abi.LookupStatus.CERTIFIED
    assert table.lookup(0x401070, "wsm_cons").status is abi.LookupStatus.NOT_A_SAFEPOINT
    assert (
        table.lookup(0x401050, "wsm_closure_new").status
        is abi.LookupStatus.ALLOCATOR_KIND_MISMATCH
    )

    # Relabel/address change is mechanism-only: rebinding changes PCs, not roots.
    rebound = bind_final_pcs(
        records,
        {
            ".Lgc_return_0": 0x501050,
            ".Lgc_return_1": 0x501090,
        },
    )
    assert [r.stack_offsets for r in rebound] == [r.stack_offsets for r in bound]
    assert [r.register_roots for r in rebound] == [r.register_roots for r in bound]

    assert_rejects(
        "unresolved return label",
        lambda: bind_final_pcs(records, {".Lgc_return_0": 0x401050}),
    )
    assert_rejects(
        "duplicate resolved return PC",
        lambda: bind_final_pcs(
            records,
            {".Lgc_return_0": 0x401050, ".Lgc_return_1": 0x401050},
        ),
    )

    corrupt = manifest.replace("CML_GC_ROOT_MAP_V1", "CML_GC_ROOT_MAP_V2", 1)
    assert_rejects("unsupported", lambda: parse_manifest(corrupt))

    bad_label = manifest.replace(".Lgc_return_0", ".Lgc_return_9", 1)
    assert_rejects("does not match site id", lambda: parse_manifest(bad_label))

    bad_offset = manifest.replace("stack=16,40", "stack=16,64", 1)
    assert_rejects("outside certified frame", lambda: parse_manifest(bad_offset))

    bad_reg = manifest.replace("regs=%rdx,%rsi", "regs=%rax", 1)
    assert_rejects("unsupported rewriteable register", lambda: parse_manifest(bad_reg))

    unsorted = manifest.replace("stack=16,40", "stack=40,16", 1)
    assert_rejects("stack offsets must be sorted", lambda: parse_manifest(unsorted))

    duplicate_field = manifest.replace(
        "site id=0 ",
        "site id=0 id=0 ",
        1,
    )
    assert_rejects("duplicate root-map field", lambda: parse_manifest(duplicate_field))

    print("GC-ROOT-MAP-WIRE-CONSUMER=PASS")
    print("WIRE=CML_GC_ROOT_MAP_V1")
    print("SYMBOLIC-RETURN-LABEL-PARSE=PASS")
    print("FINAL-PC-BINDING=EXPLICIT-REQUIRED")
    print("UNRESOLVED-LABEL=REJECTED")
    print("DUPLICATE-FINAL-PC=REJECTED")
    print("MISSING-SITE=NOT-A-SAFEPOINT")
    print("ALLOCATOR-MISMATCH=REJECTED")
    print("BAD-VERSION/LABEL/OFFSET/REGISTER=REJECTED")
    print("COLLECTOR-ENABLED=0")
    print("SEMANTIC-AUTHORITY=NONE")
    print("STATUS=BOUNDED-WIRE-CONSUMER-WITNESSED")


if __name__ == "__main__":
    main()
