#!/usr/bin/env python3
"""Policy-enforcement gate (ADR-005, D2).

A policy is a property of this system only when three parts exist:

  1. an enforcement point in the mechanism layer,
  2. a witness where the policy actually refused something,
  3. a gate that runs in CI.

This script re-checks every record in policy-enforcement.lisp against the tree.
It does not trust the registry: a record that cannot be re-checked fails the
build instead of being cited. Written as a real s-expression reader rather than
a shell/awk pattern match, because a gate that mis-parses is worse than none.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "policy-enforcement.lisp"
WORKFLOWS = ROOT / ".github" / "workflows"
SELF = "scripts/check-policy-enforcement.py"

REQUIRED = ("id", "claim", "enforcement", "witness", "gate", "status")


class GateError(Exception):
    pass


# --- minimal s-expression reader -------------------------------------------


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
                if text[i] == "\\" and i + 1 < n:
                    buf.append(text[i + 1])
                    i += 2
                    continue
                buf.append(text[i])
                i += 1
            if i >= n:
                raise GateError("unterminated string literal in registry")
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
                raise GateError("unbalanced ')' in registry")
            done = stack.pop()
            stack[-1].append(done)
        else:
            kind, value = tok
            stack[-1].append(value if kind == "str" else ("atom", value))
    if len(stack) != 1:
        raise GateError("unbalanced '(' in registry")
    return stack[0]


def atom(node) -> str | None:
    if isinstance(node, tuple) and node[0] == "atom":
        return node[1]
    return None


def string(node) -> str | None:
    return node if isinstance(node, str) else None


def find(node, name: str):
    """First child list of `node` whose head atom is `name`."""
    if not isinstance(node, list):
        return None
    for child in node:
        if isinstance(child, list) and child and atom(child[0]) == name:
            return child
    return None


def find_all(node, name: str) -> list:
    out = []
    if isinstance(node, list):
        for child in node:
            if isinstance(child, list) and child and atom(child[0]) == name:
                out.append(child)
    return out


# --- verification ----------------------------------------------------------


def read_records() -> list[dict]:
    if not REGISTRY.is_file():
        raise GateError(f"registry {REGISTRY.relative_to(ROOT)} is missing")
    tree = parse(REGISTRY.read_text(encoding="utf-8"))
    if len(tree) != 1:
        raise GateError("registry must contain exactly one top-level form")
    top = tree[0]
    if atom(top[0]) != "policy-enforcement-registry":
        raise GateError("top-level form must be (policy-enforcement-registry ...)")

    policies = find(top, "policies")
    if policies is None:
        raise GateError("registry has no (policies ...) section")

    records = []
    for entry in find_all(policies, "policy"):
        rec: dict = {}
        for name in REQUIRED:
            node = find(entry, name)
            rec[name] = node[1:] if node else None
        rec["gate-gap"] = (find(entry, "gate-gap") or [None, None])[1:]
        records.append(rec)
    return records


def check_enforcement(rid: str, node) -> str:
    if not node:
        raise GateError(f"{rid}: enforcement is missing")
    kind = atom(node[0])
    if kind == "literal":
        if len(node) < 3:
            raise GateError(f"{rid}: (enforcement literal <file> \"<text>\") needs a file and a literal")
        rel, literal = string(node[1]), string(node[2])
        if not rel or literal is None:
            raise GateError(f"{rid}: enforcement literal needs quoted file and text")
        path = ROOT / rel
        if not path.is_file():
            raise GateError(f"{rid}: enforcement file {rel} does not exist")
        if literal not in path.read_text(encoding="utf-8", errors="replace"):
            raise GateError(
                f"{rid}: enforcement literal {literal!r} is not present in {rel} — "
                "the claim has no mechanism behind it"
            )
        return f"literal {rel}"
    if kind == "absent":
        patterns = [string(p) or atom(p) for p in node[1:]]
        patterns = [p for p in patterns if p]
        if not patterns:
            raise GateError(f"{rid}: (enforcement absent ...) needs at least one pattern")
        for pattern in patterns:
            hits = [
                p
                for p in ROOT.rglob(pattern)
                if ".git" not in p.parts
            ][:3]
            if hits:
                joined = ", ".join(str(h.relative_to(ROOT)) for h in hits)
                raise GateError(f"{rid}: forbidden path {pattern!r} exists ({joined}) — absence claim is false")
        return f"absent {' '.join(patterns)}"
    raise GateError(f"{rid}: unknown enforcement kind {kind!r} (expected literal or absent)")


def check_witness(rid: str, node) -> str:
    if not node:
        raise GateError(f"{rid}: witness is missing")
    kind = atom(node[0])
    if kind == "transcript":
        if len(node) < 3:
            raise GateError(f"{rid}: (witness transcript <file> \"<text>\") needs a file and a literal")
        rel, literal = string(node[1]), string(node[2])
        if not rel or literal is None:
            raise GateError(f"{rid}: witness transcript needs quoted file and text")
        path = ROOT / rel
        if not path.is_file():
            raise GateError(f"{rid}: witness file {rel} does not exist")
        if literal not in path.read_text(encoding="utf-8", errors="replace"):
            raise GateError(
                f"{rid}: witness literal {literal!r} is not present in {rel} — "
                "the policy was never observed refusing anything"
            )
        return f"transcript {rel}"
    if kind == "runtime":
        return "runtime (produced by the gate itself)"
    raise GateError(f"{rid}: unknown witness kind {kind!r} (expected transcript or runtime)")


def workflow_references(rel: str) -> list[str]:
    hits = []
    if not WORKFLOWS.is_dir():
        return hits
    for wf in sorted(WORKFLOWS.glob("*.y*ml")):
        if rel in wf.read_text(encoding="utf-8", errors="replace"):
            hits.append(wf.name)
    return hits


def check_gate(rid: str, node, gap) -> tuple[str, str | None]:
    if not node:
        raise GateError(f"{rid}: gate is missing")
    value = string(node[0]) or atom(node[0])
    if value == "manual":
        why = string(gap[0]) if gap else None
        if not why:
            raise GateError(f"{rid}: manual gate must declare (gate-gap \"...\")")
        return "manual", why
    if not value:
        raise GateError(f"{rid}: gate must name a script or be manual")
    path = ROOT / value
    if not path.is_file():
        raise GateError(f"{rid}: gate script {value} does not exist")
    wfs = workflow_references(value)
    if not wfs:
        raise GateError(
            f"{rid}: gate script {value} is not referenced by any workflow under "
            ".github/workflows — it never runs"
        )
    return value, None


# --- mechanism vocabulary ------------------------------------------------

ASM_COMMENT = "#"


def strip_asm_comments(text: str) -> str:
    out = []
    for line in text.splitlines():
        cut = line.find(ASM_COMMENT)
        out.append(line[:cut] if cut >= 0 else line)
    return "\n".join(out)


def read_reserved_codes() -> dict[str, str]:
    tree = parse(REGISTRY.read_text(encoding="utf-8"))
    top = tree[0]
    block = find(top, "reserved-mechanism-codes")
    if block is None:
        return {}
    reserved: dict[str, str] = {}
    for entry in find_all(block, "code"):
        name = atom(entry[1]) if len(entry) > 1 else None
        if not name:
            raise GateError("reserved-mechanism-codes: (code <NAME> \"<reason>\") needs a name")
        reason = string(entry[2]) if len(entry) > 2 else None
        if not reason:
            raise GateError(f"reserved-mechanism-codes: {name} needs a reason")
        if name in reserved:
            raise GateError(f"reserved-mechanism-codes: duplicate {name}")
        reserved[name] = reason
    return reserved


def read_ungated_declarations() -> dict[str, tuple[str, str]]:
    tree = parse(REGISTRY.read_text(encoding="utf-8"))
    block = find(tree[0], "ungated-check-scripts")
    if block is None:
        return {}
    declared: dict[str, tuple[str, str]] = {}
    for entry in find_all(block, "script"):
        rel = string(entry[1]) if len(entry) > 1 else None
        why = string(entry[2]) if len(entry) > 2 else None
        nxt = string(entry[3]) if len(entry) > 3 else None
        if not rel or not why or not nxt:
            raise GateError('ungated-check-scripts: (script "<path>" "<why>" "<next action>") needs all three')
        if rel in declared:
            raise GateError(f"ungated-check-scripts: duplicate {rel}")
        declared[rel] = (why, nxt)
    return declared


def read_arbiter_budget() -> dict:
    tree = parse(REGISTRY.read_text(encoding="utf-8"))
    block = find(tree[0], "arbiter-budget")
    if block is None:
        raise GateError("registry has no (arbiter-budget ...) block; ADR-005 W5 would be unenforced")

    def field(name):
        node = find(block, name)
        if node is None or len(node) < 2:
            raise GateError(f"arbiter-budget: missing ({name} ...)")
        return node[1:]

    share_node = field("max-share")
    try:
        max_share = float(atom(share_node[0]) or string(share_node[0]) or "")
    except ValueError:
        raise GateError("arbiter-budget: max-share must be a number")
    if not 0 < max_share <= 1:
        raise GateError("arbiter-budget: max-share must be a fraction between 0 and 1")

    glob_node = field("arbiter-glob")
    arbiter_glob = string(glob_node[0]) or atom(glob_node[0])
    ext_node = field("code-extensions")
    extensions = [string(x) or atom(x) for x in ext_node]
    pref_node = field("excluded-prefix")
    excluded = string(pref_node[0]) or atom(pref_node[0])
    return {
        "max_share": max_share,
        "arbiter_glob": arbiter_glob,
        "extensions": [e for e in extensions if e],
        "excluded": excluded,
    }


def count_lines(path: Path) -> int:
    try:
        return len(path.read_text(encoding="utf-8", errors="replace").splitlines())
    except OSError:
        return 0


def check_arbiter_budget(budget: dict) -> tuple[float, int, int]:
    arbiter_files = sorted(ROOT.glob(budget["arbiter_glob"]))
    if not arbiter_files:
        raise GateError(f"arbiter-budget: glob {budget['arbiter_glob']} matched no file")
    arbiter_lines = sum(count_lines(p) for p in arbiter_files)

    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files"], capture_output=True, text=True
    )
    if tracked.returncode != 0:
        raise GateError("arbiter-budget: git ls-files failed, cannot measure the denominator")
    total = 0
    for rel in tracked.stdout.splitlines():
        if budget["excluded"] and rel.startswith(budget["excluded"]):
            continue
        if not any(rel.endswith(ext) for ext in budget["extensions"]):
            continue
        total += count_lines(ROOT / rel)
    if total <= 0:
        raise GateError("arbiter-budget: denominator is zero, cannot measure a share")

    share = arbiter_lines / total
    if share > budget["max_share"]:
        raise GateError(
            f"arbiter-budget: the arbiter is {arbiter_lines}/{total} lines = {share:.1%} "
            f"of hand-written code, above the declared ceiling of {budget['max_share']:.0%} — "
            "shrink it, or change the ceiling as an explicit owner decision"
        )
    return share, arbiter_lines, total


def check_vocabulary(reserved: dict[str, str]) -> tuple[int, int]:
    """Every constant defined in the mechanism layer is emitted, or declared reserved.

    A constant that exists only as a .set line is vocabulary the mechanism does
    not implement. That is allowed only when the registry says so out loud, and
    the declaration must be removed once the constant is emitted — otherwise the
    list rots into a place where dead code hides.
    """
    src = sorted((ROOT / "src").glob("*.s"))
    if not src:
        raise GateError("no src/*.s files found; the vocabulary check would pass vacuously")

    defined: list[str] = []
    for path in src:
        for line in strip_asm_comments(path.read_text(encoding="utf-8", errors="replace")).splitlines():
            m = re.match(r"\s*\.set\s+([A-Za-z_][A-Za-z0-9_]*)\s*,", line)
            if m:
                defined.append(m.group(1))
    if not defined:
        raise GateError("no .set definitions found in src/*.s; the vocabulary check would pass vacuously")

    corpus = "\n".join(
        strip_asm_comments(p.read_text(encoding="utf-8", errors="replace"))
        for p in src + sorted((ROOT / "artifacts").glob("*.s"))
    )

    unemitted = set()
    for name in sorted(set(defined)):
        if len(re.findall(r"\b" + re.escape(name) + r"\b", corpus)) <= 1:
            unemitted.add(name)

    undeclared = sorted(unemitted - set(reserved))
    if undeclared:
        raise GateError(
            "mechanism constants defined but never emitted, and not declared reserved: "
            + ", ".join(undeclared)
            + " — declare them under (reserved-mechanism-codes ...) with a reason, or delete them"
        )

    stale = sorted(set(reserved) - unemitted)
    if stale:
        raise GateError(
            "reserved-mechanism-codes lists constants that are emitted (or do not exist): "
            + ", ".join(stale)
            + " — remove them from the reserved list"
        )

    return len(set(defined)), len(unemitted)


def main() -> int:
    try:
        records = read_records()
    except GateError as exc:
        print(f"POLICY-ENFORCEMENT-FAIL: {exc}", file=sys.stderr)
        return 1

    if not records:
        print(
            "POLICY-ENFORCEMENT-FAIL: registry contains no policy record; the gate would pass vacuously",
            file=sys.stderr,
        )
        return 1

    try:
        reserved = read_reserved_codes()
    except GateError as exc:
        print(f"POLICY-ENFORCEMENT-FAIL: {exc}", file=sys.stderr)
        return 1

    gaps: list[str] = []
    seen: set[str] = set()
    try:
        for rec in records:
            rid = atom(rec["id"][0]) if rec["id"] else None
            if not rid:
                raise GateError("a record has no (id ...)")
            if rid in seen:
                raise GateError(f"{rid}: duplicate policy id")
            seen.add(rid)

            claim = string(rec["claim"][0]) if rec["claim"] else None
            if not claim:
                raise GateError(f"{rid}: claim is empty")

            status = atom(rec["status"][0]) if rec["status"] else None
            if status != "proved":
                raise GateError(
                    f"{rid}: status is {status!r} — intentions belong in docs/VISION.md, not in the registry"
                )

            check_enforcement(rid, rec["enforcement"])
            check_witness(rid, rec["witness"])
            _, gap = check_gate(rid, rec["gate"], rec["gate-gap"])
            if gap:
                gaps.append(f"  {rid}: {gap}")
    except GateError as exc:
        print(f"POLICY-ENFORCEMENT-FAIL: {exc}", file=sys.stderr)
        return 1

    try:
        budget = read_arbiter_budget()
        share, arbiter_lines, total_lines = check_arbiter_budget(budget)
    except GateError as exc:
        print(f"POLICY-ENFORCEMENT-FAIL: {exc}", file=sys.stderr)
        return 1

    try:
        defined, unemitted = check_vocabulary(reserved)
    except GateError as exc:
        print(f"POLICY-ENFORCEMENT-FAIL: {exc}", file=sys.stderr)
        return 1

    # Visibility, not failure: check scripts that no workflow runs are debt.
    ungated = []
    for script in sorted((ROOT / "scripts").glob("check-*")):
        rel = f"scripts/{script.name}"
        if rel == SELF or script.suffix not in {".sh", ".py"}:
            continue
        if not workflow_references(rel):
            ungated.append(rel)

    try:
        declared_ungated = read_ungated_declarations()
    except GateError as exc:
        print(f"POLICY-ENFORCEMENT-FAIL: {exc}", file=sys.stderr)
        return 1

    undeclared = [rel for rel in ungated if rel not in declared_ungated]
    if undeclared:
        print(
            "POLICY-ENFORCEMENT-FAIL: check scripts with no workflow and no declaration: "
            + ", ".join(undeclared)
            + " — add them to (ungated-check-scripts ...) with a reason and a next action, or gate them",
            file=sys.stderr,
        )
        return 1

    stale_decl = sorted(set(declared_ungated) - set(ungated))
    if stale_decl:
        print(
            "POLICY-ENFORCEMENT-FAIL: (ungated-check-scripts ...) declares scripts that are gated or missing: "
            + ", ".join(stale_decl)
            + " — remove them from the list",
            file=sys.stderr,
        )
        return 1

    if ungated:
        print("POLICY-ENFORCEMENT: check scripts that no workflow references (declared debt):", file=sys.stderr)
        for rel in ungated:
            why, nxt = declared_ungated[rel]
            print(f"  {rel}", file=sys.stderr)
            print(f"    why: {why}", file=sys.stderr)
            print(f"    next: {nxt}", file=sys.stderr)

    if gaps:
        print("POLICY-ENFORCEMENT: policies with a declared gate gap:", file=sys.stderr)
        for line in gaps:
            print(line, file=sys.stderr)

    print(
        f"POLICY-ENFORCEMENT-PASS: {len(records)} proved policies re-checked, "
        f"{len(gaps)} with a declared gate gap, {len(ungated)} check scripts without an automated gate; "
        f"{unemitted}/{defined} mechanism constants are reserved-but-unemitted; "
        f"arbiter {arbiter_lines}/{total_lines} lines = {share:.1%} of hand-written code "
        f"(ceiling {budget['max_share']:.0%})."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
