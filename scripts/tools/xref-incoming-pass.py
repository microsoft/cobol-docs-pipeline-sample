#!/usr/bin/env python3
"""Workspace-scope incoming-xref pass for phase B.

Scans every facts.json under docs/_shared/**/facts.json, builds the
inverted caller graph from `calls[]`, `copybooks[]` and `jcl_steps[]`,
then rewrites each target file's `incoming_xref[]` in place.

Deterministic: re-running with no upstream changes produces byte-identical
files (entries sorted by caller_source then line).

Usage:
    py -3 xref-incoming-pass.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


SCRIPT_ROOT = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_ROOT.parent.parent
DOC_ROOT = REPO_ROOT / "docs" / "_shared"


def load_facts_files() -> list[tuple[Path, dict]]:
    out: list[tuple[Path, dict]] = []
    if not DOC_ROOT.exists():
        return out
    for path in sorted(DOC_ROOT.glob("*/facts.json")):
        try:
            data = json.loads(path.read_bytes().decode("utf-8"))
        except Exception as e:
            print(f"WARN: skipping unreadable {path}: {e}", file=sys.stderr)
            continue
        out.append((path, data))
    return out


def basename_key(source_path: str) -> str:
    """Match callers to facts files via the source basename (file name only).

    Matches the convention that every facts.json lives at
    docs/_shared/<basename-with-ext>/facts.json.
    """
    return Path(source_path).name.upper()


def target_object_name(target: str) -> str:
    """Return the object name from an optional IBM i LIBRARY/OBJECT target."""
    return target.upper().rsplit("/", 1)[-1]


def build_xref(files: list[tuple[Path, dict]]) -> dict[str, list[dict]]:
    by_program: dict[str, str] = {}     # program_id -> caller_source key (basename)
    by_basename: dict[str, str] = {}    # source basename upper -> caller_source key
    for _path, data in files:
        bn = basename_key(data["source_path"])
        by_basename[bn] = data["source_path"]
        pid = data.get("program_id")
        if pid:
            by_program[pid.upper()] = data["source_path"]

    edges: dict[str, list[dict]] = {}

    def add_edge(target_source: str, edge: dict) -> None:
        edges.setdefault(target_source, []).append(edge)

    for _path, data in files:
        caller_source = data["source_path"]
        caller_kind = data["source_kind"]
        for c in data.get("calls", []):
            tgt = target_object_name(c.get("target", ""))
            target_source = by_program.get(tgt)
            if not target_source:
                # try treating target as a file basename match (foo.CBL)
                for cand_bn, cand_src in by_basename.items():
                    if cand_bn.split(".")[0] == tgt:
                        target_source = cand_src
                        break
            if not target_source:
                continue
            add_edge(target_source, {
                "caller_source": caller_source,
                "caller_kind": caller_kind,
                "via": c["kind"] if c["kind"] in (
                    "call", "cics-link", "cics-xctl", "cl-call", "cl-callprc", "cl-submit-job"
                ) else "call",
                "line": c["line"],
            })
        for cp in data.get("copybooks", []):
            name = cp["name"].upper()
            target_source = None
            for cand_bn, cand_src in by_basename.items():
                if cand_bn.split(".")[0] == name:
                    target_source = cand_src
                    break
            if not target_source:
                continue
            add_edge(target_source, {
                "caller_source": caller_source,
                "caller_kind": caller_kind,
                "via": "copy",
                "line": cp["line"],
            })
        for step in data.get("jcl_steps", []):
            pgm = (step.get("program") or "").upper()
            if not pgm:
                continue
            target_source = by_program.get(pgm)
            if not target_source:
                for cand_bn, cand_src in by_basename.items():
                    if cand_bn.split(".")[0] == pgm:
                        target_source = cand_src
                        break
            if not target_source:
                continue
            add_edge(target_source, {
                "caller_source": caller_source,
                "caller_kind": caller_kind,
                "via": "jcl-step",
                "line": step["start_line"],
            })

    # Sort each target's edges deterministically.
    for k in edges:
        edges[k].sort(key=lambda e: (e["caller_source"], e["line"], e["via"]))
    return edges


def main(_argv: list[str] | None = None) -> int:
    files = load_facts_files()
    if not files:
        print("OK: no facts.json files found")
        return 0
    edges = build_xref(files)
    written = 0
    unchanged = 0
    for path, data in files:
        new_xref = edges.get(data["source_path"], [])
        if data.get("incoming_xref") == new_xref:
            unchanged += 1
            continue
        data["incoming_xref"] = new_xref
        text = json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False)
        path.write_text(text + "\n", encoding="utf-8")
        written += 1
    print(f"OK: xref pass scanned={len(files)} updated={written} unchanged={unchanged}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
