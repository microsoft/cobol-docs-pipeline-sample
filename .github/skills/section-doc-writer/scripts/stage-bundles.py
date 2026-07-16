#!/usr/bin/env python3
"""Bulk pre-stage per-chunk LLM prompt bundles for ONE source.

For each chunk in `docs/_shared/<file>/chunk-manifest.json`, invoke the
deterministic `assemble-inputs.py` packager and write
  `docs/_shared/<file>/_bundles/<chunk_id_sanitized>.bundle.json`.

This closes the prep half of phase-C end-to-end so the LLM authoring step
just needs to read one bundle per chunk and emit the MD(s). The runner is
fully deterministic — re-running on unchanged inputs is a no-op (skip when
the bundle's input hashes already match).

Exit codes:
  0  all ok
  1  one or more chunks failed to package (per-chunk stderr printed)
  4  missing prerequisite (chunk-manifest, chunks/index, facts-slices, …)
  5  stale source vs. manifest
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SKILL_ROOT.parents[2]
ASSEMBLE_PY = SKILL_ROOT / "scripts" / "assemble-inputs.py"
DOC_ROOT = REPO_ROOT / "docs" / "_shared"
SOURCES_YAML = REPO_ROOT / "config" / "sources.yaml"

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_MISSING_PREREQ = 4
EXIT_STALE = 5


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_sha(obj: object) -> str:
    return sha256_bytes(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def parse_languages(value: str) -> list[str]:
    langs = [s.strip() for s in (value or "en").split(",") if s.strip()]
    seen: list[str] = []
    for l in (["en"] + langs):
        if l not in seen:
            seen.append(l)
    return seen


def load_source_root(override: str | None) -> Path:
    cfg = yaml.safe_load(SOURCES_YAML.read_text(encoding="utf-8")) if SOURCES_YAML.exists() else {}
    raw = override or (cfg or {}).get("source_root", "./samples")
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


def main() -> int:
    ap = argparse.ArgumentParser(description="Bulk pre-stage per-chunk LLM bundles for ONE source.")
    ap.add_argument("--source", required=True)
    ap.add_argument("--languages", default="en")
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--bundles-dir", default=None,
                    help="override output directory (default: docs/_shared/<file>/_bundles).")
    ap.add_argument("--prune", action="store_true",
                    help="delete stale bundle files whose chunk_id no longer exists in the manifest.")
    ap.add_argument("--force", action="store_true",
                    help="re-stage bundles even when up-to-date.")
    args = ap.parse_args()

    if not ASSEMBLE_PY.exists():
        print(f"ERROR: cannot find assemble-inputs.py at {ASSEMBLE_PY}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    source_root = load_source_root(args.source_root)
    source_path = resolve_source(args.source, source_root)
    doc_dir = DOC_ROOT / source_path.name
    manifest_path = doc_dir / "chunk-manifest.json"
    if not manifest_path.exists():
        print(f"ERROR: missing chunk-manifest.json — run cobol-chunking first: {manifest_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    on_disk_sha = sha256_bytes(source_path.read_bytes())
    if manifest.get("sha256") != on_disk_sha:
        print(
            f"STALE: manifest sha {manifest.get('sha256','?')[:12]}… "
            f"!= source sha {on_disk_sha[:12]}… — re-run cobol-chunking",
            file=sys.stderr,
        )
        return EXIT_STALE

    idx_path = doc_dir / "chunks" / "index.json"
    if not idx_path.exists():
        print(f"ERROR: missing chunks/index.json — run chunk-text-extraction first: {idx_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    chunks_index = json.loads(idx_path.read_text(encoding="utf-8"))
    id_to_file = {c["id"]: c["file"] for c in chunks_index.get("chunks") or []}

    facts_dir = doc_dir / "facts-slices"
    if not facts_dir.exists():
        print(f"ERROR: missing facts-slices/ — run facts-slicing first: {facts_dir}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    bundles_dir = Path(args.bundles_dir) if args.bundles_dir else (doc_dir / "_bundles")
    if not bundles_dir.is_absolute():
        bundles_dir = (REPO_ROOT / bundles_dir).resolve()
    bundles_dir.mkdir(parents=True, exist_ok=True)

    chunks = manifest.get("chunks") or []
    expected_names: set[str] = set()
    ok = 0
    skipped = 0
    failed: list[tuple[str, int, str]] = []

    for chunk in sorted(chunks, key=lambda c: c.get("id", "")):
        cid = chunk.get("id")
        if not cid:
            continue
        if cid not in id_to_file:
            failed.append((cid, EXIT_MISSING_PREREQ, "chunk_id missing from chunks/index.json"))
            continue
        stem = Path(id_to_file[cid]).stem
        out_name = f"{stem}.bundle.json"
        expected_names.add(out_name)
        out_path = bundles_dir / out_name

        # Up-to-date check: hashes must match the exact ones assemble-inputs.py
        # writes — raw bytes for chunk_text, canonical-JSON for facts_slice.
        if not args.force and out_path.exists():
            try:
                existing = json.loads(out_path.read_text(encoding="utf-8"))
                slice_path = facts_dir / f"{stem}.json"
                text_path = doc_dir / "chunks" / f"{stem}.txt"
                if slice_path.exists() and text_path.exists():
                    slice_obj = json.loads(slice_path.read_text(encoding="utf-8"))
                    if (existing.get("chunk_text_sha") == sha256_bytes(text_path.read_bytes())
                            and existing.get("facts_slice_sha") == canonical_json_sha(slice_obj)
                            and existing.get("languages") == parse_languages(args.languages)):
                        skipped += 1
                        continue
            except (OSError, ValueError, json.JSONDecodeError):
                pass

        argv = [
            sys.executable, str(ASSEMBLE_PY),
            "--source", str(source_path),
            "--chunk-id", cid,
            "--languages", args.languages,
            "--source-root", str(source_root),
            "--out", str(out_path),
        ]
        res = subprocess.run(argv, capture_output=True, text=True)
        if res.returncode != 0:
            failed.append((cid, res.returncode, (res.stderr or res.stdout or "").strip()))
        else:
            ok += 1

    pruned = 0
    if args.prune:
        for f in sorted(bundles_dir.glob("*.bundle.json")):
            if f.name not in expected_names:
                f.unlink()
                pruned += 1

    total = len(chunks)
    print(f"DONE {source_path.name}: total={total} ok={ok} skipped={skipped} failed={len(failed)} pruned={pruned}  ->  {bundles_dir.relative_to(REPO_ROOT)}")
    if failed:
        for cid, code, msg in failed[:20]:
            short = (msg or "").splitlines()[-1] if msg else ""
            print(f"  [{code}] {cid}  {short}", file=sys.stderr)
        return EXIT_FAIL
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
