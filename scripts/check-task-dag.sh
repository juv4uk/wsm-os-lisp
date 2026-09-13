#!/usr/bin/env bash
# Verify tasks.my is a trustworthy DAG: a completed (done) task may only
# depend on predecessors that are themselves completed, explicitly superseded,
# or marked as an umbrella whose decomposition covers the needed work.
# Also fail closed on duplicate task IDs and on superseded tasks that do not
# say what superseded them.
#
# Status mapping (machine-readable, consistent with historical ledger forms):
#   (done . t)                    -> DONE
#   (done . (t . "note"))         -> DONE
#   (done . ()) / (done . nil)    -> OPEN
#   (superseded . t)              -> SUPERSEDED (non-blocking for descendants)
#   (superseded . (t . "note"))   -> SUPERSEDED
#   missing (done ...)            -> OPEN
#   (umbrella . t)                -> UMBRELLA (non-blocking for descendants)
set -euo pipefail

task_file="tasks.my"

python3 - "$task_file" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

def fail(msg):
    print("TASK-DAG-FAIL: " + msg, file=sys.stderr)
    sys.exit(1)

header_re = re.compile(r'^\s*\("([^"]+)"\s*\.\s*(\(\s*)?$', re.M)
matches = list(header_re.finditer(text))
if not matches:
    fail("no task headers found; tasks.my structure unexpected")

blocks = []
for i, m in enumerate(matches):
    block_id = m.group(1)
    nxt = matches[i + 1] if i + 1 < len(matches) else None
    seg = text[m.end():nxt.start() if nxt else len(text)]
    blocks.append((block_id, m.end() + 1, seg))

# duplicate task IDs
seen = {}
dupes = set()
for block_id, start_line, _ in blocks:
    if block_id not in seen:
        seen[block_id] = start_line
    else:
        dupes.add(block_id)
if dupes:
    fail("duplicate task IDs: " + ", ".join(sorted(dupes)) + f" (task_file line offsets: {', '.join(str(seen[b]) for b in sorted(dupes))})")

by_id = {b[0]: b for b in blocks}

def has(seg, field):
    return bool(re.search(r'\(' + re.escape(field) + r'\s*\.', seg))

def status_of(block):
    seg = block[2]
    if not has(seg, "done"):
        return "OPEN"
    if re.search(r'\(done\s*\.\s*t\s*\)', seg) or re.search(r'\(done\s*\.\s*\(t\s*\.', seg):
        return "DONE"
    return "OPEN"

def is_superseded(block):
    seg = block[2]
    return bool(re.search(r'\(superseded\s*\.\s*t\s*\)', seg) or re.search(r'\(superseded\s*\.\s*\(t\s*\.', seg))

def is_umbrella(block):
    seg = block[2]
    return re.search(r'\(umbrella\s*\.\s*t\s*\)', seg) is not None

def has_superseded_by(block):
    return has(block[2], "superseded-by")

def depends_of(block):
    seg = block[2]
    m = re.search(r'\(depends-on\s*\.\s*\(([^)]*)\)\)', seg)
    if not m:
        return []
    return m.group(1).split()

errors = []
for block_id, start_line, seg in blocks:
    if is_superseded((block_id, start_line, seg)):
        if not has_superseded_by((block_id, start_line, seg)):
            errors.append(
                f"{block_id} (line ~{start_line}): superseded but missing superseded-by"
            )
        continue
    if status_of((block_id, start_line, seg)) != "DONE":
        continue
    for dep in depends_of((block_id, start_line, seg)):
        depblock = by_id.get(dep)
        if depblock is None:
            errors.append(f"{block_id} (line ~{start_line}): depends on unknown task {dep}")
            continue
        dep_ok = (
            status_of(depblock) == "DONE"
            or is_superseded(depblock)
            or is_umbrella(depblock)
        )
        if not dep_ok:
            errors.append(
                f"{block_id} (line ~{start_line}): DONE but depends on non-DONE, "
                f"non-superseded, non-umbrella predecessor {dep} (line ~{depblock[1]})"
            )

if errors:
    fail("\n  ".join(errors))

print("TASK-DAG-PASS: tasks.my DAG is consistent (no DONE task depends on an OPEN predecessor)")
PY