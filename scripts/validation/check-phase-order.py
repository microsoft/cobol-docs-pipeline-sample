#!/usr/bin/env python3
"""Assert the orchestrator's phase order reconciles with config/pipeline-dag.yaml.

The orchestrator (scripts/run-pipeline.ps1) discovers its phase order from
scripts/lib/Resolve-PhaseInputs.ps1::$PhaseScriptMap. The DAG uses COARSER phase
ids than the orchestrator: a single DAG phase can be realised by several runner
phases (e.g. DAG "C" = section docs + finalizer + diagrams, run by runner
D + E + H). The `DAG_TO_ORCH` table below is the authoritative reconciliation.

This checker verifies (strictly, no tolerant subsequence):
  1. Every DAG phase id is mapped, and every mapping key is a real DAG phase.
  2. Every mapped runner id exists in $PhaseScriptMap, and every runner phase is
     covered by exactly one DAG phase (no orphan, no duplicate).
  3. DAG phases begin in DAG order in the orchestrator (tolerates the legitimate
     interleave, e.g. runner H running after F/G, without demanding contiguity).

Exit 0 on success, 2 on drift, 1 on usage/IO errors.
"""
from __future__ import annotations
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
YAML = REPO / "config" / "pipeline-dag.yaml"
LIB  = REPO / "scripts" / "lib" / "Resolve-PhaseInputs.ps1"

# Authoritative reconciliation between the DAG's coarse phase ids and the
# orchestrator's finer-grained per-source phase scripts. Keep this in lock-step
# with BOTH config/pipeline-dag.yaml `phases[].id` AND $PhaseScriptMap in
# scripts/lib/Resolve-PhaseInputs.ps1.
DAG_TO_ORCH: dict[str, list[str]] = {
    "A": ["A"],            # chunking
    "B": ["B", "C"],       # facts extraction + chunk-text extraction
    "C": ["D", "E", "H"],  # section docs + finalizer + file-level diagrams
    "F": ["F"],            # technical requirements
    "G": ["G"],            # functional analysis
    "I": ["I"],            # group docs
    "J": ["J"],            # group requirements
    "K": ["K"],            # group functional analysis
    "L": ["L"],            # technical analysis
    "M": ["M"],            # group technical analysis
    "N": ["N"],            # documentation portal
}


def read_yaml_phase_ids(path: pathlib.Path) -> list[str]:
    ids: list[str] = []
    in_phases = False
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.lstrip()
        # Track entry into the top-level `phases:` block.
        if stripped.startswith("phases:") and not line.startswith(" "):
            in_phases = True
            continue
        if in_phases and line and not line.startswith((" ", "\t", "#")):
            # New top-level key ends the phases block.
            in_phases = False
        if not in_phases:
            continue
        m = re.match(r"^\s*-\s*id:\s*([A-Za-z0-9_-]+)\s*$", line)
        if m:
            ids.append(m.group(1))
    return ids


def read_orchestrator_phase_ids(path: pathlib.Path) -> list[str]:
    # Parse the [ordered]@{} block defining $script:PhaseScriptMap.
    text = path.read_text(encoding="utf-8")
    m = re.search(
        r"\$script:PhaseScriptMap\s*=\s*\[ordered\]@\{(.*?)\}",
        text,
        flags=re.DOTALL,
    )
    if not m:
        print("ERROR: could not locate $script:PhaseScriptMap in", path, file=sys.stderr)
        sys.exit(1)
    body = m.group(1)
    return re.findall(r"^\s*([A-Za-z0-9_-]+)\s*=", body, flags=re.MULTILINE)


def main() -> int:
    if not YAML.exists():
        print(f"ERROR: missing {YAML}", file=sys.stderr); return 1
    if not LIB.exists():
        print(f"ERROR: missing {LIB}", file=sys.stderr); return 1

    yaml_ids   = read_yaml_phase_ids(YAML)
    script_ids = read_orchestrator_phase_ids(LIB)

    print(f"pipeline-dag.yaml phases : {yaml_ids}")
    print(f"orchestrator    phases : {script_ids}")

    problems: list[str] = []

    # 1. Every DAG phase must be mapped; every mapping key must be a real phase.
    for pid in yaml_ids:
        if pid not in DAG_TO_ORCH:
            problems.append(f"DAG phase '{pid}' has no entry in DAG_TO_ORCH mapping")
    for pid in DAG_TO_ORCH:
        if pid not in yaml_ids:
            problems.append(f"DAG_TO_ORCH maps '{pid}' but it is not a declared DAG phase")

    # 2. Every mapped runner id must exist; every runner phase covered once.
    mapped = [oid for pid in yaml_ids if pid in DAG_TO_ORCH for oid in DAG_TO_ORCH[pid]]
    for oid in mapped:
        if oid not in script_ids:
            problems.append(f"mapping references orchestrator phase '{oid}' not in $PhaseScriptMap")
    seen: dict[str, int] = {}
    for oid in mapped:
        seen[oid] = seen.get(oid, 0) + 1
    for oid, n in seen.items():
        if n > 1:
            problems.append(f"orchestrator phase '{oid}' is mapped {n} times (must be exactly once)")
    for oid in script_ids:
        if oid not in seen:
            problems.append(f"orchestrator phase '{oid}' is not covered by any DAG phase mapping")

    # 3. DAG phases must *begin* in DAG order in the orchestrator sequence.
    idx = {oid: i for i, oid in enumerate(script_ids)}
    first_indices: list[tuple[str, int]] = []
    for pid in yaml_ids:
        positions = [idx[o] for o in DAG_TO_ORCH.get(pid, []) if o in idx]
        if positions:
            first_indices.append((pid, min(positions)))
    for (p_prev, i_prev), (p_cur, i_cur) in zip(first_indices, first_indices[1:]):
        if i_cur <= i_prev:
            problems.append(
                f"DAG phase '{p_cur}' starts at orchestrator index {i_cur} which is not "
                f"after '{p_prev}' (index {i_prev}) - DAG/orchestrator order drift"
            )

    if problems:
        print("DRIFT: DAG <-> orchestrator reconciliation failed:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 2

    print("OK: DAG phases reconcile 1:1 with orchestrator phases:")
    for pid in yaml_ids:
        print(f"    {pid} -> {DAG_TO_ORCH[pid]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
