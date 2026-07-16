#!/usr/bin/env python3
"""Deterministic per-group functional-analysis finalize bundle assembler (phase K).

Simplified single-call (phase-I style) assembler. For ONE group declared in
`config/grouping.yaml`, walks every member and projects each member's per-file
phase-G `functional-analysis.md` plus the group's phase-J `requirements.md` into
a single bundle the `functional-analysis-group-writer` agent feeds to its LLM
call.

Outputs:
  docs/_shared/_groups/<group_id>/_fa-group-bundles/_finalize.bundle.json
  docs/_shared/_groups/<group_id>/_fa-group-bundles/_finalize.bundle.md

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
PROFILE_ROOT = REPO_ROOT / "config" / "templates" / "docs" / "functional-analysis"

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_MISSING_PREREQ = 4

SUMMARY_MAX_CHARS = 320
MEMBER_DOC_MAX_CHARS = 16000
GROUP_DOC_MAX_CHARS = 8000


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


def excerpt_head(md_path: Path, max_chars: int) -> str:
    if not md_path.exists():
        return ""
    text = md_path.read_text(encoding="utf-8", errors="replace")
    if len(text) <= max_chars:
        return text
    return text[:max_chars].rstrip() + "\n\n\u2026(truncated)\u2026\n"


def resolve_profile_name(explicit: str | None, source_kinds: list[str]) -> str:
    if explicit:
        return explicit
    kinds = {(k or "").lower() for k in source_kinds}
    if kinds & {"cics", "bms"}:
        return "default"
    if kinds & {"jcl", "prc", "proc"}:
        return "default"
    return "default"


def load_profile(profile_name: str) -> dict:
    profile_path = PROFILE_ROOT / profile_name / "profile.yaml"
    rel = str(profile_path.relative_to(REPO_ROOT)).replace("\\", "/")
    if not profile_path.exists():
        return {"name": profile_name, "path": rel, "exists": False, "front_matter_values": {}}
    data = yaml.safe_load(profile_path.read_text(encoding="utf-8")) or {}
    fm = data.get("front_matter_values") or data.get("front_matter") or {}
    return {
        "name": profile_name,
        "path": rel,
        "exists": True,
        "sha256": sha256_bytes(profile_path.read_bytes()),
        "front_matter_values": fm,
    }


def build_member_record(member: str, languages: list[str]) -> dict:
    basename = Path(member).name
    shared_dir = REPO_ROOT / "docs" / "_shared" / basename
    facts_path = shared_dir / "facts.json"
    facts = {}
    if facts_path.exists():
        facts = json.loads(facts_path.read_text(encoding="utf-8"))

    docs: dict[str, dict] = {}
    for lang in languages:
        fa = REPO_ROOT / "docs" / lang / basename / "functional-analysis.md"
        docs[lang] = {
            "functional_analysis": f"docs/{lang}/{basename}/functional-analysis.md",
            "exists": fa.exists(),
            "excerpt": excerpt_head(fa, MEMBER_DOC_MAX_CHARS),
        }

    if not docs.get("en", {}).get("exists"):
        raise SystemExit(
            f"ERROR: phase-G EN functional-analysis.md missing for member {basename!r} \u2014 "
            f"expected docs/en/{basename}/functional-analysis.md"
        )

    return {
        "basename": basename,
        "source_path": member.replace("\\", "/"),
        "source_kind": facts.get("source_kind"),
        "source_platform": facts.get("source_platform", "mainframe"),
        "program_id": facts.get("program_id"),
        "docs": docs,
    }


def build_group_doc_info(group_id: str, languages: list[str]) -> dict:
    info: dict[str, dict] = {}
    for lang in languages:
        req = REPO_ROOT / "docs" / lang / "_groups" / group_id / "requirements.md"
        info[lang] = {
            "requirements": f"docs/{lang}/_groups/{group_id}/requirements.md",
            "exists": req.exists(),
            "excerpt": excerpt_head(req, GROUP_DOC_MAX_CHARS),
        }
    return info


def build_glossary_info() -> dict:
    rel = "docs/_glossary.md"
    if not GLOSSARY_PATH.exists():
        return {"path": rel, "exists": False, "sha256": None}
    text = GLOSSARY_PATH.read_text(encoding="utf-8", errors="replace")
    return {"path": rel, "exists": True, "sha256": sha256_bytes(text.encode("utf-8"))}


def render_markdown_view(bundle: dict) -> str:
    lines: list[str] = []
    lines.append(f"# Group functional-analysis finalize bundle \u2014 `{bundle['group_id']}`\n")
    desc = bundle.get("group_description") or "(no description)"
    lines.append(f"**Description:** {desc}\n")
    lines.append(f"**Languages:** {', '.join(bundle['languages'])}\n")
    lines.append(f"**Profile:** `{bundle['profile']['name']}`\n")
    lines.append(f"**Members:** {len(bundle['members'])}\n")
    lines.append("\n## Output paths\n")
    for lang, path in bundle["output_paths"].items():
        lines.append(f"- `{lang}` \u2192 `{path}`")
    lines.append("\n## Member order (verbatim from grouping.yaml)\n")
    for i, m in enumerate(bundle["members"], 1):
        lines.append(
            f"{i}. `{m['basename']}` ({m.get('source_kind') or 'unknown'}, "
            f"{m.get('source_platform') or 'mainframe'})"
        )
    lines.append("\n## Group context (phase-J requirements.md, EN)\n")
    gen = bundle["group_doc"].get("en") or {}
    if gen.get("excerpt"):
        lines.append("\n<details><summary>EN requirements.md excerpt</summary>\n\n```markdown")
        lines.append(gen["excerpt"].rstrip())
        lines.append("```\n\n</details>\n")
    lines.append("\n## Member functional analyses (phase-G, EN)\n")
    for m in bundle["members"]:
        lines.append(
            f"### `{m['basename']}` ({m.get('source_kind') or 'unknown'}, "
            f"{m.get('source_platform') or 'mainframe'})\n"
        )
        if m.get("program_id"):
            lines.append(f"- program_id: `{m['program_id']}`")
        lines.append(f"- source functional analysis: `{m['docs']['en']['functional_analysis']}`")
        en = m["docs"].get("en") or {}
        if en.get("excerpt"):
            lines.append("\n<details><summary>EN functional-analysis.md excerpt</summary>\n\n```markdown")
            lines.append(en["excerpt"].rstrip())
            lines.append("```\n\n</details>\n")
        lines.append("")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Stage per-group functional-analysis finalize bundle (phase K).")
    ap.add_argument("--group-id", required=True)
    ap.add_argument("--languages", default="en")
    ap.add_argument("--manifest", default=str(DEFAULT_GROUPING))
    ap.add_argument("--profile-name", default=None)
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

    # Per-file phase-G functional-analysis.md is not generated for PROC (*.prc)
    # sources (PRC files are excluded upstream and have no docs/_shared entry).
    # Drop PRC members here so their absent functional-analysis.md does not abort
    # the group bundle.
    prc_members = [m for m in members if Path(m).suffix.lower() == ".prc"]
    members = [m for m in members if Path(m).suffix.lower() != ".prc"]
    if prc_members:
        print(
            f"INFO: skipping {len(prc_members)} PRC member(s) with no phase-G functional-analysis.md: "
            + ", ".join(Path(m).name for m in prc_members),
            file=sys.stderr,
        )
    if not members:
        print(
            f"ERROR: group {args.group_id!r} has no non-PRC members with functional-analysis.",
            file=sys.stderr,
        )
        return EXIT_MISSING_PREREQ

    languages = parse_languages(args.languages)
    member_records = [build_member_record(m, languages) for m in members]
    source_kinds = [m.get("source_kind") for m in member_records]
    profile_name = resolve_profile_name(args.profile_name, source_kinds)
    profile = load_profile(profile_name)

    members_sha = canonical_json_sha(
        [{"basename": m["basename"], "source_path": m["source_path"]} for m in member_records]
    )

    output_paths = {
        lang: f"docs/{lang}/_groups/{args.group_id}/functional-analysis.md" for lang in languages
    }

    bundle = {
        "bundle_version": "1.0",
        "scope": "per-group",
        "phase": "K",
        "group_id": args.group_id,
        "group_description": group.get("description") or "",
        "languages": languages,
        "profile": profile,
        "members": member_records,
        "members_sha": members_sha,
        "group_doc": build_group_doc_info(args.group_id, languages),
        "output_paths": output_paths,
        "glossary": build_glossary_info(),
    }

    out_json = args.out or f"docs/_shared/_groups/{args.group_id}/_fa-group-bundles/_finalize.bundle.json"
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
        f"OK: group functional-analysis bundle written to {out_json_path.relative_to(REPO_ROOT)} "
        f"(members={len(member_records)}, languages={','.join(languages)}, "
        f"profile={profile_name}, members_sha={members_sha[:8]})"
    )
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
