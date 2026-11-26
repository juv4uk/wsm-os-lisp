#!/usr/bin/env python3
"""Branch-policy gate: detective control for the owner's "no new branches" rule.

The directive of 2026-10-11 forbids creating any new branch and requires finished
work to land directly in main. Until now that rule was text in AGENTS.md with no
mechanism behind it, and a branch was created anyway on 2026-11-26.

Prevention needs repository admin rights (a GitHub ruleset with the "Restrict
creations" rule — see contracts/github-ruleset-no-new-branches.json). This script
is the part that needs only read access, so an agent can run it:

  * a remote branch that is not listed in branch-disposition.lisp  -> FAIL
  * a listed branch whose tip moved                                -> FAIL
  * a listed branch that no longer exists                          -> WARN (intended end state)

Run: python3 scripts/check-branch-policy.py [--remote origin]
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DISPOSITION = ROOT / "branch-disposition.lisp"


class GateError(Exception):
    pass


# --- minimal s-expression reader (same shape as the policy gate) ------------


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
                raise GateError("unterminated string literal in disposition file")
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
                raise GateError("unbalanced ')' in disposition file")
            done = stack.pop()
            stack[-1].append(done)
        else:
            kind, value = tok
            stack[-1].append(value if kind == "str" else ("atom", value))
    if len(stack) != 1:
        raise GateError("unbalanced '(' in disposition file")
    return stack[0]


def atom(node):
    return node[1] if isinstance(node, tuple) and node[0] == "atom" else None


def string(node):
    return node if isinstance(node, str) else None


def find(node, name):
    if not isinstance(node, list):
        return None
    for child in node:
        if isinstance(child, list) and child and atom(child[0]) == name:
            return child
    return None


def read_disposition() -> dict[str, str]:
    if not DISPOSITION.is_file():
        raise GateError("branch-disposition.lisp is missing")
    tree = parse(DISPOSITION.read_text(encoding="utf-8"))
    if len(tree) != 1 or atom(tree[0][0]) != "branch-disposition":
        raise GateError("branch-disposition.lisp must contain one (branch-disposition ...) form")
    branches = find(tree[0], "branches")
    if branches is None:
        raise GateError("branch-disposition.lisp has no (branches ...) section")
    allowed: dict[str, str] = {}
    for entry in branches[1:]:
        if not isinstance(entry, list) or atom(entry[0]) != "branch":
            continue
        name, sha = string(entry[1]), string(entry[2])
        if not name or not sha:
            raise GateError('every entry must be (branch "<name>" "<tip-sha>")')
        if name in allowed:
            raise GateError(f"duplicate branch entry: {name}")
        allowed[name] = sha
    if not allowed:
        raise GateError("no branch entries; the gate would pass vacuously")
    return allowed


def remote_heads(remote: str) -> dict[str, str]:
    proc = subprocess.run(
        ["git", "-C", str(ROOT), "ls-remote", "--heads", remote],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise GateError(
            f"git ls-remote {remote} failed: {proc.stderr.strip()[:200]} — "
            "without the remote list this gate cannot check anything"
        )
    heads: dict[str, str] = {}
    for line in proc.stdout.splitlines():
        sha, ref = line.split("\t", 1)
        heads[ref.replace("refs/heads/", "")] = sha
    return heads


def main(argv: list[str]) -> int:
    remote = "origin"
    if "--remote" in argv:
        remote = argv[argv.index("--remote") + 1]

    try:
        allowed = read_disposition()
        heads = remote_heads(remote)
    except GateError as exc:
        print(f"BRANCH-POLICY-FAIL: {exc}", file=sys.stderr)
        return 1

    new_branches = sorted(set(heads) - set(allowed))
    moved = sorted(
        name for name, sha in allowed.items()
        if name in heads and sha != "moving" and heads[name] != sha
    )
    missing = sorted(set(allowed) - set(heads))

    if missing:
        print("BRANCH-POLICY-NOTE: listed branches that no longer exist (intended end state):", file=sys.stderr)
        for name in missing:
            print(f"  {name}", file=sys.stderr)
        print("  remove them from branch-disposition.lisp when convenient", file=sys.stderr)

    if moved:
        for name in moved:
            print(
                f"BRANCH-POLICY-FAIL: {name} moved from {allowed[name][:12]} to {heads[name][:12]} — "
                "these branches are frozen; land work in main instead",
                file=sys.stderr,
            )

    if new_branches:
        for name in new_branches:
            print(
                f"BRANCH-POLICY-FAIL: {name} exists and is not in branch-disposition.lisp — "
                "the owner directive of 2026-10-11 forbids new branches; delete it or record an exception",
                file=sys.stderr,
            )

    if moved or new_branches:
        return 1

    print(
        f"BRANCH-POLICY-PASS: {len(heads)} remote heads match the disposition "
        f"({len(allowed)} recorded, {len(missing)} already deleted)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
