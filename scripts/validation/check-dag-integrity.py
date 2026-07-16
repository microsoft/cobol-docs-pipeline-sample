#!/usr/bin/env python3
"""Validate the structural integrity of config/pipeline-dag.yaml.

JSON Schema (config/pipeline-dag.schema.json) can regex-check each `depends_on`
entry but cannot verify that the id actually resolves to a declared phase, nor
that the resulting graph is acyclic. This checker closes that gap:

  1. Every `depends_on` id MUST reference a phase declared in `phases[]`.
  2. No phase may depend on itself.
  3. The `depends_on` graph MUST be acyclic (a topological order must exist).

Exit codes:
  0  graph is well-formed
  2  one or more integrity problems (dangling ref, self-dep, or cycle)
  1  pipeline-dag.yaml could not be loaded

Usage:
    python scripts/validation/check-dag-integrity.py
    python scripts/validation/check-dag-integrity.py --dag path/to/pipeline-dag.yaml
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DAG = REPO_ROOT / "config" / "pipeline-dag.yaml"


def load_phases(dag: dict) -> list[dict]:
    return [p for p in (dag.get("phases") or []) if isinstance(p, dict)]


def check_phase_ids(phases: list[dict]) -> list[str]:
    """Every phase must have a unique, non-empty string id."""
    problems: list[str] = []
    seen: set[str] = set()
    for index, phase in enumerate(phases):
        phase_id = phase.get("id")
        if not isinstance(phase_id, str) or not phase_id:
            problems.append(f"phase at index {index}: missing or invalid id")
        elif phase_id in seen:
            problems.append(f"duplicate phase id: {phase_id}")
        else:
            seen.add(phase_id)
    return problems


def check_references(phases: list[dict]) -> list[str]:
    """Every depends_on id must be a declared phase; no self-dependency."""
    ids = {p.get("id") for p in phases}
    problems: list[str] = []
    for p in phases:
        pid = p.get("id", "?")
        for dep in p.get("depends_on", []) or []:
            if dep == pid:
                problems.append(f"phase {pid}: depends on itself")
            elif dep not in ids:
                problems.append(
                    f"phase {pid}: depends_on '{dep}' which is not a declared phase id"
                )
    return problems


def find_cycle(phases: list[dict]) -> list[str] | None:
    """Return a cycle as a list of ids if the graph is cyclic, else None.

    Edges point from a phase to each of its dependencies. Only edges whose
    target is a declared phase are followed (dangling refs are reported
    separately by check_references and ignored here).
    """
    ids = {p.get("id") for p in phases}
    graph = {
        p.get("id"): [d for d in (p.get("depends_on", []) or []) if d in ids]
        for p in phases
    }
    WHITE, GREY, BLACK = 0, 1, 2
    color = {pid: WHITE for pid in graph}
    stack: list[str] = []

    def dfs(node: str) -> list[str] | None:
        color[node] = GREY
        stack.append(node)
        for nxt in graph.get(node, []):
            if color[nxt] == GREY:
                # Back-edge: extract the cycle from the current stack.
                return stack[stack.index(nxt):] + [nxt]
            if color[nxt] == WHITE:
                found = dfs(nxt)
                if found:
                    return found
        color[node] = BLACK
        stack.pop()
        return None

    for pid in graph:
        if color[pid] == WHITE:
            cycle = dfs(pid)
            if cycle:
                return cycle
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dag", default=str(DEFAULT_DAG))
    args = parser.parse_args(argv)

    dag_path = Path(args.dag)
    try:
        dag = yaml.safe_load(dag_path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"ERROR: cannot load {dag_path}: {e}", file=sys.stderr)
        return 1

    if not isinstance(dag, dict):
        print(
            f"ERROR: {dag_path} must contain a YAML mapping at the document root",
            file=sys.stderr,
        )
        return 1

    phases = load_phases(dag)
    if not phases:
        print("ERROR: no phases[] found in DAG", file=sys.stderr)
        return 1

    ids = [p.get("id") for p in phases]
    print(f"pipeline-dag phases: {ids}")

    problems = check_phase_ids(phases)
    if not problems:
        problems.extend(check_references(phases))
        cycle = find_cycle(phases)
        if cycle:
            problems.append("cycle detected: " + " -> ".join(cycle))

    if problems:
        print("DAG integrity problems:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 2

    print(f"OK: {len(phases)} phases, depends_on graph is acyclic and fully resolved.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
