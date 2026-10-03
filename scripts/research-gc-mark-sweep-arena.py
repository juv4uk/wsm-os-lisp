#!/usr/bin/env python3
"""Bounded WSM cons-arena mark/sweep mechanism witness for wsm-os-lisp#60.

Research mechanism only. No production collector is enabled.
Live substrate facts modeled from current runtime.s / entry.s:
- 64 KiB cons arena
- 4096 fixed 16-byte cells
- cons tag 000, pointer is the aligned cell address
- current runtime uses bump high-water allocation

Candidate-A model:
- 4096-bit mark bitmap (512 B)
- iterative u16 worklist (<= 8192 B worst case)
- sweep + free-list reuse
- explicit model roots only
"""
from __future__ import annotations

from dataclasses import dataclass
from collections import deque

HEAP_BASE = 0x100000
CAPACITY = 4096
CELL_BYTES = 16
TAG_MASK = 0b111
TAG_CONS = 0
NIL = 1
FREE_NONE = 0xFFFF
MARK_BITMAP_BYTES = CAPACITY // 8
WORKLIST_MAX_BYTES = CAPACITY * 2


class HeapError(RuntimeError):
    pass


@dataclass
class Cell:
    car: int = NIL
    cdr: int = NIL
    allocated: bool = False
    next_free: int = FREE_NONE


class Arena:
    def __init__(self) -> None:
        self.cells = [Cell() for _ in range(CAPACITY)]
        self.high_water = 0
        self.free_head = FREE_NONE
        self.marked = [False] * CAPACITY
        self.max_worklist = 0
        self.sweep_inspections = 0

    @staticmethod
    def word_for(index: int) -> int:
        if not (0 <= index < CAPACITY):
            raise HeapError("cell index out of range")
        return HEAP_BASE + index * CELL_BYTES

    @staticmethod
    def index_for(word: int) -> int | None:
        if word & TAG_MASK != TAG_CONS:
            return None
        if word < HEAP_BASE or word >= HEAP_BASE + CAPACITY * CELL_BYTES:
            return None
        delta = word - HEAP_BASE
        if delta % CELL_BYTES != 0:
            raise HeapError("cons-looking word is not cell-aligned")
        return delta // CELL_BYTES

    def cons(self, car: int, cdr: int) -> int:
        if self.free_head != FREE_NONE:
            index = self.free_head
            cell = self.cells[index]
            self.free_head = cell.next_free
        elif self.high_water < CAPACITY:
            index = self.high_water
            self.high_water += 1
            cell = self.cells[index]
        else:
            raise HeapError("OOM")
        cell.car = car
        cell.cdr = cdr
        cell.allocated = True
        cell.next_free = FREE_NONE
        return self.word_for(index)

    def read(self, word: int) -> tuple[int, int]:
        index = self.index_for(word)
        if index is None:
            raise HeapError("not a cons word")
        if index >= self.high_water or not self.cells[index].allocated:
            raise HeapError("stale or unallocated cons word")
        cell = self.cells[index]
        return cell.car, cell.cdr

    def mark(self, roots: list[int]) -> int:
        work: deque[int] = deque()
        for word in roots:
            index = self.index_for(word)
            if index is None:
                continue
            if index >= self.high_water or not self.cells[index].allocated:
                raise HeapError("root points at stale/unallocated cell")
            work.append(index)
        while work:
            self.max_worklist = max(self.max_worklist, len(work))
            index = work.pop()
            if self.marked[index]:
                continue
            cell = self.cells[index]
            if not cell.allocated:
                raise HeapError("trace reached unallocated cell")
            self.marked[index] = True
            for word in (cell.car, cell.cdr):
                child = self.index_for(word)
                if child is None:
                    continue
                if child >= self.high_water or not self.cells[child].allocated:
                    raise HeapError("trace reached stale/unallocated cell")
                if not self.marked[child]:
                    work.append(child)
        return sum(self.marked[: self.high_water])

    def sweep(self) -> int:
        reclaimed = 0
        self.free_head = FREE_NONE
        self.sweep_inspections = 0
        for index in range(self.high_water - 1, -1, -1):
            self.sweep_inspections += 1
            cell = self.cells[index]
            if not cell.allocated:
                continue
            if self.marked[index]:
                self.marked[index] = False
                continue
            cell.allocated = False
            cell.car = NIL
            cell.cdr = NIL
            cell.next_free = self.free_head
            self.free_head = index
            reclaimed += 1
        return reclaimed

    def collect(self, roots: list[int]) -> tuple[int, int]:
        live = self.mark(roots)
        reclaimed = self.sweep()
        return live, reclaimed

    def live_indices(self) -> set[int]:
        return {i for i in range(self.high_water) if self.cells[i].allocated}


def make_chain(arena: Arena, length: int, tail: int = NIL) -> int:
    root = tail
    for _ in range(length):
        root = arena.cons(NIL, root)
    return root


