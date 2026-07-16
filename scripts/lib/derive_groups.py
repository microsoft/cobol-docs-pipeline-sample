#!/usr/bin/env python3
"""Derive an effective grouping manifest for group-based phases.

If config/grouping.yaml declares usable groups, the manifest is returned as-is.
Otherwise the helper scans docs/_shared/**/facts.json and builds groups from
source connectivity, then writes a synthetic grouping.yaml-compatible manifest
to the requested output path.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict, deque
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
ALLOWED_XREF_VIA = {
    "call", "cics-link", "cics-xctl", "jcl-step", "copy",
    "cl-call", "cl-callprc", "cl-submit-job",
}


def normalize_path(value: object) -> str:
    return str(value or "").replace("\\", "/").strip()


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "group"


def load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def sanitize_explicit_groups(data: dict) -> list[dict]:
    groups: list[dict] = []
    for raw_group in data.get("groups") or []:
        gid = normalize_path(raw_group.get("id"))
        members = [normalize_path(member) for member in (raw_group.get("members") or []) if normalize_path(member)]
        if not gid or not members:
            continue
        groups.append({
            "id": gid,
            "description": normalize_path(raw_group.get("description")),
            "members": members,
        })
    return groups


def load_facts(repo_root: Path) -> dict[str, dict]:
    facts_by_source: dict[str, dict] = {}
    docs_root = repo_root / "docs" / "_shared"
    if not docs_root.exists():
        return facts_by_source

    for facts_path in sorted(docs_root.glob("*/facts.json")):
        try:
            data = json.loads(facts_path.read_text(encoding="utf-8"))
        except Exception:
            continue
        source_path = normalize_path(data.get("source_path"))
        if not source_path:
            continue
        facts_by_source[source_path] = data
    return facts_by_source


def build_graph(facts_by_source: dict[str, dict]) -> dict[str, set[str]]:
    adjacency: dict[str, set[str]] = defaultdict(set)
    nodes = sorted(facts_by_source.keys())

    by_program: dict[str, str] = {}
    by_basename: dict[str, str] = {}
    for source_path, facts in facts_by_source.items():
        basename = Path(source_path).name.upper()
        by_basename[basename] = source_path
        program_id = normalize_path(facts.get("program_id")).upper()
        if program_id:
            by_program[program_id] = source_path

    def link(left: str, right: str) -> None:
        if left == right:
            return
        if left in facts_by_source and right in facts_by_source:
            adjacency[left].add(right)
            adjacency[right].add(left)

    for source_path, facts in facts_by_source.items():
        for xref in facts.get("incoming_xref") or []:
            caller = normalize_path(xref.get("caller_source"))
            via = normalize_path(xref.get("via"))
            if not caller or caller == source_path:
                continue
            if via and via not in ALLOWED_XREF_VIA:
                continue
            link(source_path, caller)

        for call in facts.get("calls") or []:
            target = normalize_path(call.get("target_source") or call.get("target"))
            if not target or target == source_path:
                continue
            if target in facts_by_source:
                link(source_path, target)
                continue
            target_key = target.upper().rsplit("/", 1)[-1]
            link(source_path, by_program.get(target_key) or by_basename.get(target_key))

        for step in facts.get("jcl_steps") or []:
            resolved = normalize_path(step.get("resolved_source"))
            if resolved:
                link(source_path, resolved)

            program = normalize_path(step.get("program")).upper()
            proc = normalize_path(step.get("proc")).upper()
            target_key = program or proc
            if target_key:
                link(source_path, by_program.get(target_key) or by_basename.get(target_key))

    return {node: adjacency.get(node, set()) for node in nodes}


def connected_components(graph: dict[str, set[str]]) -> list[list[str]]:
    seen: set[str] = set()
    components: list[list[str]] = []

    for node in sorted(graph.keys()):
        if node in seen:
            continue

        queue = deque([node])
        component: list[str] = []
        while queue:
            current = queue.popleft()
            if current in seen:
                continue
            seen.add(current)
            component.append(current)
            for neighbor in sorted(graph.get(current, set())):
                if neighbor not in seen:
                    queue.append(neighbor)

        components.append(sorted(component))

    return components


def derive_groups(facts_by_source: dict[str, dict]) -> list[dict]:
    if not facts_by_source:
        return []

    graph = build_graph(facts_by_source)
    components = connected_components(graph)
    groups: list[dict] = []
    used_ids: set[str] = set()

    for component in components:
        if not component:
            continue
        if len(components) == 1:
            gid = "all-connected-sources"
        else:
            gid = f"xref-{slugify(Path(component[0]).stem)}"

        base_gid = gid
        suffix = 2
        while gid in used_ids:
            gid = f"{base_gid}-{suffix}"
            suffix += 1
        used_ids.add(gid)

        groups.append({
            "id": gid,
            "description": f"Auto-derived group from xref-connected component ({len(component)} source(s))",
            "members": component,
        })

    return groups


def write_manifest(path: Path, groups: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = yaml.safe_dump({"groups": groups}, sort_keys=False, allow_unicode=True)
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Derive an effective grouping manifest.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve()
    manifest_path = Path(args.manifest)
    if not manifest_path.is_absolute():
        manifest_path = (repo_root / manifest_path).resolve()
    if not manifest_path.is_file():
        print(f"ERROR: grouping manifest not found: {manifest_path}", file=sys.stderr)
        return 2

    data = load_yaml(manifest_path)
    explicit_groups = sanitize_explicit_groups(data)
    if explicit_groups:
        print(json.dumps({
            "effective_manifest": str(manifest_path),
            "derived": False,
            "group_count": len(explicit_groups),
            "groups": explicit_groups,
        }))
        return 0

    facts_by_source = load_facts(repo_root)
    derived_groups = derive_groups(facts_by_source)

    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = (repo_root / out_path).resolve()
    write_manifest(out_path, derived_groups)

    print(json.dumps({
        "effective_manifest": str(out_path),
        "derived": True,
        "group_count": len(derived_groups),
        "groups": derived_groups,
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())