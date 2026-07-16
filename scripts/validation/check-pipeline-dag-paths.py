#!/usr/bin/env python3
"""Validate that every `scripts:` entry in config/pipeline-dag.yaml points to a
file that exists on disk. Emits a short report and a "did you mean" hint for
each stale entry by matching basenames across .github/skills/*/scripts/.

Exit codes:
  0  every referenced script exists
  1  one or more stale references
  2  pipeline-dag.yaml could not be loaded

Usage:
    python scripts/validation/check-pipeline-dag-paths.py
    python scripts/validation/check-pipeline-dag-paths.py --dag path/to/pipeline-dag.yaml
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DAG = REPO_ROOT / "config" / "pipeline-dag.yaml"
# Paths in the DAG are resolved against these bases in order.
SEARCH_BASES = (REPO_ROOT / ".github", REPO_ROOT)


def collect_script_refs(dag: dict) -> list[tuple[str, str]]:
    """Return [(location, script_path), ...] for every `scripts:` entry."""
    refs: list[tuple[str, str]] = []
    for phase in dag.get("phases", []) or []:
        pid = phase.get("id", "?")
        for s in phase.get("scripts", []) or []:
            refs.append((f"phase {pid}", s))
        for agent in phase.get("agents", []) or []:
            aname = agent.get("name", "?")
            ascope = agent.get("scope", "?")
            for s in agent.get("scripts", []) or []:
                refs.append((f"phase {pid} / {aname} ({ascope})", s))
    return refs


def resolve(script_path: str) -> Path | None:
    for base in SEARCH_BASES:
        p = (base / script_path).resolve()
        if p.exists():
            return p
    return None


def index_known_scripts() -> dict[str, list[Path]]:
    """basename -> [matching paths under .github/skills/*/scripts/ and scripts/]."""
    idx: dict[str, list[Path]] = {}
    for base in SEARCH_BASES:
        if not base.exists():
            continue
        for p in base.rglob("scripts/*"):
            if p.is_file():
                idx.setdefault(p.name, []).append(p)
    return idx


def to_dag_path(p: Path) -> str:
    """Express p as a DAG-relative path (preferring .github/ base)."""
    for base in SEARCH_BASES:
        try:
            return p.relative_to(base).as_posix()
        except ValueError:
            continue
    return p.as_posix()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dag", default=str(DEFAULT_DAG))
    args = parser.parse_args(argv)

    dag_path = Path(args.dag)
    try:
        dag = yaml.safe_load(dag_path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"ERROR: cannot load {dag_path}: {e}", file=sys.stderr)
        return 2

    refs = collect_script_refs(dag)
    if not refs:
        print("WARN: no `scripts:` entries found in DAG")
        return 0

    known = index_known_scripts()
    stale: list[tuple[str, str, list[Path]]] = []
    for loc, ref in refs:
        if resolve(ref) is None:
            hints = known.get(Path(ref).name, [])
            stale.append((loc, ref, hints))

    total = len(refs)
    ok = total - len(stale)
    print(f"pipeline-dag scripts: {ok}/{total} OK")
    if stale:
        print("Stale references:")
        for loc, ref, hints in stale:
            print(f"  [{loc}] {ref}")
            for h in hints:
                print(f"      did you mean: {to_dag_path(h)}")
            if not hints:
                print("      (no basename match found anywhere in repo)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