def list_length(arena: Arena, word: int) -> int:
    n = 0
    seen: set[int] = set()
    while word != NIL:
        idx = arena.index_for(word)
        if idx is None:
            raise HeapError("non-list atom in cdr")
        if idx in seen:
            raise HeapError("cycle in list witness")
        seen.add(idx)
        _, word = arena.read(word)
        n += 1
    return n


def early_vs_late() -> None:
    def workload(force_every: bool) -> tuple[int, int]:
        arena = Arena()
        live = NIL
        for _ in range(128):
            _garbage = arena.cons(NIL, NIL)
            live = arena.cons(NIL, live)
            if force_every:
                arena.collect([live])
        if not force_every:
            arena.collect([live])
        return list_length(arena, live), len(arena.live_indices())

    assert workload(False) == workload(True) == (128, 128)


def main() -> None:
    assert MARK_BITMAP_BYTES == 512
    assert WORKLIST_MAX_BYTES == 8192

    arena = Arena()
    live = make_chain(arena, 4)
    garbage = make_chain(arena, 3)
    garbage_indices = {
        arena.index_for(garbage),
        arena.index_for(arena.read(garbage)[1]),
        arena.index_for(arena.read(arena.read(garbage)[1])[1]),
    }
    assert None not in garbage_indices
    before = set(arena.live_indices())
    live_count, reclaimed = arena.collect([live])
    assert live_count == 4
    assert reclaimed == 3
    assert list_length(arena, live) == 4
    assert len(before) == 7
    assert arena.sweep_inspections == 7
    reused = [arena.index_for(arena.cons(NIL, NIL)) for _ in range(3)]
    assert set(reused) == garbage_indices

    cycle = Arena()
    x = cycle.cons(NIL, NIL)
    y = cycle.cons(NIL, x)
    xi = cycle.index_for(x)
    yi = cycle.index_for(y)
    assert xi is not None and yi is not None
    cycle.cells[xi].cdr = y
    assert cycle.collect([x]) == (2, 0)
    assert cycle.collect([]) == (0, 2)

    deep = Arena()
    root = make_chain(deep, CAPACITY)
    assert deep.high_water == CAPACITY
    live_count, reclaimed = deep.collect([root])
    assert (live_count, reclaimed) == (CAPACITY, 0)
    assert deep.max_worklist <= CAPACITY
    assert deep.max_worklist * 2 <= WORKLIST_MAX_BYTES
    assert deep.sweep_inspections == CAPACITY

    full = Arena()
    roots = [full.cons(NIL, NIL) for _ in range(CAPACITY)]
    survivors = roots[::2]
    live_count, reclaimed = full.collect(survivors)
    assert live_count == CAPACITY // 2
    assert reclaimed == CAPACITY // 2
    for _ in range(reclaimed):
        full.cons(NIL, NIL)
    assert len(full.live_indices()) == CAPACITY
    try:
        full.cons(NIL, NIL)
    except HeapError as exc:
        assert str(exc) == "OOM"
    else:
        raise AssertionError("full heap must remain OOM after exact refill")

    early_vs_late()

    pointer_shape = Arena()
    root = pointer_shape.cons(0x100003, NIL)
    assert pointer_shape.collect([root]) == (1, 0)

    bad = HEAP_BASE + 8
    try:
        pointer_shape.collect([bad])
    except HeapError as exc:
        assert "not cell-aligned" in str(exc)
    else:
        raise AssertionError("unaligned cons-looking root must fail closed")

    print("WSM-GC-MARK-SWEEP-CANDIDATE=PASS")
    print(f"HEAP-CAPACITY-CELLS={CAPACITY}")
    print(f"HEAP-BYTES={CAPACITY * CELL_BYTES}")
    print(f"MARK-BITMAP-BYTES={MARK_BITMAP_BYTES}")
    print(f"U16-WORKLIST-WORST-BYTES={WORKLIST_MAX_BYTES}")
    print(f"FULL-SWEEP-INSPECTIONS={CAPACITY}")
    print("FREE-LIST-ALLOC=O(1)-MODEL")
    print("UNREACHABLE-REUSE=PASS")
    print("ROOTED-CYCLE=PASS")
    print("UNROOTED-CYCLE-RECLAIM=PASS")
    print("DEEP-4096-CHAIN=ITERATIVE-PASS")
    print("FORCE-EARLY-VS-LATE-SEMANTICS=PASS")
    print("UNALIGNED-CONS-LOOKING-ROOT=FAIL-CLOSED")
    print("ROOT-PROTOCOL=EXPLICIT-MODEL-ONLY")
    print("RUNTIME-OOM-REPLACED=0")
    print("COLLECTOR-ENABLED=0")
    print("SEMANTIC-AUTHORITY=NONE")


if __name__ == "__main__":
    main()
