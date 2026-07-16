#!/usr/bin/env python3
"""Deterministic per-group finalize bundle assembler (phase I).

For ONE group declared in `config/grouping.yaml`, walks every member and
projects per-file phase-E artefacts (chunk-manifest.json, facts.json TOC,
per-language index.md / complete.md excerpts) into a single bundle the
`group-doc-finalizer` agent feeds to its LLM call.

Outputs:
  docs/_shared/_groups/<group_id>/_doc-bundles/_finalize.bundle.json
  docs/_shared/_groups/<group_id>/_doc-bundles/_finalize.bundle.md

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
DEFAULT_GROUPING = REPO_ROOT / "config" / "grouping.yaml"
GLOSSARY_PATH = REPO_ROOT / "docs" / "_glossary.md"

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_MISSING_PREREQ = 4

SUMMARY_MAX_CHARS = 320
EXCERPT_MAX_CHARS = 4000


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_sha(obj: object) -> str:
    return sha256_bytes(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def parse_languages(value: str) -> list[str]:
    raw = [s.strip() for s in (value or "en").split(",") if s.strip()]
    seen: list[str] = []
    for l in ["en", *raw]:
        if l not in seen:
            seen.append(l)
    return seen


def load_grouping(manifest_path: Path) -> dict:
    if not manifest_path.exists():
        raise SystemExit(f"ERROR: grouping manifest not found: {manifest_path}")
    return yaml.safe_load(manifest_path.read_text(encoding="utf-8")) or {}


def find_group(grouping: dict, group_id: str) -> dict:
    for g in (grouping.get("groups") or []):
        if g.get("id") == group_id:
            return g
    raise SystemExit(f"ERROR: group_id {group_id!r} not found in grouping.yaml")


def excerpt_tldr(md_path: Path) -> str:
    if not md_path.exists():
        return ""
    text = md_path.read_text(encoding="utf-8", errors="replace")
    in_tldr = False
    buf: list[str] = []
    for line in text.splitlines():
        s = line.strip()
        if not in_tldr:
            if s.lower().startswith("## summary") or s.lower().startswith("## tl;dr"):
                in_tldr = True
            continue
        if s.startswith("#"):
            break
        if not s:
            if buf:
                break
            continue
        buf.append(s)
    para = " ".join(buf).strip()
    if len(para) > SUMMARY_MAX_CHARS:
        para = para[: SUMMARY_MAX_CHARS - 1].rstrip() + "\u2026"
    return para


def excerpt_head(md_path: Path, max_chars: int = EXCERPT_MAX_CHARS) -> str:
    if not md_path.exists():
        return ""
    text = md_path.read_text(encoding="utf-8", errors="replace")
    if len(text) <= max_chars:
        return text
    return text[:max_chars].rstrip() + "\n\n\u2026(truncated)\u2026\n"


def build_member_record(member: str, languages: list[str]) -> dict:
    basename = Path(member).name
    shared_dir = REPO_ROOT / "docs" / "_shared" / basename
    manifest_path = shared_dir / "chunk-manifest.json"
    facts_path = shared_dir / "facts.json"

    if not manifest_path.exists():
        raise SystemExit(
            f"ERROR: missing chunk-manifest for member {basename!r}: {manifest_path}"
        )
    if not facts_path.exists():
        raise SystemExit(f"ERROR: missing facts.json for member {basename!r}: {facts_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    facts = json.loads(facts_path.read_text(encoding="utf-8"))

    toc: list[dict] = []
    for c in (manifest.get("chunks") or []):
        toc.append(
            {
                "chunk_id": c.get("id"),
                "kind": c.get("kind"),
                "name": c.get("name"),
                "parent_id": c.get("parent_id"),
                "start_line": c.get("start_line"),
                "end_line": c.get("end_line"),
            }
        )

    outputs: dict[str, dict] = {}
    for lang in languages:
        idx = REPO_ROOT / "docs" / lang / basename / "index.md"
        cmp_ = REPO_ROOT / "docs" / lang / basename / "complete.md"
        outputs[lang] = {
            "index": f"docs/{lang}/{basename}/index.md",
            "complete": f"docs/{lang}/{basename}/complete.md",
            "exists": idx.exists() and cmp_.exists(),
            "summary": excerpt_tldr(idx),
            "index_excerpt": excerpt_head(idx),
        }

    if not outputs.get("en", {}).get("exists"):
        raise SystemExit(
            f"ERROR: phase-E EN outputs missing for member {basename!r} \u2014 "
            f"expected docs/en/{basename}/index.md and complete.md"
        )

    return {
        "basename": basename,
        "source_path": member.replace("\\", "/"),
        "source_kind": facts.get("source_kind"),
        "source_platform": facts.get("source_platform", "mainframe"),
        "program_id": facts.get("program_id"),
        "manifest_sha": manifest.get("sha256"),
        "toc": toc,
        "incoming_xref": facts.get("incoming_xref") or [],
        "calls": facts.get("calls") or [],
        "paragraphs": facts.get("paragraphs") or [],
        "outputs": outputs,
    }


def build_glossary_info() -> dict:
    rel = "docs/_glossary.md"
    if not GLOSSARY_PATH.exists():
        return {"path": rel, "exists": False, "sha256": None}
    text = GLOSSARY_PATH.read_text(encoding="utf-8", errors="replace")
    return {"path": rel, "exists": True, "sha256": sha256_bytes(text.encode("utf-8"))}


def render_markdown_view(bundle: dict) -> str:
    lines: list[str] = []
    lines.append(f"# Group finalize bundle \u2014 `{bundle['group_id']}`\n")
    desc = bundle.get("group_description") or "(no description)"
    lines.append(f"**Description:** {desc}\n")
    lines.append(f"**Languages:** {', '.join(bundle['languages'])}\n")
    lines.append(f"**Members:** {len(bundle['members'])}\n")
    lines.append("\n## Output paths\n")
    for lang, paths in bundle["output_paths"].items():
        lines.append(f"- `{lang}` \u2192 `{paths['index']}`, `{paths['complete']}`")
    lines.append("\n## Members\n")
    for m in bundle["members"]:
        lines.append(
            f"### `{m['basename']}` ({m.get('source_kind') or 'unknown'}, "
            f"{m.get('source_platform') or 'mainframe'})\n"
        )
        if m.get("program_id"):
            lines.append(f"- program_id: `{m['program_id']}`")
        lines.append(f"- chunks: {len(m['toc'])}")
        lines.append(f"- incoming_xref entries: {len(m['incoming_xref'])}")
        lines.append(f"- calls entries: {len(m['calls'])}")
        en = m["outputs"].get("en") or {}
        if en.get("summary"):
            lines.append(f"\n**EN Summary:** {en['summary']}\n")
        if en.get("index_excerpt"):
            lines.append("\n<details><summary>EN index.md excerpt</summary>\n\n```markdown")
            lines.append(en["index_excerpt"].rstrip())
            lines.append("```\n\n</details>\n")
        lines.append("")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Stage per-group finalize bundle for phase I.")
    ap.add_argument("--group-id", required=True)
    ap.add_argument("--languages", default="en")
    ap.add_argument("--manifest", default=str(DEFAULT_GROUPING))
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    manifest_path = Path(args.manifest)
    if not manifest_path.is_absolute():
        manifest_path = (REPO_ROOT / manifest_path).resolve()

    grouping = load_grouping(manifest_path)
    group = find_group(grouping, args.group_id)

    members = group.get("members") or []
    if not members:
        print(f"ERROR: group {args.group_id!r} has no members.", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    languages = parse_languages(args.languages)
    member_records = [build_member_record(m, languages) for m in members]
    members_sha = canonical_json_sha(
        [{"basename": m["basename"], "manifest_sha": m["manifest_sha"]} for m in member_records]
    )

    output_paths = {
        lang: {
            "index": f"docs/{lang}/_groups/{args.group_id}/index.md",
            "complete": f"docs/{lang}/_groups/{args.group_id}/complete.md",
        }
        for lang in languages
    }

    bundle = {
        "bundle_version": "1.0",
        "group_id": args.group_id,
        "group_description": group.get("description") or "",
        "languages": languages,
        "members": member_records,
        "members_sha": members_sha,
        "output_paths": output_paths,
        "glossary": build_glossary_info(),
    }

    out_json = args.out or f"docs/_shared/_groups/{args.group_id}/_doc-bundles/_finalize.bundle.json"
    out_json_path = Path(out_json)
    if not out_json_path.is_absolute():
        out_json_path = (REPO_ROOT / out_json_path).resolve()
    out_json_path.parent.mkdir(parents=True, exist_ok=True)
    out_json_path.write_text(
        json.dumps(bundle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    out_md_path = out_json_path.with_suffix(".md")
    out_md_path.write_text(render_markdown_view(bundle), encoding="utf-8")

    print(
        f"OK: group bundle written to {out_json_path.relative_to(REPO_ROOT)} "
        f"(members={len(member_records)}, languages={','.join(languages)}, "
        f"members_sha={members_sha[:8]})"
    )
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
