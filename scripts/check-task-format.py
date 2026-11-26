#!/usr/bin/env python3
"""Task-format gate: Definition of Done items 1-3, enforced on new tasks.

The owner's agent prompt says a task carries its level, an evidence plan and
fail-safely triggers, or it is not ready to be worked on. 54 tasks predate that
rule, so they are listed in task-format-disposition.lisp as legacy and this gate
enforces the format only on tasks that are not on that list.

The list is checked in both directions: a legacy task that gains the fields must
leave the list, and a legacy task that no longer exists must leave it too. A list
that can only grow becomes a place where the rule quietly stops applying.

Run: python3 scripts/check-task-format.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TASKS = ROOT / "tasks.lisp"
DISPOSITION = ROOT / "task-format-disposition.lisp"

LEVELS = {"asm", "pascal", "c", "sens", "lisp"}
REQUIRED = ("level", "evidence-plan", "fail-safely")


class GateError(Exception):
    pass


def tokenize(text: str):
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == ";":
            while i < n and text[i] != "\n":
                i += 1
        elif ch.isspace():
            i += 1
        elif ch in "()":
            yield ch
            i += 1
        elif ch == '"':
            i += 1
            buf = []
            while i < n and text[i] != '"':
                buf.append(text[i])
                i += 1
            if i >= n:
                raise GateError("unterminated string literal")
            i += 1
            yield ("str", "".join(buf))
        else:
            start = i
            while i < n and not text[i].isspace() and text[i] not in "()":
                i += 1
            yield ("atom", text[start:i])


def parse(text: str):
    stack: list[list] = [[]]
    for tok in tokenize(text):
        if tok == "(":
            stack.append([])
        elif tok == ")":
            if len(stack) < 2:
                raise GateError("unbalanced ')'")
            done = stack.pop()
            stack[-1].append(done)
        else:
            kind, value = tok
            stack[-1].append(value if kind == "str" else ("atom", value))
    if len(stack) != 1:
        raise GateError("unbalanced '('")
    return stack[0]


def atom(node):
    return node[1] if isinstance(node, tuple) and node[0] == "atom" else None


def string(node):
    return node if isinstance(node, str) else None


def pairs(node) -> dict:
    """Collect (key . value) children of an alist form.

    tasks.lisp writes each field as its own dotted pair list, so the body is a
    list of lists, not a flat sequence of key, dot, value.
    """
    out: dict = {}
    if not isinstance(node, list):
        return out
    for child in node:
        if not isinstance(child, list) or len(child) < 3:
            continue
        key = atom(child[0])
        if key and atom(child[1]) == ".":
            out[key] = child[2]
    return out


def read_legacy() -> set[str]:
    if not DISPOSITION.is_file():
        raise GateError("task-format-disposition.lisp is missing")
    tree = parse(DISPOSITION.read_text(encoding="utf-8"))
    if len(tree) != 1 or atom(tree[0][0]) != "task-format-disposition":
        raise GateError("task-format-disposition.lisp must hold one (task-format-disposition ...) form")
    block = None
    for child in tree[0]:
        if isinstance(child, list) and child and atom(child[0]) == "legacy-tasks":
            block = child
    if block is None:
        raise GateError("task-format-disposition.lisp has no (legacy-tasks ...) section")
    legacy = set()
    for entry in block[1:]:
        if isinstance(entry, list) and entry and atom(entry[0]) == "legacy-task":
            name = string(entry[1]) if len(entry) > 1 else None
            if not name:
                raise GateError('entries must be (legacy-task "<TASK-ID>")')
            legacy.add(name)
    return legacy


def read_tasks() -> dict[str, dict]:
    if not TASKS.is_file():
        raise GateError("tasks.lisp is missing")
    tree = parse(TASKS.read_text(encoding="utf-8"))
    if len(tree) != 1:
        raise GateError("tasks.lisp must hold one top-level form")
    top = pairs(tree[0])
    tasks_node = top.get("tasks")
    if not isinstance(tasks_node, list):
        raise GateError("tasks.lisp has no (tasks . (...)) section")

    tasks: dict[str, dict] = {}
    for entry in tasks_node:
        if not isinstance(entry, list) or len(entry) < 3:
            continue
        name = string(entry[0])
        if not name or atom(entry[1]) != ".":
            continue
        tasks[name] = pairs(entry[2])
    return tasks


def main() -> int:
    try:
        legacy = read_legacy()
        tasks = read_tasks()
    except GateError as exc:
        print(f"TASK-FORMAT-FAIL: {exc}", file=sys.stderr)
        return 1

    if not tasks:
        print("TASK-FORMAT-FAIL: no tasks parsed; the gate would pass vacuously", file=sys.stderr)
        return 1
    if not legacy:
        print("TASK-FORMAT-FAIL: no legacy tasks declared; every task would need the new format", file=sys.stderr)
        return 1

    problems: list[str] = []

    for name, fields in sorted(tasks.items()):
        if name in legacy:
            gained = [f for f in REQUIRED if f in fields]
            if gained:
                problems.append(
                    f"{name}: legacy task now carries {', '.join(gained)} — remove it from "
                    "task-format-disposition.lisp so the rule applies to it"
                )
            continue

        level = atom(fields.get("level"))
        if level is None:
            problems.append(f"{name}: new task has no (level . asm|pascal|c|sens|lisp)")
        elif level.lower() not in LEVELS:
            problems.append(f"{name}: level '{level}' is not one of {sorted(LEVELS)}")

        plan = string(fields.get("evidence-plan"))
        if not plan or not plan.strip():
            problems.append(f"{name}: new task has no (evidence-plan . \"...\") — DoD item 4")

        triggers = fields.get("fail-safely")
        if triggers is None:
            problems.append(f"{name}: new task has no (fail-safely . (...)) — DoD item 3")
        elif isinstance(triggers, str) and not triggers.strip():
            problems.append(f"{name}: (fail-safely ...) is empty")
        elif isinstance(triggers, list) and not triggers:
            problems.append(f"{name}: (fail-safely ...) lists no trigger")

    for gone in sorted(legacy - set(tasks)):
        problems.append(f"{gone}: listed as legacy but no longer exists — remove it from the disposition")

    if problems:
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        print(
            f"TASK-FORMAT-FAIL: {len(problems)} problem(s). A task without level, evidence plan and "
            "fail-safely triggers is not ready to be worked on.",
            file=sys.stderr,
        )
        return 1

    print(
        f"TASK-FORMAT-PASS: {len(tasks) - len(legacy & set(tasks))} formatted tasks, "
        f"{len(legacy & set(tasks))} declared legacy, 0 problems."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
