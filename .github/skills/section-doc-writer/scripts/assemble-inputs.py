#!/usr/bin/env python3
"""Deterministic prompt-bundle packager for the `section-doc-writer` skill.

Loads, for one chunk of one source file:
  - the chunk record from `docs/_shared/<file>/chunk-manifest.json`
  - the raw chunk text from `docs/_shared/<file>/chunks/<chunk_id>.txt`
  - the facts slice from `docs/_shared/<file>/facts-slices/<chunk_id>.json`
  - the kind-matching template under `config/templates/`
  - the active profile.yaml (thresholds, identifier regex, citation policy)

Emits a single JSON object on stdout (or via --out) that the
`section-doc-writer` agent feeds to its LLM call.

NO LLM CALLS. Fully deterministic.
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
DEFAULT_PROFILE = REPO_ROOT / "config" / "templates" / "section-doc.profile.yaml"
TEMPLATES_ROOT = REPO_ROOT / "config" / "templates"
GLOSSARY_PATH = REPO_ROOT / "docs" / "_glossary.md"

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_MISSING_PREREQ = 4
EXIT_STALE = 5

# Chunk kind -> template basename under config/templates/.
TEMPLATE_BY_KIND: dict[str, str] = {
    "paragraph": "procedure-section-doc.template.md",
    "section": "procedure-section-doc.template.md",
    "exec-sql": "procedure-section-doc.template.md",
    "exec-cics": "procedure-section-doc.template.md",
    "data-record": "data-record.template.md",
    "copybook-record": "copybook.template.md",
    "jcl-job": "jcl-job.template.md",
    "jcl-step": "jcl-step.template.md",
    "jcl-proc": "jcl-job.template.md",
    "bms-mapset": "procedure-section-doc.template.md",
    "bms-map": "procedure-section-doc.template.md",
    "bms-field": "procedure-section-doc.template.md",
    # division kinds resolved separately in `pick_template`.
}

# Diagram-kind heuristic from pipeline-dag.yaml phase C.
# Copybook chunks use `flowchart LR` because the per-chunk `.mmd` sidecar
# carries the INCLUSION GRAPH (fan-in of including programs, optionally
# grouped by REPLACING variant) — see copybook.template.md "DIAGRAM
# OWNERSHIP". The structure / ER fragment for a copybook is owned by
# `diagram-renderer` at the file-level path
# `docs/_shared/<copybook>/diagrams/er-fragment.mmd` and is embedded
# verbatim by the markdown; it is NOT written to the per-chunk sidecar.
DIAGRAM_KIND_BY_KIND: dict[str, str] = {
    "exec-cics": "sequenceDiagram",
    "data-record": "erDiagram",
    "copybook-record": "flowchart LR",
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_sha(obj: object) -> str:
    return sha256_bytes(json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))


def load_sources_yaml() -> dict:
    if not SOURCES_YAML.exists():
        return {}
    return yaml.safe_load(SOURCES_YAML.read_text(encoding="utf-8")) or {}


def resolve_source(source: str, source_root: Path) -> Path:
    p = Path(source)
    if p.is_absolute() and p.exists():
        return p
    cand_repo = (REPO_ROOT / p).resolve()
    if cand_repo.exists():
        return cand_repo
    cand_root = (source_root / p).resolve()
    if cand_root.exists():
        return cand_root
    raise SystemExit(f"ERROR: source not found: {source}")


def default_doc_dir_for(source_path: Path) -> Path:
    return DEFAULT_DOC_ROOT / source_path.name


def pick_template(chunk: dict, override: str | None) -> Path:
    if override:
        p = Path(override)
        if not p.is_absolute():
            p = (REPO_ROOT / p).resolve()
        return p
    kind = chunk.get("kind", "")
    if kind == "division":
        # Disambiguate by chunk id segment.
        cid = chunk.get("id", "").lower()
        if "procedure-division" in cid:
            return TEMPLATES_ROOT / "procedure-division.template.md"
        if "data-division" in cid:
            return TEMPLATES_ROOT / "data-division.template.md"
        if "identification-division" in cid:
            return TEMPLATES_ROOT / "identification-division.template.md"
        if "environment-division" in cid:
            return TEMPLATES_ROOT / "environment-division.template.md"
        return TEMPLATES_ROOT / "procedure-division.template.md"
    name = TEMPLATE_BY_KIND.get(kind)
    if not name:
        raise SystemExit(f"ERROR: no template registered for chunk kind: {kind!r}")
    return TEMPLATES_ROOT / name


def pick_diagram_kind(chunk: dict) -> str:
    return DIAGRAM_KIND_BY_KIND.get(chunk.get("kind", ""), "flowchart TD")


def find_chunk(manifest: dict, chunk_id: str) -> dict:
    for c in manifest.get("chunks") or []:
        if c.get("id") == chunk_id:
            return c
    raise SystemExit(f"ERROR: chunk_id not found in manifest: {chunk_id!r}")


def find_chunk_filename(chunks_index: dict, chunk_id: str) -> str:
    """Look up the sanitized filename via chunks/index.json (authoritative)."""
    for c in chunks_index.get("chunks") or []:
        if c.get("id") == chunk_id:
            return c["file"]
    raise SystemExit(f"ERROR: chunk_id not found in chunks/index.json: {chunk_id!r}")


def parse_languages(value: str) -> list[str]:
    parts = [p.strip().lower() for p in (value or "en").split(",") if p.strip()]
    return list(dict.fromkeys(parts))


def build_glossary_info() -> dict:
    rel = str(GLOSSARY_PATH.relative_to(REPO_ROOT)).replace("\\", "/")
    if not GLOSSARY_PATH.exists():
        return {
            "path": rel,
            "exists": False,
            "sha256": None,
            "entry_count": 0,
        }
    text = GLOSSARY_PATH.read_text(encoding="utf-8", errors="replace")
    entry_count = 0
    for line in text.splitlines():
        if line.startswith("| `"):
            entry_count += 1
    return {
        "path": rel,
        "exists": True,
        "sha256": sha256_bytes(text.encode("utf-8")),
        "entry_count": entry_count,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Package phase-C section-doc inputs into a deterministic JSON bundle.")
    ap.add_argument("--source", required=True)
    ap.add_argument("--chunk-id", required=True)
    ap.add_argument("--languages", default="en", help="exact comma-separated output languages; default: en")
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--manifest", default=None)
    ap.add_argument("--profile", default=None)
    ap.add_argument("--template", default=None)
    ap.add_argument("--out", default=None, help="write bundle to file (default: stdout)")
    ap.add_argument(
        "--no-md-view",
        action="store_true",
        help="suppress the sibling .md view emitted next to --out (the JSON remains authoritative either way)",
    )
    args = ap.parse_args()

    cfg = load_sources_yaml()
    source_root = Path(args.source_root or cfg.get("source_root", "./samples"))
    if not source_root.is_absolute():
        source_root = (REPO_ROOT / source_root).resolve()

    source_path = resolve_source(args.source, source_root)
    doc_dir = default_doc_dir_for(source_path)
    manifest_path = Path(args.manifest) if args.manifest else (doc_dir / "chunk-manifest.json")
    if not manifest_path.exists():
        print(f"ERROR: missing chunk-manifest.json — re-run cobol-chunking: {manifest_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes.decode("utf-8"))
    on_disk_sha = sha256_bytes(source_path.read_bytes())
    if manifest.get("sha256") != on_disk_sha:
        print(
            f"STALE: chunk-manifest.json sha {manifest.get('sha256','?')[:12]}… "
            f"!= source sha {on_disk_sha[:12]}… — re-run cobol-chunking",
            file=sys.stderr,
        )
        return EXIT_STALE

    chunk = find_chunk(manifest, args.chunk_id)

    chunks_index_path = doc_dir / "chunks" / "index.json"
    if not chunks_index_path.exists():
        print(f"ERROR: missing chunks/index.json — re-run chunk-text-extraction: {chunks_index_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    chunks_index = json.loads(chunks_index_path.read_text(encoding="utf-8"))
    fname = find_chunk_filename(chunks_index, args.chunk_id)

    chunk_text_path = doc_dir / "chunks" / fname
    if not chunk_text_path.exists():
        print(f"ERROR: missing chunk-text file — re-run chunk-text-extraction: {chunk_text_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    chunk_text_bytes = chunk_text_path.read_bytes()

    slice_name = Path(fname).with_suffix(".json").name
    slice_path = doc_dir / "facts-slices" / slice_name
    if not slice_path.exists():
        print(f"ERROR: missing facts-slice — re-run facts-slicing: {slice_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    facts_slice = json.loads(slice_path.read_text(encoding="utf-8"))

    profile_path = Path(args.profile) if args.profile else DEFAULT_PROFILE
    if not profile_path.is_absolute():
        profile_path = (REPO_ROOT / profile_path).resolve()
    profile_bytes = profile_path.read_bytes()
    profile = yaml.safe_load(profile_bytes.decode("utf-8")) or {}

    template_path = pick_template(chunk, args.template)
    if not template_path.exists():
        print(f"ERROR: template not found: {template_path}", file=sys.stderr)
        return EXIT_USAGE
    template_bytes = template_path.read_bytes()

    languages = parse_languages(args.languages)
    md_name = Path(fname).with_suffix(".md").name
    diagram_name = f"section-{Path(fname).stem}.mmd"

    rel = lambda p: str(p.relative_to(REPO_ROOT)).replace("\\", "/")
    output_paths: dict[str, str] = {}
    for lang in languages:
        output_paths[lang] = rel(REPO_ROOT / "docs" / lang / source_path.name / "sections" / md_name)
    output_paths["diagram"] = rel(doc_dir / "diagrams" / diagram_name)

    bundle = {
        "bundle_version": "1.0",
        "source_path": rel(source_path),
        "source_kind": manifest.get("source_kind", "cobol"),
        "source_platform": manifest.get("source_platform", "mainframe"),
        "chunk": chunk,
        "chunk_text": chunk_text_bytes.decode("utf-8", errors="replace"),
        "chunk_text_sha": sha256_bytes(chunk_text_bytes),
        "facts_slice": facts_slice,
        "facts_slice_sha": canonical_json_sha(facts_slice),
        "template_path": rel(template_path),
        "template_text": template_bytes.decode("utf-8", errors="replace"),
        "template_sha": sha256_bytes(template_bytes),
        "profile_path": rel(profile_path),
        "profile": profile,
        "profile_sha": sha256_bytes(profile_bytes),
        "languages": languages,
        "diagram_kind": pick_diagram_kind(chunk),
        "output_paths": output_paths,
        "glossary": build_glossary_info(),
    }

    payload = json.dumps(bundle, indent=2, ensure_ascii=False) + "\n"
    if args.out:
        out_path = Path(args.out)
        if not out_path.is_absolute():
            out_path = (REPO_ROOT / out_path).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(payload, encoding="utf-8")
        md_note = ""
        if not args.no_md_view:
            try:
                # Local import keeps assemble-inputs.py runnable even if the
                # renderer is missing; the MD view is a convenience, not a
                # contract — the JSON is authoritative.
                import importlib.util as _ilu

                _spec = _ilu.spec_from_file_location(
                    "_render_bundle_md", Path(__file__).with_name("render-bundle-md.py")
                )
                _mod = _ilu.module_from_spec(_spec)
                _spec.loader.exec_module(_mod)  # type: ignore[union-attr]
                md_path = out_path.with_suffix(".md")
                md_path.write_text(_mod.render(bundle), encoding="utf-8")
                md_note = f", md_view={md_path.name}"
            except Exception as exc:  # noqa: BLE001 — best-effort sidecar
                md_note = f", md_view_skipped={type(exc).__name__}"
        print(
            f"OK: bundle written to {out_path} "
            f"(chunk={chunk.get('kind')}/{args.chunk_id}, "
            f"languages={','.join(languages)}, "
            f"template_sha={bundle['template_sha'][:8]}, "
            f"slice_sha={bundle['facts_slice_sha'][:8]}, "
            f"text_sha={bundle['chunk_text_sha'][:8]}"
            f"{md_note})"
        )
    else:
        sys.stdout.write(payload)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
