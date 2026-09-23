#!/usr/bin/env python3
"""Deterministic per-GROUP technical-analysis (ATE) bundle packager.

SIMPLE single-pass finalizer input for ONE group declared in
`config/grouping.yaml`. Loads:
  - the first requested language's group consolidated documentation
    `docs/<lang>/_groups/<group_id>/complete.md` (phase-I output; the SINGLE
    narrative source the writer draws from),
  - the resolved technical-analysis profile (group auto-detect rule) +
    per-language template,
and emits a single bundle the `technical-analysis-writer` agent feeds to
its LLM call to author `docs/<lang>/_groups/<group_id>/technical-analysis.md`.

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

sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))
import ta_profile_resolver as tpr  # noqa: E402

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_MISSING_PREREQ = 4


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_languages(value: str) -> list[str]:
    parts = [p.strip().lower() for p in (value or "en").split(",") if p.strip()]
    return list(dict.fromkeys(parts))


def rel(p: Path) -> str:
    return str(p.resolve().relative_to(REPO_ROOT)).replace("\\", "/")


def load_group(manifest: Path, group_id: str) -> dict:
    data = yaml.safe_load(manifest.read_text(encoding="utf-8")) or {}
    for g in data.get("groups") or []:
        if g.get("id") == group_id:
            return g
    raise SystemExit(f"ERROR: group '{group_id}' not found in {manifest}")


def synthesize_group_complete(group_id: str, members: list[str], language: str = "en") -> str:
    parts: list[str] = []
    for member in members:
        base = Path(member).name
        md_path = REPO_ROOT / "docs" / language / base / "complete.md"
        if not md_path.exists():
            continue
        text = md_path.read_text(encoding="utf-8", errors="replace").strip()
        if not text:
            continue
        parts.append(f"\n\n<!-- member: {base} -->\n\n{text}\n")

    if not parts:
        raise SystemExit(
            f"ERROR: missing group complete.md and no member complete.md files were found for group '{group_id}'."
        )

    header = (
        f"# {group_id} — Group Complete (auto-generated fallback)\n\n"
        f"This document was auto-generated because docs/{language}/_groups/{group_id}/complete.md was missing. "
        "It is composed from available per-member complete.md files in group order.\n"
    )
    return header + "\n".join(parts).strip() + "\n"


def group_front_matter(group_id: str, profile: dict) -> dict:
    fm = profile.get("front_matter") or {}
    return {
        "ACRONYM": group_id.upper(),
        "INTERFACE_NAME": group_id,
        "PROGRAM_ID": group_id,
        "TITLE": group_id,
        "CLASSIFICATION": (fm.get("classification") or {}).get("default", ""),
        "AUTHORIZED_OFFICE": fm.get("authorized_office", ""),
        "AUTHOR": "",
        "VERSION": "1.0",
        "CREATION_DATE": "",
        "STATE": (fm.get("state_options") or ["DRAFT"])[0] if fm.get("state_options") else "DRAFT",
        "TEMPLATE_VERSION": fm.get("template_version", ""),
        "GENERATED_AT": "",
        "LANG": "",
        "SIBLING_LINK": "",
    }


def render_md_view(bundle: dict) -> str:
    out: list[str] = []
    out.append(f"# Technical-Analysis Group Bundle: {bundle['group_id']}")
    out.append("")
    out.append("> Derived view of the bundle JSON. The `.json` sibling is authoritative.")
    out.append("")
    out.append("## Metadata")
    out.append("")
    out.append("| key | value |")
    out.append("|---|---|")
    for k in ("bundle_version", "scope", "group_id", "profile_name", "profile_path",
              "profile_sha", "complete_md_path", "complete_md_sha"):
        out.append(f"| `{k}` | {bundle.get(k, '')} |")
    out.append(f"| `members` | {', '.join(bundle.get('members') or [])} |")
    out.append(f"| `languages` | {', '.join(bundle.get('languages') or [])} |")
    out.append("")
    out.append("## Output paths")
    out.append("")
    for lang, p in (bundle.get("output_paths") or {}).items():
        out.append(f"- **{lang}** → `{p}`")
    out.append("")
    out.append("## Front-matter values")
    out.append("")
    out.append("| key | value |")
    out.append("|---|---|")
    for k, v in (bundle.get("front_matter_values") or {}).items():
        out.append(f"| `{k}` | {v} |")
    out.append("")
    out.append("## Ordered sections")
    out.append("")
    out.append("| id | number | title | required | optional_marker |")
    out.append("|---|---|---|---|---|")
    for s in bundle.get("ordered_sections") or []:
        out.append(
            f"| `{s.get('id')}` | {s.get('number', '')} | {s.get('title', '')} | "
            f"{s.get('required', '')} | {s.get('optional_marker', '')} |"
        )
    out.append("")
    out.append("## Profile spec")
    out.append("")
    out.append("```yaml")
    out.append(yaml.safe_dump(bundle.get("profile") or {}, sort_keys=False, allow_unicode=True).rstrip())
    out.append("```")
    out.append("")
    for lang, tpl in (bundle.get("templates") or {}).items():
        out.append(f"## Template — `{lang}`")
        out.append("")
        out.append("```markdown")
        out.append((tpl or "").rstrip())
        out.append("```")
        out.append("")
    out.append(f"## Narrative source — {bundle['languages'][0]} group complete.md")
    out.append("")
    out.append("```markdown")
    out.append((bundle.get("complete_md") or "").rstrip())
    out.append("```")
    out.append("")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Package the per-group technical-analysis bundle.")
    ap.add_argument("--group-id", required=True)
    ap.add_argument("--manifest", default="config/grouping.yaml")
    ap.add_argument("--profile-name", default=None)
    ap.add_argument("--languages", default="en")
    ap.add_argument("--out", default=None)
    ap.add_argument("--no-md-view", action="store_true")
    args = ap.parse_args()

    manifest = Path(args.manifest)
    if not manifest.is_absolute():
        manifest = (REPO_ROOT / manifest).resolve()
    if not manifest.exists():
        print(f"ERROR: grouping manifest not found: {manifest}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    group = load_group(manifest, args.group_id)
    members = [str(m) for m in (group.get("members") or [])]

    # Profile resolution (group auto-detect by member extensions).
    if args.profile_name:
        if args.profile_name not in tpr.KNOWN_PROFILES:
            print(f"ERROR: unknown profile: {args.profile_name}", file=sys.stderr)
            return EXIT_USAGE
        effective_name, profile_dir, note = tpr.resolve_profile_dir(args.profile_name, fallback_to_default=False)
        if profile_dir is None:
            print(f"ERROR: profile templates not found for '{args.profile_name}' under {tpr.TA_ROOT}", file=sys.stderr)
            return EXIT_USAGE
        resolution = tpr.TAResolution(
            effective_name,
            profile_dir,
            "explicit" + (f"; {note}" if note else ""),
            False,
        )
    else:
        resolution = tpr.resolve_for_group([Path(m) for m in members])
    if resolution.profile_dir is None:
        print(
            f"ERROR: unable to resolve an existing TA profile directory for group {args.group_id}: {resolution.reason}",
            file=sys.stderr,
        )
        return EXIT_MISSING_PREREQ

    languages = parse_languages(args.languages)
    complete_md_path = REPO_ROOT / "docs" / languages[0] / "_groups" / args.group_id / "complete.md"
    if not complete_md_path.exists():
        complete_md = synthesize_group_complete(args.group_id, members, languages[0])
        complete_md_path.parent.mkdir(parents=True, exist_ok=True)
        complete_md_path.write_text(complete_md, encoding="utf-8")
        print(
            f"INFO: synthesized missing group complete.md from member complete.md files: {complete_md_path}",
            file=sys.stderr,
        )
    else:
        complete_md = complete_md_path.read_text(encoding="utf-8", errors="replace")

    profile_yaml_path = resolution.profile_dir / "profile.yaml"
    profile_bytes = profile_yaml_path.read_bytes()
    profile = yaml.safe_load(profile_bytes.decode("utf-8")) or {}

    templates_by_lang = tpr.template_paths(resolution.profile_dir, languages)
    templates = {lang: p.read_text(encoding="utf-8", errors="replace") for lang, p in templates_by_lang.items()}

    flat = tpr.flatten_sections(profile)
    ordered_sections = [
        {
            "id": s.get("id"),
            "number": s.get("number", ""),
            "title": s.get("title", ""),
            "required": bool(s.get("required", False)),
            "optional_marker": s.get("optional_marker", ""),
            "parent_id": s.get("_parent_id"),
        }
        for s in flat
    ]

    output_paths = {
        lang: rel(REPO_ROOT / "docs" / lang / "_groups" / args.group_id / "technical-analysis.md")
        for lang in languages
    }

    bundle = {
        "bundle_version":      "1.0",
        "scope":               "per-group",
        "group_id":            args.group_id,
        "members":             members,
        "profile_name":        resolution.profile,
        "profile_path":        rel(profile_yaml_path),
        "profile":             profile,
        "profile_sha":         sha256_bytes(profile_bytes),
        "front_matter_values": group_front_matter(args.group_id, profile),
        "languages":           languages,
        "ordered_sections":    ordered_sections,
        "templates":           templates,
        "complete_md_path":    rel(complete_md_path),
        "complete_md_sha":     sha256_bytes(complete_md.encode("utf-8")),
        "complete_md":         complete_md,
        "output_paths":        output_paths,
    }

    out_path = Path(args.out) if args.out else (
        REPO_ROOT / "docs" / "_shared" / "_groups" / args.group_id
        / "_ta-group-bundles" / "_finalize.bundle.json"
    )
    if not out_path.is_absolute():
        out_path = (REPO_ROOT / out_path).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(bundle, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    md_note = ""
    if not args.no_md_view:
        md_path = out_path.with_suffix(".md")
        md_path.write_text(render_md_view(bundle), encoding="utf-8")
        md_note = f", md_view={md_path.name}"
    print(f"OK: technical-analysis group bundle written to {out_path} "
          f"(profile={resolution.profile}, languages={','.join(languages)}{md_note})")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
