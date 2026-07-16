#!/usr/bin/env python3
"""Deterministic per-file REQ finalizer bundle packager.

For ONE source file, loads the chosen requirements profile + every per-section
draft under `docs/_shared/<file>/_req-sections/<lang>/*.md` and emits a single
JSON bundle the per-file finalizer agent feeds to its LLM call. The bundle
embeds each per-section draft body verbatim (so the agent never re-reads them)
and carries the profile-driven ordering, optional-section markers, front-matter
values, and per-language output paths.

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
SOURCES_YAML = REPO_ROOT / "config" / "sources.yaml"
DOC_ROOT = REPO_ROOT / "docs" / "_shared"

sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))
import req_profile_resolver as rpr  # noqa: E402

# Reuse the per-section assembler's front-matter helper to keep the values
# byte-identical between bundles.
WRITER_SCRIPTS = REPO_ROOT / ".github" / "skills" / "requirements-writer" / "scripts"
sys.path.insert(0, str(WRITER_SCRIPTS))
import importlib.util as _ilu  # noqa: E402

_spec = _ilu.spec_from_file_location("_req_writer_assembler", WRITER_SCRIPTS / "assemble-inputs.py")
_writer_mod = _ilu.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(_writer_mod)  # type: ignore[union-attr]
front_matter_values = _writer_mod.front_matter_values

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_MISSING_PREREQ = 4
EXIT_STALE = 5


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_sources_yaml() -> dict:
    if not SOURCES_YAML.exists():
        return {}
    return yaml.safe_load(SOURCES_YAML.read_text(encoding="utf-8")) or {}


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
    parts = [p.strip().lower() for p in (value or "en").split(",") if p.strip()]
    if "en" in parts:
        rest = [p for p in parts if p != "en"]
        return ["en", *rest]
    return ["en", *parts]


def rel(p: Path) -> str:
    return str(p.resolve().relative_to(REPO_ROOT)).replace("\\", "/")


def render_md_view(bundle: dict) -> str:
    out: list[str] = []
    out.append(f"# REQ Finalizer Bundle: {Path(bundle['source_path']).name}")
    out.append("")
    out.append(
        "> Derived view of the bundle JSON. The `.json` sibling is authoritative."
    )
    out.append("")
    out.append("## Metadata")
    out.append("")
    out.append("| key | value |")
    out.append("|---|---|")
    for k in ("bundle_version", "scope", "source_path", "source_kind", "source_platform",
              "manifest_sha", "profile_name", "profile_path", "profile_sha"):
        out.append(f"| `{k}` | {bundle.get(k, '')} |")
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
    out.append("## Missing sections (per language)")
    out.append("")
    for lang, missing in (bundle.get("missing_sections") or {}).items():
        out.append(f"- **{lang}**: " + (", ".join(f"`{m}`" for m in missing) if missing else "_None._"))
    out.append("")
    for lang, drafts in (bundle.get("section_drafts") or {}).items():
        out.append(f"## Section drafts — `{lang}`")
        out.append("")
        for sid, body in drafts.items():
            out.append(f"### `{sid}`")
            out.append("")
            out.append("```markdown")
            out.append(body.rstrip())
            out.append("```")
            out.append("")
    out.append("## Footer")
    out.append("")
    out.append("```yaml")
    out.append(yaml.safe_dump(bundle.get("footer") or {}, sort_keys=False, allow_unicode=True).rstrip())
    out.append("```")
    out.append("")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Package the REQ per-file finalizer bundle.")
    ap.add_argument("--source", required=True)
    ap.add_argument("--profile-name", default=None)
    ap.add_argument("--languages", default="en")
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--no-md-view", action="store_true")
    args = ap.parse_args()

    cfg = load_sources_yaml()
    source_root = Path(args.source_root or cfg.get("source_root", "./samples"))
    if not source_root.is_absolute():
        source_root = (REPO_ROOT / source_root).resolve()
    source_path = resolve_source(args.source, source_root)
    doc_dir = DOC_ROOT / source_path.name

    facts_path = doc_dir / "facts.json"
    if not facts_path.exists():
        print(f"ERROR: missing facts.json: {facts_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    facts = json.loads(facts_path.read_text(encoding="utf-8"))

    manifest_path = doc_dir / "chunk-manifest.json"
    manifest_sha = ""
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest_sha = manifest.get("sha256") or ""
        on_disk_sha = sha256_bytes(source_path.read_bytes())
        if manifest_sha and manifest_sha != on_disk_sha:
            print(
                f"STALE: chunk-manifest sha {manifest_sha[:12]}… != source sha {on_disk_sha[:12]}… — re-run phase A",
                file=sys.stderr,
            )
            return EXIT_STALE

    bundles_dir = doc_dir / "_req-bundles"
    skip_marker = bundles_dir / "_skipped.json"
    if skip_marker.exists():
        print(f"SKIP: {source_path.name}: tombstoned at {skip_marker.relative_to(REPO_ROOT)}")
        return EXIT_OK

    if args.profile_name:
        if args.profile_name not in rpr.KNOWN_PROFILES:
            print(f"ERROR: unknown profile: {args.profile_name}", file=sys.stderr)
            return EXIT_USAGE
        effective_name, profile_dir, note = rpr.resolve_profile_dir(args.profile_name, fallback_to_default=False)
        if profile_dir is None:
            print(f"ERROR: profile templates not found for '{args.profile_name}' under {rpr.REQ_ROOT}", file=sys.stderr)
            return EXIT_USAGE
        resolution = rpr.REQResolution(
            effective_name,
            profile_dir,
            "explicit" + (f"; {note}" if note else ""),
            False,
        )
    else:
        resolution = rpr.resolve(source_path, facts)
    if resolution.skipped:
        print(f"SKIP: {source_path.name}: {resolution.reason}")
        return EXIT_OK
    if resolution.profile_dir is None:
        print(
            f"ERROR: unable to resolve an existing REQ profile directory for {source_path.name}: {resolution.reason}",
            file=sys.stderr,
        )
        return EXIT_MISSING_PREREQ
    profile_yaml_path = resolution.profile_dir / "profile.yaml"
    profile_bytes = profile_yaml_path.read_bytes()
    profile = yaml.safe_load(profile_bytes.decode("utf-8")) or {}

    languages = parse_languages(args.languages)
    flat = rpr.flatten_sections(profile)
    ordered_sections = []
    for spec in flat:
        ordered_sections.append({
            "id":              spec.get("id"),
            "number":          spec.get("number", ""),
            "title":           spec.get("title", ""),
            "required":        bool(spec.get("required", False)),
            "optional_marker": spec.get("optional_marker", ""),
            "parent_id":       spec.get("_parent_id"),
        })

    section_drafts: dict[str, dict[str, str]] = {}
    missing_sections: dict[str, list[str]] = {}
    for lang in languages:
        draft_dir = doc_dir / "_req-sections" / lang
        per_lang: dict[str, str] = {}
        missing: list[str] = []
        for spec in ordered_sections:
            sid = spec["id"]
            if sid == "header":
                continue
            p = draft_dir / f"{sid}.md"
            if p.exists():
                per_lang[sid] = p.read_text(encoding="utf-8", errors="replace")
            else:
                missing.append(sid)
        section_drafts[lang] = per_lang
        missing_sections[lang] = missing

    # Fail if any REQUIRED section is missing for any language.
    required_ids = {s["id"] for s in ordered_sections if s["required"] and s["id"] != "header"}
    hard_missing: dict[str, list[str]] = {
        lang: [sid for sid in miss if sid in required_ids]
        for lang, miss in missing_sections.items()
    }
    if any(hard_missing.values()):
        for lang, miss in hard_missing.items():
            if miss:
                print(f"ERROR: missing required REQ section drafts for lang={lang}: {', '.join(miss)}",
                      file=sys.stderr)
        return EXIT_MISSING_PREREQ

    output_paths = {
        lang: rel(REPO_ROOT / "docs" / lang / source_path.name / "requirements.md")
        for lang in languages
    }

    bundle = {
        "bundle_version":      "1.0",
        "scope":               "per-file",
        "source_path":         rel(source_path),
        "source_kind":         facts.get("source_kind", source_path.suffix.lstrip(".").lower() or "cobol"),
        "source_platform":     facts.get("source_platform", "mainframe"),
        "manifest_sha":        manifest_sha,
        "profile_name":        resolution.profile,
        "profile_path":        rel(profile_yaml_path),
        "profile":             profile,
        "profile_sha":         sha256_bytes(profile_bytes),
        "front_matter_values": front_matter_values(facts, profile, source_path),
        "languages":           languages,
        "ordered_sections":    ordered_sections,
        "section_drafts":      section_drafts,
        "missing_sections":    missing_sections,
        "footer":              profile.get("footer") or {},
        "output_paths":        output_paths,
    }

    out_path = Path(args.out) if args.out else (bundles_dir / "_finalize.bundle.json")
    if not out_path.is_absolute():
        out_path = (REPO_ROOT / out_path).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(bundle, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    md_note = ""
    if not args.no_md_view:
        md_path = out_path.with_suffix(".md")
        md_path.write_text(render_md_view(bundle), encoding="utf-8")
        md_note = f", md_view={md_path.name}"
    sec_counts = ", ".join(f"{l}={len(d)}" for l, d in section_drafts.items())
    print(f"OK: REQ finalizer bundle written to {out_path} "
          f"(profile={resolution.profile}, languages={','.join(languages)}, "
          f"sections={sec_counts}{md_note})")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
