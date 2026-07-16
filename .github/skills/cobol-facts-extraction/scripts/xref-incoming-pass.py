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

SKILL_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = SKILL_ROOT.parent.parent.parent
DOC_ROOT = REPO_ROOT / "docs" / "_shared"


def load_facts_files() -> list[tuple[Path, dict, str]]:
    out: list[tuple[Path, dict, str]] = []
    if not DOC_ROOT.exists():
        return out
    for path in sorted(DOC_ROOT.glob("*/facts.json")):
        try:
            original = path.read_bytes().decode("utf-8")
            data = json.loads(original)
        except Exception as e:
            print(f"WARN: skipping unreadable {path}: {e}", file=sys.stderr)
            continue
        out.append((path, data, original))
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


def build_xref(files: list[tuple[Path, dict, str]]) -> dict[str, list[dict]]:
    by_program: dict[str, str] = {}     # program_id -> caller_source key (basename)
    by_basename: dict[str, str] = {}    # source basename upper -> caller_source key
    by_source_kind: dict[str, str] = {}  # source_path -> source_kind
    for _path, data, _orig in files:
        bn = basename_key(data["source_path"])
        by_basename[bn] = data["source_path"]
        by_source_kind[data["source_path"]] = data.get("source_kind", "")
        pid = data.get("program_id")
        if pid:
            by_program[pid.upper()] = data["source_path"]

    edges: dict[str, list[dict]] = {}

    def add_edge(target_source: str, edge: dict) -> None:
        edges.setdefault(target_source, []).append(edge)

    for _path, data, _orig in files:
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
            # Reset forward resolution every run for determinism.
            step["resolved_source"] = None
            step["resolved_kind"] = None
            pgm = (step.get("program") or "").upper()
            proc = (step.get("proc") or "").upper()
            is_proc = not pgm and bool(proc)
            target_name = pgm or proc
            if not target_name:
                continue
            target_source = by_program.get(target_name)
            if target_source == caller_source:
                target_source = None
            if not target_source:
                # Resolve by file basename. A proc invocation must prefer a
                # PROC source (.PRC/.PROC); never resolve to the caller itself.
                candidates = [
                    cand_src for cand_bn, cand_src in by_basename.items()
                    if cand_bn.split(".")[0] == target_name
                    and cand_src != caller_source
                ]
                if is_proc:
                    proc_cands = [
                        s for s in candidates
                        if Path(s).suffix.upper() in (".PRC", ".PROC")
                    ]
                    candidates = proc_cands or candidates
                target_source = candidates[0] if candidates else None
            if not target_source:
                continue
            # Forward resolution: record on the JCL step so downstream
            # facts-slices / bundles know the EXEC target exists in the
            # workspace (drives CATALOGED vs UNRESOLVED in the section doc).
            step["resolved_source"] = target_source
            step["resolved_kind"] = by_source_kind.get(target_source)
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
    for path, data, original in files:
        # Pristine pre-mutation snapshot (build_xref mutated `data` in place).
        baseline = json.loads(original)
        # build_xref may have set jcl_steps[].resolved_* in place; also apply
        # the freshly computed incoming_xref before comparing/serializing.
        data["incoming_xref"] = edges.get(data["source_path"], [])
        if data == baseline:
            unchanged += 1
            continue
        # Preserve the file's existing newline convention to keep the pass
        # byte-deterministic across platforms (no spurious LF<->CRLF churn).
        nl = "\r\n" if "\r\n" in original else "\n"
        text = json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False) + "\n"
        if nl == "\r\n":
            text = text.replace("\n", "\r\n")
        path.write_text(text, encoding="utf-8", newline="")
        written += 1
    print(f"OK: xref pass scanned={len(files)} updated={written} unchanged={unchanged}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
