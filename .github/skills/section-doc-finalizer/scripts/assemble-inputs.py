#!/usr/bin/env python3
"""Deterministic prompt-bundle packager for the `section-doc-finalizer` skill.

For ONE source file, loads the chunk manifest + facts.json TOC subset +
every per-language sections/*.md (with a deterministic excerpt), and
emits a single JSON bundle the per-file finalizer agent feeds to its
LLM call to author index.md + complete.md per language.

NO LLM CALLS. Fully deterministic.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SKILL_ROOT.parents[2]
DEFAULT_DOC_ROOT = REPO_ROOT / "docs" / "_shared"
SOURCES_YAML = REPO_ROOT / "config" / "sources.yaml"
DEFAULT_PROFILE = REPO_ROOT / "config" / "templates" / "docs" / "functional-analysis" / "default" / "profile.yaml"
GLOSSARY_PATH = REPO_ROOT / "docs" / "_glossary.md"

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_MISSING_PREREQ = 4
EXIT_STALE = 5

SUMMARY_MAX_CHARS = 320


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


def parse_languages(value: str) -> list[str]:
    langs = [s.strip() for s in (value or "en").split(",") if s.strip()]
    seen: list[str] = []
    for l in (["en"] + langs):
        if l not in seen:
            seen.append(l)
    return seen


def excerpt_en_summary(md_path: Path) -> str:
    """First non-heading, non-blank paragraph after `## Summary` (or legacy `## TL;DR`)."""
    if not md_path.exists():
        return ""
    text = md_path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    in_tldr = False
    buf: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not in_tldr:
            if re.match(r"^##\s+(?:Summary|TL;DR)\b", stripped, flags=re.IGNORECASE):
                in_tldr = True
            continue
        if stripped.startswith("#"):
            break
        if not stripped:
            if buf:
                break
            continue
        buf.append(stripped)
    para = " ".join(buf).strip()
    if len(para) > SUMMARY_MAX_CHARS:
        para = para[:SUMMARY_MAX_CHARS - 1].rstrip() + "…"
    return para


def load_profile(path_override: str | None) -> dict:
    profile_path = Path(path_override) if path_override else DEFAULT_PROFILE
    if not profile_path.is_absolute():
        profile_path = (REPO_ROOT / profile_path).resolve()
    if not profile_path.exists():
        return {}
    return yaml.safe_load(profile_path.read_text(encoding="utf-8")) or {}


def build_toc(chunks_index: dict, manifest_chunks: list[dict], source_name: str,
              languages: list[str]) -> list[dict]:
    file_by_id = {c["id"]: c["file"] for c in (chunks_index.get("chunks") or [])}
    toc: list[dict] = []
    for chunk in manifest_chunks:
        cid = chunk["id"]
        stem = Path(file_by_id.get(cid, "")).stem
        if not stem:
            continue
        section_md: dict[str, str] = {}
        for lang in languages:
            rel = f"docs/{lang}/{source_name}/sections/{stem}.md"
            section_md[lang] = rel
        en_path = REPO_ROOT / "docs" / "en" / source_name / "sections" / f"{stem}.md"
        toc.append({
            "chunk_id": cid,
            "kind": chunk.get("kind"),
            "name": chunk.get("name"),
            "parent_id": chunk.get("parent_id"),
            "start_line": chunk.get("start_line"),
            "end_line": chunk.get("end_line"),
            "section_md": section_md,
            "summary_en": excerpt_en_summary(en_path),
        })
    return toc


def has_cursor_sql(facts: dict) -> bool:
    cursor_terms = ("declare cursor", "open", "fetch", "close", "cursor")
    for item in facts.get("exec_sql") or []:
        kind = (item.get("kind") or "").lower()
        statement = (item.get("statement") or "").lower()
        if any(term in kind or term in statement for term in cursor_terms):
            return True
    return False


def list_diagrams(source_name: str, facts: dict) -> list[str]:
    diag_dir = REPO_ROOT / "docs" / "_shared" / source_name / "diagrams"
    # Only include FILE-LEVEL overview .mmd files (no per-section prefix).
    basenames = {
        path.name
        for path in diag_dir.glob("*.mmd")
        if not path.name.startswith("section-")
    }
    expected = (
        ("performs", "call-graph.mmd"),
        ("go_tos", "control-flow.mmd"),
        ("jcl_steps", "jcl-steps.mmd"),
        ("cl_commands", "cl-command-flow.mmd"),
        ("exec_cics", "cics-calls.mmd"),
        ("data_records", "er-fragment.mmd"),
    )
    basenames.update(basename for key, basename in expected if facts.get(key))
    if build_inter_program_calls(facts):
        basenames.add("inter-program-call-graph.mmd")
    if has_cursor_sql(facts):
        basenames.add("cursor-lifecycle.mmd")
    return [
        f"docs/_shared/{source_name}/diagrams/{basename}"
        for basename in sorted(basenames)
    ]


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


def build_internal_calls(facts: dict) -> list[dict]:
    """Normalize paragraph-level PERFORM and GO TO edges for documentation."""
    rows: list[dict] = []
    for item in facts.get("performs") or []:
        rows.append({
            "caller": item.get("from"),
            "relationship": "perform",
            "target": item.get("to"),
            "range_end": item.get("thru_to"),
            "line": item.get("line"),
        })
    for item in facts.get("go_tos") or []:
        targets = item.get("to")
        if not isinstance(targets, list):
            targets = [targets]
        for target in targets:
            rows.append({
                "caller": item.get("from"),
                "relationship": "go-to",
                "target": target,
                "range_end": None,
                "line": item.get("line"),
            })
    return sorted(rows, key=lambda row: (row.get("line") or 0, row.get("caller") or ""))


def build_inter_program_calls(facts: dict) -> list[dict]:
    """Normalize outbound and inbound program edges for tables and diagrams."""
    program_id = facts.get("program_id") or Path(facts.get("source_path") or "source").stem
    rows: list[dict] = []
    for item in facts.get("calls") or []:
        rows.append({
            "direction": "outbound",
            "source": program_id,
            "source_location": item.get("from"),
            "relationship": item.get("kind") or "call",
            "target": item.get("target"),
            "dynamic": bool(item.get("dynamic")),
            "line": item.get("line"),
        })
    for item in facts.get("incoming_xref") or []:
        if item.get("via") == "copy":
            continue
        rows.append({
            "direction": "inbound",
            "source": item.get("caller_source"),
            "source_location": None,
            "relationship": item.get("via") or "call",
            "target": program_id,
            "dynamic": False,
            "line": item.get("line"),
        })
    return sorted(
        rows,
        key=lambda row: (
            row.get("direction") or "",
            row.get("source") or "",
            row.get("line") or 0,
            row.get("target") or "",
        ),
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="Package per-file section-doc-finalizer inputs.")
    ap.add_argument("--source", required=True)
    ap.add_argument("--languages", default="en")
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--profile", default=None)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    source_root = resolve_source_root(args.source_root)
    source_path = resolve_source(args.source, source_root)
    source_name = source_path.name
    doc_dir = REPO_ROOT / "docs" / "_shared" / source_name
    manifest_path = doc_dir / "chunk-manifest.json"
    facts_path = doc_dir / "facts.json"
    chunks_index_path = doc_dir / "chunks" / "index.json"
    for required in (manifest_path, facts_path, chunks_index_path):
        if not required.exists():
            print(f"ERROR: missing prerequisite: {required}", file=sys.stderr)
            return EXIT_MISSING_PREREQ

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    facts = json.loads(facts_path.read_text(encoding="utf-8"))
    chunks_index = json.loads(chunks_index_path.read_text(encoding="utf-8"))

    src_sha_on_disk = sha256_bytes(source_path.read_bytes())
    manifest_sha = manifest.get("sha256")
    if manifest_sha and manifest_sha != src_sha_on_disk:
        print(f"ERROR: chunk-manifest.json is stale vs {source_name} — re-run phase A.", file=sys.stderr)
        return EXIT_STALE

    languages = parse_languages(args.languages)
    toc = build_toc(chunks_index, manifest.get("chunks") or [], source_name, languages)

    facts_toc = {
        "paragraphs": facts.get("paragraphs") or [],
        "incoming_xref": facts.get("incoming_xref") or [],
        "calls": facts.get("calls") or [],
        "internal_calls": build_internal_calls(facts),
        "inter_program_calls": build_inter_program_calls(facts),
    }

    output_paths: dict[str, dict[str, str]] = {}
    for lang in languages:
        output_paths[lang] = {
            "index": f"docs/{lang}/{source_name}/index.md",
            "complete": f"docs/{lang}/{source_name}/complete.md",
        }

    bundle = {
        "bundle_version": "1.0",
        "source_path": str(source_path).replace("\\", "/"),
        "source_kind": facts.get("source_kind"),
        "source_platform": facts.get("source_platform", "mainframe"),
        "program_id": facts.get("program_id"),
        "manifest_sha": manifest_sha,
        "languages": languages,
        "toc": toc,
        "toc_sha": canonical_json_sha(toc),
        "facts_toc": facts_toc,
        "facts_toc_sha": canonical_json_sha(facts_toc),
        "diagrams_present": list_diagrams(source_name, facts),
        "output_paths": output_paths,
        "profile": load_profile(args.profile),
        "glossary": build_glossary_info(),
    }

    out = json.dumps(bundle, ensure_ascii=False, indent=2)
    if args.out:
        out_path = Path(args.out)
        if not out_path.is_absolute():
            out_path = (REPO_ROOT / out_path).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(out + "\n", encoding="utf-8")
        print(f"OK: bundle written to {out_path} (sections={len(toc)}, "
              f"languages={','.join(languages)}, diagrams={len(bundle['diagrams_present'])}, "
              f"toc_sha={bundle['toc_sha'][:8]})")
    else:
        sys.stdout.write(out + "\n")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
