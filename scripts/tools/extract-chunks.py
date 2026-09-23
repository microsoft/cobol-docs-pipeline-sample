#!/usr/bin/env python3
"""Deterministic per-chunk raw-text extractor (phase-B sibling).

Reads a source file + its chunk-manifest.json and emits one .txt per chunk
under docs/_shared/<file>/chunks/<chunk_id_sanitized>.txt.

Usage:
    py -3 extract-chunks.py --source <rel-path> [--chunk-id <id>] [--prune] [--no-index]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import yaml

SCRIPT_ROOT = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_ROOT.parent.parent
DEFAULT_DOC_ROOT = REPO_ROOT / "docs" / "_shared"
SOURCES_YAML = REPO_ROOT / "config" / "pipeline.yaml"

# Exit codes (mirrors sibling skills).
EXIT_OK = 0
EXIT_USAGE = 2
EXIT_STALE = 4
EXIT_CHUNK_ID_TOO_LONG = 5

# Filesystem limit guard; Windows MAX_PATH minus directory headroom.
MAX_FILENAME = 200


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


def sanitize_chunk_id(chunk_id: str, suffix: str = "") -> str:
    name = chunk_id.replace("/", "__") + suffix + ".txt"
    if len(name) > MAX_FILENAME:
        raise SystemExit(
            f"CHUNK_ID_TOO_LONG: sanitized filename {len(name)} chars exceeds {MAX_FILENAME}: {chunk_id}"
        )
    return name


def assign_unique_filenames(chunks: list[dict]) -> tuple[dict[int, str], list[dict]]:
    """Return (index_in_list -> filename) and a list of DUPLICATE_CHUNK_ID errors.

    Phase A is supposed to guarantee unique chunk ids, but some real-world manifests
    violate that. For each collision after the first, append __L<start_line>.
    """
    seen: dict[str, int] = {}
    out: dict[int, str] = {}
    errs: list[dict] = []
    for i, c in enumerate(chunks):
        cid = c["id"]
        base = sanitize_chunk_id(cid)
        if base not in seen:
            seen[base] = 1
            out[i] = base
            continue
        seen[base] += 1
        suffix = f"__L{c.get('start_line', 'X')}"
        disambiguated = sanitize_chunk_id(cid, suffix)
        # Last-resort: if even the disambiguated name collides, append occurrence ordinal.
        if disambiguated in out.values():
            disambiguated = sanitize_chunk_id(cid, f"{suffix}_{seen[base]}")
        out[i] = disambiguated
        errs.append({
            "code": "DUPLICATE_CHUNK_ID",
            "chunk_id": cid,
            "start_line": c.get("start_line"),
            "end_line": c.get("end_line"),
            "renamed_to": disambiguated,
        })
    return out, errs


def read_source_lines(source_path: Path, encoding: str) -> list[str]:
    """Read source with universal newlines and return lines with '\\n' endings."""
    with source_path.open("r", encoding=encoding, newline=None, errors="replace") as f:
        text = f.read()
    # splitlines drops the line terminator; rebuild with LF for deterministic output.
    lines = text.split("\n")
    # If the file ended with a newline, split produces a trailing empty element. Drop it
    # so line indexing matches an editor's 1-based "last non-empty line" count.
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def slice_lines(lines: list[str], start: int, end: int) -> bytes:
    """Return bytes for inclusive 1-based [start..end], LF-joined, trailing LF."""
    if start < 1 or end < start:
        return b""
    s = max(1, start) - 1
    e = min(len(lines), end)
    if s >= len(lines):
        return b""
    payload = "\n".join(lines[s:e])
    if payload:
        payload += "\n"
    return payload.encode("utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract per-chunk raw source text.")
    ap.add_argument("--source", help="Path to the source file (repo-relative or absolute).")
    ap.add_argument("--manifest", help="Override path to chunk-manifest.json.")
    ap.add_argument("--output-dir", help="Override default docs/_shared/<file>/chunks dir.")
    ap.add_argument("--source-root", help="Override pipeline.yaml::source_root.")
    ap.add_argument("--chunk-id", help="Extract only the named chunk_id.")
    ap.add_argument("--prune", action="store_true", help="Delete .txt files for chunks no longer in the manifest.")
    ap.add_argument("--no-index", action="store_true", help="Do not write index.json.")
    args = ap.parse_args()

    if not args.source:
        print("ERROR: --source is required", file=sys.stderr)
        return EXIT_USAGE

    # Resolve source.
    try:
        source_path = resolve_source(args.source, args.source_root)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_USAGE

    # Resolve manifest.
    doc_dir = default_doc_dir_for(source_path)
    manifest_path = Path(args.manifest) if args.manifest else doc_dir / "chunk-manifest.json"
    if not manifest_path.exists():
        print(f"ERROR: chunk-manifest.json not found at {manifest_path}", file=sys.stderr)
        return EXIT_USAGE

    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes.decode("utf-8"))
    manifest_sha = sha256_bytes(manifest_bytes)

    # Stale-input check: manifest's sha256 must match source on disk.
    source_bytes = source_path.read_bytes()
    source_sha = sha256_bytes(source_bytes)
    declared = manifest.get("sha256")
    if declared and declared != source_sha:
        print(
            f"ERROR: STALE manifest — manifest.sha256={declared[:12]}... but source on disk hashes to "
            f"{source_sha[:12]}.... Re-run cobol-chunking.",
            file=sys.stderr,
        )
        return EXIT_STALE

    encoding = manifest.get("encoding_detected") or "utf-8"
    chunks = manifest.get("chunks") or []

    # Optional filter to one chunk.
    if args.chunk_id:
        chunks = [c for c in chunks if c.get("id") == args.chunk_id]
        if not chunks:
            print(f"ERROR: chunk_id not in manifest: {args.chunk_id}", file=sys.stderr)
            return EXIT_USAGE

    # Output directory.
    out_dir = Path(args.output_dir) if args.output_dir else doc_dir / "chunks"
    out_dir.mkdir(parents=True, exist_ok=True)

    lines = read_source_lines(source_path, encoding)

    fname_by_index, dup_errors = assign_unique_filenames(chunks)
    errors: list[dict] = list(dup_errors)
    index_entries: list[dict] = []
    written = 0

    for i, chunk in enumerate(chunks):
        cid = chunk["id"]
        start = int(chunk.get("start_line") or 0)
        end = int(chunk.get("end_line") or 0)
        fname = fname_by_index[i]
        payload = slice_lines(lines, start, end)
        if not payload:
            errors.append({"code": "EMPTY_CHUNK", "chunk_id": cid, "start_line": start, "end_line": end})
        out_path = out_dir / fname
        out_path.write_bytes(payload)
        written += 1
        index_entries.append({
            "id": cid,
            "file": fname,
            "start_line": start,
            "end_line": end,
            "line_count": (end - start + 1) if end >= start else 0,
            "byte_count": len(payload),
            "sha256": sha256_bytes(payload),
        })

    # Optional prune.
    pruned = 0
    if args.prune:
        all_chunks = manifest.get("chunks") or []
        keep_map, _ = assign_unique_filenames(all_chunks)
        keep = set(keep_map.values())
        for existing in out_dir.glob("*.txt"):
            if existing.name not in keep:
                existing.unlink()
                pruned += 1

    # Index file.
    if not args.no_index:
        # Always re-emit the FULL index based on the manifest (not just the filtered chunks)
        # unless the user is doing a single-chunk extraction, in which case --no-index is the
        # right call. Here we honor the filter to keep semantics simple.
        index = {
            "index_version": "1.0",
            "source_path": manifest.get("source_path") or args.source,
            "source_sha256": source_sha,
            "manifest_sha256": manifest_sha,
            "encoding": encoding,
            "chunks": sorted(index_entries, key=lambda e: (e["start_line"], e["id"])),
            "errors": errors,
        }
        index_path = out_dir / "index.json"
        index_path.write_text(
            json.dumps(index, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
            encoding="utf-8",
        )

    print(
        f"OK: wrote {written} chunk(s) to {out_dir} "
        f"(pruned={pruned}, errors={len(errors)}, "
        f"source_sha={source_sha[:8]}, manifest_sha={manifest_sha[:8]})"
    )
    for err in errors:
        print(f"  WARN {err['code']}: {err.get('chunk_id')} [{err.get('start_line')}-{err.get('end_line')}]")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
