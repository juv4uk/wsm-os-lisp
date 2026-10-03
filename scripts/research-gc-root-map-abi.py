#!/usr/bin/env python3
"""#62 — fail-closed GC root-map ABI research witness.

This is NOT a collector.  It models the information contract needed for a
runtime allocator to consume compiler-proved exact roots at one call site.

Key x86-64 relation at allocator entry:

    callee_rsp -> return address
    caller_rsp_at_call = callee_rsp + 8
    stack_root_address = caller_rsp_at_call + certified_offset

Missing metadata is NOT-A-SAFEPOINT, never an empty root set.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Iterable


WORD = 8
REWRITEABLE_REGS = frozenset({"%rsi", "%rdx"})


class LookupStatus(str, Enum):
    CERTIFIED = "CERTIFIED"
    NOT_A_SAFEPOINT = "NOT-A-SAFEPOINT"
    ALLOCATOR_KIND_MISMATCH = "ALLOCATOR-KIND-MISMATCH"


@dataclass(frozen=True)
class RootRecord:
    return_pc: int
    allocator_kind: str
    frame_size: int
    stack_offsets: tuple[int, ...]
    register_roots: tuple[str, ...]
    certificate_kind: str
    version: int = 1
    certified_empty: bool = False

    def validate(self) -> None:
        if self.return_pc <= 0:
            raise ValueError("return_pc must be positive")
        if not self.allocator_kind:
            raise ValueError("allocator_kind must be non-empty")
        if self.frame_size < 0 or self.frame_size % WORD != 0:
            raise ValueError("frame_size must be a non-negative word multiple")
        if self.version != 1:
            raise ValueError("unsupported root-map version")

        if len(set(self.stack_offsets)) != len(self.stack_offsets):
            raise ValueError("duplicate stack root offset")
        if len(set(self.register_roots)) != len(self.register_roots):
            raise ValueError("duplicate register root")

        for offset in self.stack_offsets:
            if offset < 0 or offset % WORD != 0:
                raise ValueError("stack root offset must be aligned and non-negative")
            if offset + WORD > self.frame_size:
                raise ValueError("stack root offset lies outside certified frame")

        for reg in self.register_roots:
            if reg not in REWRITEABLE_REGS:
                raise ValueError(f"unsupported/non-rewriteable root register: {reg}")

        if not self.stack_offsets and not self.register_roots and not self.certified_empty:
            raise ValueError("zero-root certificate requires explicit certified_empty=true")
        if self.certified_empty and (self.stack_offsets or self.register_roots):
            raise ValueError("certified_empty conflicts with declared roots")


@dataclass(frozen=True)
class Lookup:
    status: LookupStatus
    record: RootRecord | None


class RootMap:
    def __init__(self, records: Iterable[RootRecord]) -> None:
        self._by_pc: dict[int, RootRecord] = {}
        for record in records:
            record.validate()
            if record.return_pc in self._by_pc:
                raise ValueError("ambiguous duplicate return_pc")
            self._by_pc[record.return_pc] = record

    def lookup(self, return_pc: int, allocator_kind: str) -> Lookup:
        record = self._by_pc.get(return_pc)
        if record is None:
            return Lookup(LookupStatus.NOT_A_SAFEPOINT, None)
        if record.allocator_kind != allocator_kind:
            return Lookup(LookupStatus.ALLOCATOR_KIND_MISMATCH, None)
        return Lookup(LookupStatus.CERTIFIED, record)


@dataclass
class MachineState:
    callee_rsp: int
    stack_words: dict[int, int]
    registers: dict[str, int]

    @property
    def caller_rsp_at_call(self) -> int:
        return self.callee_rsp + WORD


@dataclass(frozen=True)
class RootLocation:
    kind: str
    name: str
    address: int | None = None


def exact_root_locations(record: RootRecord, state: MachineState) -> tuple[RootLocation, ...]:
    record.validate()
    locations: list[RootLocation] = []

    for offset in record.stack_offsets:
        address = state.caller_rsp_at_call + offset
        if address not in state.stack_words:
            raise ValueError(f"certified stack location absent from machine state: {address:#x}")
        locations.append(RootLocation("stack", f"rsp+{offset}", address))

    for reg in record.register_roots:
        if reg not in state.registers:
            raise ValueError(f"certified register absent from machine state: {reg}")
        locations.append(RootLocation("register", reg, None))

    return tuple(locations)


def read_root(location: RootLocation, state: MachineState) -> int:
    if location.kind == "stack":
        assert location.address is not None
        return state.stack_words[location.address]
    if location.kind == "register":
        return state.registers[location.name]
    raise AssertionError(location.kind)


def rewrite_roots(
    record: RootRecord,
    state: MachineState,
    moved: dict[int, int],
) -> tuple[RootLocation, ...]:
    """Rewrite only explicitly certified locations, as a moving-GC thought experiment."""
    locations = exact_root_locations(record, state)
    for location in locations:
        old = read_root(location, state)
        new = moved.get(old, old)
        if location.kind == "stack":
            assert location.address is not None
            state.stack_words[location.address] = new
        else:
            state.registers[location.name] = new
    return locations


def assert_raises(fragment: str, fn) -> None:
    try:
        fn()
    except ValueError as exc:
        if fragment not in str(exc):
            raise AssertionError(f"expected {fragment!r}, got {exc!r}") from exc
    else:
        raise AssertionError(f"expected ValueError containing {fragment!r}")


def main() -> None:
    certified = RootRecord(
        return_pc=0x401050,
        allocator_kind="wsm_cons",
        frame_size=64,
        stack_offsets=(16, 40),
        register_roots=("%rsi", "%rdx"),
        certificate_kind="runtime-call-structured",
    )
    other_site = RootRecord(
        return_pc=0x401090,
        allocator_kind="wsm_cons",
        frame_size=32,
        stack_offsets=(8,),
        register_roots=("%rsi", "%rdx"),
        certificate_kind="list-bounded",
    )
    explicitly_empty = RootRecord(
        return_pc=0x4010D0,
        allocator_kind="synthetic-empty-proof",
        frame_size=0,
        stack_offsets=(),
        register_roots=(),
        certificate_kind="empty-positive-control",
        certified_empty=True,
    )

    table = RootMap((other_site, explicitly_empty, certified))

    # 1. Exact site lookup.
    hit = table.lookup(0x401050, "wsm_cons")
    assert hit.status is LookupStatus.CERTIFIED
    assert hit.record == certified

    # 2. Another site in the same function/code region without metadata is NOT a safepoint.
    miss = table.lookup(0x401070, "wsm_cons")
    assert miss.status is LookupStatus.NOT_A_SAFEPOINT
    assert miss.record is None

    # 3. Allocator kind participates in the key contract.
    mismatch = table.lookup(0x401050, "wsm_closure_new")
    assert mismatch.status is LookupStatus.ALLOCATOR_KIND_MISMATCH
    assert mismatch.record is None

    # 4. Certified empty is distinguishable from absent metadata.
    empty = table.lookup(0x4010D0, "synthetic-empty-proof")
    assert empty.status is LookupStatus.CERTIFIED
    assert empty.record is not None and empty.record.certified_empty
    assert not empty.record.stack_offsets and not empty.record.register_roots
    assert empty != miss

    # 5. x86 caller-stack address law and rewriteable locations.
    callee_rsp = 0x7FFF_0000
    caller_rsp = callee_rsp + WORD
    state = MachineState(
        callee_rsp=callee_rsp,
        stack_words={
            caller_rsp + 16: 0x1001,  # certified live root A
            caller_rsp + 24: 0xDEAD_BEEF,  # pointer-looking dead/non-root word
            caller_rsp + 40: 0x1003,  # certified live root B
        },
        registers={
            "%rsi": 0x1005,
            "%rdx": 0x1007,
            "%r12": 0xCAFE_0000,  # RuntimeContext mechanism pointer, never a root
        },
    )
    locations = exact_root_locations(certified, state)
    assert [(x.kind, x.name) for x in locations] == [
        ("stack", "rsp+16"),
        ("stack", "rsp+40"),
        ("register", "%rsi"),
        ("register", "%rdx"),
    ]
    assert locations[0].address == caller_rsp + 16
    assert locations[1].address == caller_rsp + 40

    dead_before = state.stack_words[caller_rsp + 24]
    ctx_before = state.registers["%r12"]

    moved = {
        0x1001: 0x2001,
        0x1003: 0x2003,
        0x1005: 0x2005,
        0x1007: 0x2007,
        0xDEAD_BEEF: 0xBAD0_0000,  # must NOT be applied to unlisted stack word
        0xCAFE_0000: 0xBAD0_0001,  # must NOT rewrite RuntimeContext
    }
    rewrite_roots(certified, state, moved)

    assert state.stack_words[caller_rsp + 16] == 0x2001
    assert state.stack_words[caller_rsp + 40] == 0x2003
    assert state.registers["%rsi"] == 0x2005
    assert state.registers["%rdx"] == 0x2007
    assert state.stack_words[caller_rsp + 24] == dead_before
    assert state.registers["%r12"] == ctx_before

    # 6. Table ordering/relabeling does not affect lookup semantics.
    table_reordered = RootMap((certified, explicitly_empty, other_site))
    assert table_reordered.lookup(0x401050, "wsm_cons") == hit
    assert table_reordered.lookup(0x401070, "wsm_cons") == miss

    # 7. Falsifiers.
    assert_raises(
        "ambiguous duplicate return_pc",
        lambda: RootMap((certified, certified)),
    )
    assert_raises(
        "aligned",
        lambda: RootRecord(
            return_pc=1,
            allocator_kind="wsm_cons",
            frame_size=32,
            stack_offsets=(3,),
            register_roots=("%rsi",),
            certificate_kind="bad",
        ).validate(),
    )
    assert_raises(
        "outside certified frame",
        lambda: RootRecord(
            return_pc=1,
            allocator_kind="wsm_cons",
            frame_size=32,
            stack_offsets=(32,),
            register_roots=("%rsi",),
            certificate_kind="bad",
        ).validate(),
    )
    assert_raises(
        "unsupported/non-rewriteable",
        lambda: RootRecord(
            return_pc=1,
            allocator_kind="wsm_cons",
            frame_size=32,
            stack_offsets=(8,),
            register_roots=("%r12",),
            certificate_kind="bad",
        ).validate(),
    )
    assert_raises(
        "explicit certified_empty",
        lambda: RootRecord(
            return_pc=1,
            allocator_kind="synthetic",
            frame_size=0,
            stack_offsets=(),
            register_roots=(),
            certificate_kind="bad",
        ).validate(),
    )

    print("GC-ROOT-MAP-ABI-WITNESS=PASS")
    print("LOOKUP-KEY=return-pc+allocator-kind")
    print("STACK-ADDRESS-LAW=callee-rsp+8+certified-offset")
    print("MISSING-METADATA=NOT-A-SAFEPOINT")
    print("CERTIFIED-EMPTY-DISTINCT-FROM-ABSENT=PASS")
    print("PER-SITE-LOOKUP=PASS")
    print("MOVING-REWRITE-STACK-ROOTS=PASS")
    print("MOVING-REWRITE-REGISTER-ROOTS=PASS")
    print("POINTER-LOOKING-DEAD-WORD-UNTOUCHED=PASS")
    print("RUNTIME-CONTEXT-NOT-ROOT=PASS")
    print("DUPLICATE-RETURN-PC=REJECTED")
    print("UNALIGNED/OOB-OFFSETS=REJECTED")
    print("UNKNOWN-ROOT-REGISTER=REJECTED")
    print("ALLOCATOR-KIND-MISMATCH=REJECTED")
    print("COLLECTOR-ENABLED=0")
    print("SEMANTIC-AUTHORITY=NONE")
    print("STATUS=BOUNDED-ROOT-MAP-ABI-WITNESSED")


if __name__ == "__main__":
    main()
