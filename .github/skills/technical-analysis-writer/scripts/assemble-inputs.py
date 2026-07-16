#!/usr/bin/env python3
"""Deterministic per-file technical-analysis (ATE) bundle packager.

SIMPLE single-pass finalizer input. For ONE source file it loads:
  - the EN consolidated documentation `docs/en/<file>/complete.md`
    (the SINGLE narrative source the writer draws from),
  - the resolved technical-analysis profile + per-language template,
  - front-matter values derived from `docs/_shared/<file>/facts.json`,
and emits a single bundle the `technical-analysis-writer` agent feeds to
its LLM call to author `docs/<lang>/<file>/technical-analysis.md`.

NO LLM CALLS. Fully deterministic.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util as _ilu
import json
import sys
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SKILL_ROOT.parents[2]
SOURCES_YAML = REPO_ROOT / "config" / "sources.yaml"
DOC_SHARED = REPO_ROOT / "docs" / "_shared"

sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))
import ta_profile_resolver as tpr  # noqa: E402

# Reuse the FA writer's front-matter helper so values stay byte-identical
# across the requirements / functional-analysis / technical-analysis families.
_FA_WRITER = REPO_ROOT / ".github" / "skills" / "functional-analysis-writer" / "scripts"
_spec = _ilu.spec_from_file_location("_fa_writer_assembler", _FA_WRITER / "assemble-inputs.py")
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
    rest = [p for p in parts if p != "en"]
    return ["en", *rest]


def rel(p: Path) -> str:
    return str(p.resolve().relative_to(REPO_ROOT)).replace("\\", "/")


def render_md_view(bundle: dict) -> str:
    out: list[str] = []
    out.append(f"# Technical-Analysis Bundle: {Path(bundle['source_path']).name}")
    out.append("")
    out.append("> Derived view of the bundle JSON. The `.json` sibling is authoritative.")
    out.append("")
    out.append("## Metadata")
    out.append("")
    out.append("| key | value |")
    out.append("|---|---|")
    for k in ("bundle_version", "scope", "source_path", "source_kind", "source_platform",
              "manifest_sha", "profile_name", "profile_path", "profile_sha",
              "complete_md_path", "complete_md_sha"):
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
    out.append("## Narrative source — EN complete.md")
    out.append("")
    out.append("```markdown")
    out.append((bundle.get("complete_md") or "").rstrip())
    out.append("```")
    out.append("")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Package the per-file technical-analysis bundle.")
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
    doc_dir = DOC_SHARED / source_path.name

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

    bundles_dir = doc_dir / "_ta-bundles"

    # Profile resolution — copybooks / BMS are tombstoned (no ATE document).
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
        resolution = tpr.resolve(source_path, facts)
    if resolution.skipped:
        bundles_dir.mkdir(parents=True, exist_ok=True)
        (bundles_dir / "_skipped.json").write_text(
            json.dumps({"source": rel(source_path), "reason": resolution.reason}, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"SKIP: {source_path.name}: {resolution.reason}")
        return EXIT_OK
    if resolution.profile_dir is None:
        print(
            f"ERROR: unable to resolve an existing TA profile directory for {source_path.name}: {resolution.reason}",
            file=sys.stderr,
        )
        return EXIT_MISSING_PREREQ

    # Phase-E prerequisite: the EN consolidated doc.
    complete_md_path = REPO_ROOT / "docs" / "en" / source_path.name / "complete.md"
    if not complete_md_path.exists():
        print(f"ERROR: missing complete.md (run phase E first): {complete_md_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    complete_md = complete_md_path.read_text(encoding="utf-8", errors="replace")

    profile_yaml_path = resolution.profile_dir / "profile.yaml"
    profile_bytes = profile_yaml_path.read_bytes()
    profile = yaml.safe_load(profile_bytes.decode("utf-8")) or {}

    languages = parse_languages(args.languages)
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
        lang: rel(REPO_ROOT / "docs" / lang / source_path.name / "technical-analysis.md")
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
        "templates":           templates,
        "complete_md_path":    rel(complete_md_path),
        "complete_md_sha":     sha256_bytes(complete_md.encode("utf-8")),
        "complete_md":         complete_md,
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
    print(f"OK: technical-analysis bundle written to {out_path} "
          f"(profile={resolution.profile}, languages={','.join(languages)}{md_note})")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
