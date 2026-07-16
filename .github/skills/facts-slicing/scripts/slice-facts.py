#!/usr/bin/env python3
"""Deterministic per-chunk facts slicer (phase-C prep step).

Reads a per-file facts.json + its chunk-manifest.json and emits one slice
per chunk under docs/_shared/<file>/facts-slices/<chunk_id>.json.

Usage:
    py -3 slice-facts.py --source <rel-path> [--chunk-id <id>] [--prune]
    py -3 slice-facts.py --facts <facts.json> --manifest <chunk-manifest.json>
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = SKILL_ROOT.parent.parent.parent
SCHEMA_PATH = SKILL_ROOT / "schemas" / "outputs.schema.json"
DEFAULT_DOC_ROOT = REPO_ROOT / "docs" / "_shared"
SOURCES_YAML = REPO_ROOT / "config" / "sources.yaml"

# Cross-cutting collections that are NEVER chunk-filtered.
FULL_COLLECTIONS = ("files", "incoming_xref")
# Collections filtered by chunk_id ∈ {this} ∪ descendants.
CHUNK_FILTERED = (
    "paragraphs", "performs", "go_tos", "calls", "copybooks",
    "exec_sql", "exec_cics", "data_records", "jcl_steps", "cl_commands", "bms_maps",
)


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def load_sources_yaml() -> dict:
    if not SOURCES_YAML.exists():
        return {}
    with SOURCES_YAML.open("rb") as f:
        return yaml.safe_load(f) or {}


def resolve_source(source: str, source_root: str | None) -> Path:
    p = Path(source)
    if p.is_absolute() and p.exists():
        return p
    cand = (REPO_ROOT / source).resolve()
    if cand.exists():
        return cand
    root = source_root or load_sources_yaml().get("source_root")
    if root:
        cand = (REPO_ROOT / root / source).resolve()
        if cand.exists():
            return cand
    raise FileNotFoundError(f"source not found: {source}")


def default_doc_dir_for(source_path: Path) -> Path:
    return DEFAULT_DOC_ROOT / source_path.name


def sanitize_chunk_id(chunk_id: str) -> str:
    return chunk_id.replace("/", "__")


def build_descendants(chunks: list[dict]) -> dict[str, set[str]]:
    """Map chunk_id -> set of descendant chunk_ids (transitive children)."""
    children: dict[str, list[str]] = {}
    for c in chunks:
        parent = c.get("parent_id")
        if parent is not None:
            children.setdefault(parent, []).append(c["id"])
    cache: dict[str, set[str]] = {}

    def descend(cid: str) -> set[str]:
        if cid in cache:
            return cache[cid]
        out: set[str] = set()
        for child in children.get(cid, []):
            out.add(child)
            out |= descend(child)
        cache[cid] = out
        return out

    return {c["id"]: descend(c["id"]) for c in chunks}


def load_schema() -> dict | None:
    try:
        import jsonschema  # noqa: F401
    except ImportError:
        return None
    with SCHEMA_PATH.open("rb") as f:
        return json.loads(f.read().decode("utf-8"))


def slice_one(
    chunk: dict,
    facts: dict,
    descendants: set[str],
    siblings: list[dict],
    facts_sha: str,
) -> dict:
    scope = {chunk["id"]} | descendants

    def filt(items: list[dict]) -> list[dict]:
        return [it for it in items if it.get("chunk_id") in scope]

    return {
        "slice_version":     "1.0",
        "source_path":       facts["source_path"],
        "source_kind":       facts["source_kind"],
        "source_platform":   facts.get("source_platform", "mainframe"),
        "program_id":        facts.get("program_id"),
        "source_sha256":     facts["source_sha256"],
        "manifest_sha256":   facts["manifest_sha256"],
        "facts_sha256":      facts_sha,
        "chunk": {
            "id":         chunk["id"],
            "kind":       chunk["kind"],
            "name":       chunk["name"],
            "parent_id":  chunk.get("parent_id"),
            "start_line": chunk["start_line"],
            "end_line":   chunk["end_line"],
        },
        "descendant_chunk_ids": sorted(descendants),
        "paragraphs":   filt(facts.get("paragraphs", [])),
        "performs":     filt(facts.get("performs", [])),
        "go_tos":       filt(facts.get("go_tos", [])),
        "calls":        filt(facts.get("calls", [])),
        "copybooks":    filt(facts.get("copybooks", [])),
        "exec_sql":     filt(facts.get("exec_sql", [])),
        "exec_cics":    filt(facts.get("exec_cics", [])),
        "data_records": filt(facts.get("data_records", [])),
        "jcl_steps":    filt(facts.get("jcl_steps", [])),
        "cl_commands":  filt(facts.get("cl_commands", [])),
        "bms_maps":     filt(facts.get("bms_maps", [])),
        "files":        list(facts.get("files", [])),
        "incoming_xref":list(facts.get("incoming_xref", [])),
        "siblings":     siblings,
        "errors":       [],
    }


def write_slice(out_dir: Path, chunk_id: str, payload: dict) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    fname = sanitize_chunk_id(chunk_id) + ".json"
    if len(fname) > 240:
        raise ValueError(f"CHUNK_ID_TOO_LONG: {chunk_id!r} -> {len(fname)} chars")
    path = out_dir / fname
    text = json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=False)
    path.write_text(text + "\n", encoding="utf-8")
    return path


def prune_stale(out_dir: Path, keep_ids: set[str]) -> int:
    if not out_dir.exists():
        return 0
    keep = {sanitize_chunk_id(c) + ".json" for c in keep_ids}
    removed = 0
    for p in sorted(out_dir.glob("*.json")):
        if p.name not in keep:
            p.unlink()
            removed += 1
    return removed


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Facts slicer (phase C prep).")
    p.add_argument("--source")
    p.add_argument("--facts")
    p.add_argument("--manifest")
    p.add_argument("--output-dir", dest="output_dir")
    p.add_argument("--source-root", dest="source_root")
    p.add_argument("--chunk-id", dest="chunk_id")
    p.add_argument("--all", action="store_true", default=False)
    p.add_argument("--prune", action="store_true", default=False)
    args = p.parse_args(argv)

    if args.source:
        source_path = resolve_source(args.source, args.source_root)
        doc_dir = default_doc_dir_for(source_path)
    elif args.facts:
        facts_path = Path(args.facts)
        if not facts_path.is_absolute():
            facts_path = (REPO_ROOT / facts_path).resolve()
        doc_dir = facts_path.parent
    else:
        p.error("--source or --facts is required")

    facts_path = Path(args.facts) if args.facts else doc_dir / "facts.json"
    manifest_path = Path(args.manifest) if args.manifest else doc_dir / "chunk-manifest.json"
    output_dir = Path(args.output_dir) if args.output_dir else doc_dir / "facts-slices"

    if not facts_path.exists():
        print(f"ERROR: facts.json not found: {facts_path}", file=sys.stderr)
        return 2
    if not manifest_path.exists():
        print(f"ERROR: chunk-manifest.json not found: {manifest_path}", file=sys.stderr)
        return 2

    facts_bytes = facts_path.read_bytes()
    facts = json.loads(facts_bytes.decode("utf-8"))
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes.decode("utf-8"))

    on_disk_manifest_sha = sha256_bytes(manifest_bytes)
    if facts.get("manifest_sha256") != on_disk_manifest_sha:
        print(
            f"ERROR: stale manifest — facts.json::manifest_sha256={facts.get('manifest_sha256')[:8]} "
            f"!= on-disk manifest sha={on_disk_manifest_sha[:8]}. Re-run cobol-facts-extraction.",
            file=sys.stderr,
        )
        return 4

    facts_sha = sha256_bytes(facts_bytes)
    chunks = manifest.get("chunks", [])
    by_id = {c["id"]: c for c in chunks}
    descendants_by_id = build_descendants(chunks)
    # siblings: same parent_id, sorted by start_line, exclude self
    by_parent: dict[str | None, list[dict]] = {}
    for c in chunks:
        by_parent.setdefault(c.get("parent_id"), []).append(c)
    for v in by_parent.values():
        v.sort(key=lambda c: (c["start_line"], c["id"]))

    if args.chunk_id:
        if args.chunk_id not in by_id:
            print(f"ERROR: --chunk-id {args.chunk_id!r} not in manifest", file=sys.stderr)
            return 2
        target_chunks = [by_id[args.chunk_id]]
    else:
        target_chunks = chunks

    schema = load_schema()
    try:
        import jsonschema  # type: ignore
    except ImportError:
        jsonschema = None  # type: ignore[assignment]

    written = 0
    skipped = 0
    for chunk in target_chunks:
        siblings = [
            {"id": s["id"], "kind": s["kind"], "name": s["name"]}
            for s in by_parent.get(chunk.get("parent_id"), [])
            if s["id"] != chunk["id"]
        ]
        payload = slice_one(
            chunk=chunk,
            facts=facts,
            descendants=descendants_by_id[chunk["id"]],
            siblings=siblings,
            facts_sha=facts_sha,
        )
        if schema is not None and jsonschema is not None:
            try:
                jsonschema.validate(payload, schema)
            except Exception as e:
                print(f"WARN: schema validation failed for {chunk['id']}: {e}", file=sys.stderr)
                skipped += 1
                continue
        try:
            write_slice(output_dir, chunk["id"], payload)
        except ValueError as e:
            print(f"WARN: {e}", file=sys.stderr)
            skipped += 1
            continue
        written += 1

    pruned = 0
    if args.prune and not args.chunk_id:
        pruned = prune_stale(output_dir, {c["id"] for c in chunks})

    print(f"OK: wrote {written} slices to {output_dir}")
    print(
        f"  src_sha={facts['source_sha256'][:8]} man_sha={facts['manifest_sha256'][:8]} "
        f"facts_sha={facts_sha[:8]} skipped={skipped} pruned={pruned}"
    )
    return 0 if skipped == 0 else 3


if __name__ == "__main__":
    sys.exit(main())
