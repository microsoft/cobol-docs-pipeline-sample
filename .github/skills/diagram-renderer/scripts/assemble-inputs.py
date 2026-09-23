#!/usr/bin/env python3
"""Deterministic prompt-bundle packager for the `diagram-renderer` skill.

For ONE source file, loads `docs/_shared/<file>/facts.json` and emits a
single JSON bundle containing ONE entry per non-empty collection that
maps to a file-level overview Mermaid diagram. Empty collections are
omitted; the agent only authors the .mmd files for collections present
in the bundle.

NO LLM CALLS. Fully deterministic.

Mapping (collection -> diagram kind / Mermaid header):
  performs        -> call-graph         (flowchart LR)
  go_tos          -> control-flow       (flowchart TD)
  jcl_steps       -> jcl-steps          (flowchart TD)
    cl_commands     -> cl-command-flow    (flowchart TD)
  exec_cics       -> cics-calls         (sequenceDiagram)
  exec_sql.cursor -> cursor-lifecycle   (stateDiagram-v2)
  data_records    -> er-fragment        (erDiagram)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SKILL_ROOT.parents[2]
DEFAULT_DOC_ROOT = REPO_ROOT / "docs" / "_shared"
SOURCES_YAML = REPO_ROOT / "config" / "pipeline.yaml"
DEFAULT_PROFILE = REPO_ROOT / "config" / "templates" / "docs" / "functional-analysis" / "default" / "profile.yaml"

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_MISSING_PREREQ = 4
EXIT_STALE = 5

DIAGRAM_SPECS: list[tuple[str, str, str, str]] = [
    # (collection_key, diagram_kind, output_basename, mermaid_header)
    ("performs", "call-graph", "call-graph.mmd", "flowchart LR"),
    ("inter_program_calls", "inter-program-call-graph", "inter-program-call-graph.mmd", "flowchart LR"),
    ("go_tos", "control-flow", "control-flow.mmd", "flowchart TD"),
    ("jcl_steps", "jcl-steps", "jcl-steps.mmd", "flowchart TD"),
    ("cl_commands", "cl-command-flow", "cl-command-flow.mmd", "flowchart TD"),
    ("exec_cics", "cics-calls", "cics-calls.mmd", "sequenceDiagram"),
    ("exec_sql", "cursor-lifecycle", "cursor-lifecycle.mmd", "stateDiagram-v2"),
    ("data_records", "er-fragment", "er-fragment.mmd", "erDiagram"),
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_sha(obj: object) -> str:
    return sha256_bytes(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def load_sources_yaml() -> dict:
    if not SOURCES_YAML.exists():
        return {}
    return yaml.safe_load(SOURCES_YAML.read_text(encoding="utf-8")) or {}


def resolve_source_root(override: str | None) -> Path:
    raw = override or load_sources_yaml().get("source_root", "./samples")
    p = Path(raw)
    return p if p.is_absolute() else (REPO_ROOT / p).resolve()


def resolve_source(source: str, source_root: Path) -> Path:
    p = Path(source)
    if p.is_absolute() and p.exists():
        return p
    for cand in [REPO_ROOT / p, source_root / p]:
        cand = cand.resolve()
        if cand.exists():
            return cand
    raise SystemExit(f"ERROR: source not found: {source}")


def filter_subset(collection_key: str, items: list[dict]) -> list[dict]:
    if collection_key == "exec_sql":
        # cursor-lifecycle covers only cursor-related stanzas.
        return [
            it for it in items
            if any(kw in (it.get("kind") or "").lower() or kw in (it.get("statement") or "").lower()
                   for kw in ("declare cursor", "open", "fetch", "close", "cursor"))
        ]
    return items


def build_inter_program_calls(facts: dict) -> list[dict]:
    """Combine outbound calls and inbound xrefs without copybook edges."""
    program_id = facts.get("program_id") or Path(facts.get("source_path") or "source").stem
    edges = [
        {
            "direction": "outbound",
            "source": program_id,
            "target": item.get("target"),
            "kind": item.get("kind") or "call",
            "line": item.get("line"),
        }
        for item in facts.get("calls") or []
    ]
    edges.extend(
        {
            "direction": "inbound",
            "source": item.get("caller_source"),
            "target": program_id,
            "kind": item.get("via") or "call",
            "line": item.get("line"),
        }
        for item in facts.get("incoming_xref") or []
        if item.get("via") != "copy"
    )
    return sorted(
        edges,
        key=lambda edge: (
            edge.get("direction") or "",
            edge.get("source") or "",
            edge.get("line") or 0,
            edge.get("target") or "",
        ),
    )


def build_diagram_entries(facts: dict, source_path: Path) -> list[dict]:
    diagrams: list[dict] = []
    paragraphs = facts.get("paragraphs") or []
    out_dir = Path("docs/_shared") / source_path.name / "diagrams"
    for key, kind, basename, header in DIAGRAM_SPECS:
        raw = build_inter_program_calls(facts) if key == "inter_program_calls" else facts.get(key) or []
        subset = filter_subset(key, raw)
        if not subset:
            continue
        facts_subset: dict[str, object] = {key: subset}
        if key in ("performs", "go_tos"):
            facts_subset["paragraphs"] = paragraphs
        diagrams.append({
            "kind": kind,
            "mermaid": header,
            "output_path": str(out_dir / basename).replace("\\", "/"),
            "facts_subset": facts_subset,
            "facts_subset_sha": canonical_json_sha(facts_subset),
            "item_count": len(subset),
        })
    return diagrams


def load_profile(path_override: str | None) -> dict:
    profile_path = Path(path_override) if path_override else DEFAULT_PROFILE
    if not profile_path.is_absolute():
        profile_path = (REPO_ROOT / profile_path).resolve()
    if not profile_path.exists():
        return {}
    return yaml.safe_load(profile_path.read_text(encoding="utf-8")) or {}


def main() -> int:
    ap = argparse.ArgumentParser(description="Package per-file diagram-renderer inputs.")
    ap.add_argument("--source", required=True)
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--profile", default=None)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    source_root = resolve_source_root(args.source_root)
    source_path = resolve_source(args.source, source_root)
    doc_dir = REPO_ROOT / "docs" / "_shared" / source_path.name
    facts_path = doc_dir / "facts.json"
    if not facts_path.exists():
        print(f"ERROR: missing facts.json — run cobol-facts-extraction first: {facts_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    facts_bytes = facts_path.read_bytes()
    facts = json.loads(facts_bytes.decode("utf-8"))
    facts_sha = sha256_bytes(facts_bytes)

    # Stale check vs the on-disk source.
    src_sha_on_disk = sha256_bytes(source_path.read_bytes())
    if facts.get("source_sha256") and facts["source_sha256"] != src_sha_on_disk:
        print(f"ERROR: facts.json is stale vs {source_path.name} — re-run phase B.", file=sys.stderr)
        return EXIT_STALE

    bundle = {
        "bundle_version": "1.0",
        "source_path": str(source_path).replace("\\", "/"),
        "source_kind": facts.get("source_kind"),
        "source_platform": facts.get("source_platform", "mainframe"),
        "program_id": facts.get("program_id"),
        "facts_sha": facts_sha,
        "manifest_sha": facts.get("manifest_sha256"),
        "diagrams": build_diagram_entries(facts, source_path),
        "profile": load_profile(args.profile),
    }

    out = json.dumps(bundle, ensure_ascii=False, indent=2)
    if args.out:
        out_path = Path(args.out)
        if not out_path.is_absolute():
            out_path = (REPO_ROOT / out_path).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(out + "\n", encoding="utf-8")
        print(f"OK: bundle written to {out_path} (diagrams={len(bundle['diagrams'])}, "
              f"facts_sha={facts_sha[:8]})")
    else:
        sys.stdout.write(out + "\n")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
