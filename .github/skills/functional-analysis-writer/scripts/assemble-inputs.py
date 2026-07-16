#!/usr/bin/env python3
"""Deterministic per-FA-section bundle packager for `functional-analysis-writer`.

For ONE source file + ONE FA section spec, loads:
  - the section spec from the chosen FA profile's `profile.yaml`
  - a section-scoped slice of `docs/_shared/<file>/facts.json`
  - a heading-matched excerpt from `docs/en/<file>/complete.md` (when present)
  - the `.mmd` source for every diagram listed in `section.embed_diagrams`
  - the template snippet matching the section heading from
    `template.md` / `template.<lang>.md`
  - front-matter values derived from `facts.json`

…and emits a single deterministic JSON bundle (with a sibling `.md` view) that
the per-section authoring agent feeds to its LLM call.

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
SOURCES_YAML = REPO_ROOT / "config" / "sources.yaml"
DEFAULT_DOC_ROOT = REPO_ROOT / "docs" / "_shared"

sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))
import fa_profile_resolver as fpr  # noqa: E402

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_MISSING_PREREQ = 4
EXIT_STALE = 5

# Section id -> facts.json keys to embed in `facts_slice`. Sections not listed
# here get a generic slice (program identity + cross-references summary).
SECTION_FACTS_KEYS: dict[str, tuple[str, ...]] = {
    # default
    "scopo-ambito":              ("program_id", "business_purpose", "incoming_xref", "calls"),
    "analisi-processi":          ("program_id", "business_purpose", "performs", "calls", "exec_cics"),
    "processi-business":         ("performs", "calls", "exec_cics", "jcl_steps", "cl_commands"),
    "elenco-funzionalita":       ("paragraphs", "sections", "business_rules"),
    "interfacce-utente":         ("exec_cics", "bms_maps", "bms_maps_used"),
    "ui-standard":               ("bms_maps", "bms_maps_used"),
    "mappa-navigazione":         ("exec_cics", "bms_maps_used"),
    "profili-protezione-dati":   ("security_controls", "exec_sql"),
    "impianto-dati-storicizzazione": ("data_records", "exec_sql", "files"),
    "gestione-stati":            ("paragraphs", "performs", "go_tos"),
    "messaggi-notifiche":        ("exec_cics", "exec_sql", "cl_commands", "business_rules"),
    "gestione-errori":           (
        "exec_sql", "exec_cics", "cl_commands", "go_tos", "business_rules",
    ),
    "vincoli-dipendenze":        ("incoming_xref", "calls", "copybooks", "exec_sql"),
    "modello-concettuale-dati":  ("data_records", "exec_sql", "files"),
    "open-points":               ("open_questions", "confidence_low"),
    # default
    "sistemi-e-ruoli":           ("program_id", "incoming_xref", "calls"),
    "flussi-input":              ("files", "jcl_steps", "cl_commands", "exec_sql"),
    "flussi-input-overview":     ("files", "jcl_steps", "cl_commands"),
    "focus-elaborazioni":        ("business_rules", "performs", "exec_sql"),
    "tipologie-record":          ("data_records", "files"),
    # default profile
    "header":                    ("program_id", "business_purpose"),
}

# Diagram kind -> filename under docs/_shared/<file>/diagrams/.
DIAGRAM_FILE_BY_KIND: dict[str, str] = {
    "call-graph":     "call-graph.mmd",
    "control-flow":   "control-flow.mmd",
    "jcl-steps":      "jcl-steps.mmd",
    "cl-command-flow":"cl-command-flow.mmd",
    "cics-calls":     "cics-calls.mmd",
    "cursor-lifecycle": "cursor-lifecycle.mmd",
    "er-fragment":    "er-fragment.mmd",
    "navigation-map": "cics-calls.mmd",   # CICS XCTL/RETURN flows
    "state-machine":  "control-flow.mmd",
    "data-flow":      "jcl-steps.mmd",
    "data-flow-input":  "jcl-steps.mmd",
    "data-flow-output": "jcl-steps.mmd",
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


def find_section(profile: dict, section_id: str) -> dict:
    for spec in fpr.flatten_sections(profile):
        if spec.get("id") == section_id:
            return spec
    raise SystemExit(f"ERROR: section id not found in profile: {section_id!r}")


def slice_facts(facts: dict, section_id: str) -> dict:
    keys = SECTION_FACTS_KEYS.get(section_id, ("program_id", "business_purpose", "incoming_xref", "calls"))
    out: dict = {}
    for k in keys:
        if k in facts:
            out[k] = facts[k]
    # always include lightweight program identity for context
    for k in ("program_id", "source_path", "source_kind"):
        if k in facts and k not in out:
            out[k] = facts[k]
    return out


def heading_excerpt(complete_md: str, section_number: str | None,
                    section_title: str | None) -> str:
    """Extract the heading-matched slice of `complete.md` for one FA section.

    The match is anchored on an H1/H2/H3 line that contains either the section
    number (e.g. "5.1") or the section title (case-insensitive). The excerpt
    runs from the matched heading up to the next heading of equal-or-higher
    level, capped at 12000 chars.
    """
    if not complete_md:
        return ""
    lines = complete_md.splitlines()
    needles: list[str] = []
    if section_number:
        needles.append(re.escape(str(section_number).strip()))
    if section_title:
        needles.append(re.escape(section_title.strip().lower()))
    if not needles:
        return ""
    start = -1
    start_level = 0
    for i, line in enumerate(lines):
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if not m:
            continue
        level = len(m.group(1))
        text = m.group(2).strip().lower()
        for n in needles:
            if re.search(rf"\b{n}\b", text):
                start = i
                start_level = level
                break
        if start >= 0:
            break
    if start < 0:
        return ""
    end = len(lines)
    for j in range(start + 1, len(lines)):
        m = re.match(r"^(#{1,6})\s+", lines[j])
        if m and len(m.group(1)) <= start_level:
            end = j
            break
    excerpt = "\n".join(lines[start:end]).strip()
    if len(excerpt) > 12000:
        excerpt = excerpt[:12000].rstrip() + "\n\n…(truncated)"
    return excerpt


def template_snippet(template_text: str, section_number: str | None,
                     section_title: str | None) -> str:
    """Extract the matching `## N. Title` block from a template file.

    Anchors on the heading matching the section_number / section_title. Falls
    back to a placeholder-only snippet (e.g. `{{ERRORI_TABLE}}` block) when the
    heading is not found.
    """
    return heading_excerpt(template_text, section_number, section_title)


def collect_diagrams(diagram_dir: Path, kinds: list[str]) -> list[dict]:
    out: list[dict] = []
    for kind in kinds:
        fname = DIAGRAM_FILE_BY_KIND.get(kind)
        if not fname:
            continue
        p = diagram_dir / fname
        if not p.exists():
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        out.append({
            "kind": kind,
            "path": rel(p),
            "source": text,
            "sha256": sha256_bytes(text.encode("utf-8")),
        })
    return out


def front_matter_values(facts: dict, profile: dict, source_path: Path) -> dict:
    fm = profile.get("front_matter") or {}
    program_id = facts.get("program_id") or source_path.stem
    src_bytes = source_path.read_bytes() if source_path.exists() else b""
    sha = sha256_bytes(src_bytes) if src_bytes else ""
    line_count = src_bytes.decode("utf-8", errors="replace").count("\n") + 1 if src_bytes else 0
    return {
        "ACRONYM": program_id,
        "SSA": fm.get("ssa_field") or program_id[:2] if program_id else "",
        "INTERFACE_NAME": program_id,
        "PROGRAM_ID": program_id,
        "CLASSIFICATION": (fm.get("classification") or {}).get("default", ""),
        "AUTHORIZED_OFFICE": fm.get("authorized_office", ""),
        "AUTHOR": "",
        "VERSION": "1.0",
        "CREATION_DATE": "",
        "STATE": (fm.get("state_options") or ["DRAFT"])[0] if fm.get("state_options") else "DRAFT",
        "TEMPLATE_VERSION": fm.get("template_version", ""),
        "ATE_LINK": "",
        "EPIC_LINK": "",
        "TITLE": program_id,
        "SOURCE_PATH": rel(source_path) if source_path.exists() else str(source_path),
        "SHA256": sha,
        "ENCODING": "auto",
        "LINE_COUNT": line_count,
        "GENERATED_AT": "",
        "LANG": "",
        "SIBLING_LINK": "",
    }


def render_md_view(bundle: dict) -> str:
    section = bundle["section"]
    out: list[str] = []
    out.append(f"# FA Bundle: {section.get('id')}")
    out.append("")
    out.append(
        "> Derived view of the bundle JSON. The `.json` sibling is authoritative — "
        "qa-reviewer, SHAs and downstream tooling read it, not this file. Do not edit by hand."
    )
    out.append("")
    out.append("## Metadata")
    out.append("")
    out.append("| key | value |")
    out.append("|---|---|")
    for k in ("bundle_version", "scope", "source_path", "source_kind", "source_platform", "profile_name",
              "profile_path", "profile_sha", "template_path", "template_sha",
              "facts_slice_sha", "chunk_excerpt_sha"):
        out.append(f"| `{k}` | {bundle.get(k, '')} |")
    out.append(f"| `section.id` | {section.get('id')} |")
    out.append(f"| `section.number` | {section.get('number', '')} |")
    out.append(f"| `section.title` | {section.get('title', '')} |")
    out.append(f"| `languages` | {', '.join(bundle.get('languages') or [])} |")
    out.append("")
    out.append("## Output paths")
    out.append("")
    for lang, p in (bundle.get("output_paths") or {}).items():
        out.append(f"- **{lang}** → `{p}`")
    out.append("")
    out.append("## Section spec")
    out.append("")
    out.append("```yaml")
    out.append(yaml.safe_dump(section, sort_keys=False, allow_unicode=True).rstrip())
    out.append("```")
    out.append("")
    out.append("## Front-matter values")
    out.append("")
    out.append("| key | value |")
    out.append("|---|---|")
    for k, v in (bundle.get("front_matter_values") or {}).items():
        out.append(f"| `{k}` | {v} |")
    out.append("")
    out.append("## Facts slice")
    out.append("")
    out.append("```json")
    out.append(json.dumps(bundle.get("facts_slice") or {}, indent=2, ensure_ascii=False))
    out.append("```")
    out.append("")
    out.append("## Narrative excerpt (from EN complete.md)")
    out.append("")
    excerpt = bundle.get("chunk_excerpt") or ""
    if excerpt:
        out.append(excerpt)
    else:
        out.append("_(none — no matching heading found in complete.md)_")
    out.append("")
    out.append("## Diagrams")
    out.append("")
    diagrams = bundle.get("diagrams") or []
    if not diagrams:
        out.append("_(none — section.embed_diagrams empty or sources missing)_")
    else:
        for d in diagrams:
            out.append(f"### {d['kind']} — `{d['path']}`")
            out.append("")
            out.append("```mermaid")
            out.append(d["source"].rstrip())
            out.append("```")
            out.append("")
    out.append("## Template snippet")
    out.append("")
    snippet = bundle.get("template_snippet") or ""
    if snippet:
        out.append("```markdown")
        out.append(snippet)
        out.append("```")
    else:
        out.append(f"_(no matching heading in template; see `{bundle.get('template_path')}`)_")
    out.append("")
    out.append("## Profile")
    out.append("")
    out.append(f"Profile policy: [`{bundle.get('profile_path')}`]({bundle.get('profile_path')}). "
               f"`profile_sha` pins the bytes the qa-reviewer enforces.")
    out.append("")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Package one FA section bundle (deterministic).")
    ap.add_argument("--source", required=True)
    ap.add_argument("--section-id", required=True)
    ap.add_argument("--profile-name", default=None,
                    help="override the auto-detected FA profile (one of default)")
    ap.add_argument("--languages", default="en")
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--out", default=None, help="write bundle JSON to file (default: stdout)")
    ap.add_argument("--no-md-view", action="store_true")
    args = ap.parse_args()

    cfg = load_sources_yaml()
    source_root = Path(args.source_root or cfg.get("source_root", "./samples"))
    if not source_root.is_absolute():
        source_root = (REPO_ROOT / source_root).resolve()
    source_path = resolve_source(args.source, source_root)
    doc_dir = DEFAULT_DOC_ROOT / source_path.name

    facts_path = doc_dir / "facts.json"
    if not facts_path.exists():
        print(f"ERROR: missing facts.json — run phase B first: {facts_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    facts = json.loads(facts_path.read_text(encoding="utf-8"))

    if args.profile_name:
        if args.profile_name not in fpr.KNOWN_PROFILES:
            print(f"ERROR: unknown profile: {args.profile_name}", file=sys.stderr)
            return EXIT_USAGE
        profile_dir = fpr.FA_ROOT / args.profile_name
        if not profile_dir.exists():
            print(f"ERROR: profile templates not found for '{args.profile_name}' under {fpr.FA_ROOT}", file=sys.stderr)
            return EXIT_MISSING_PREREQ
        resolution = fpr.FAResolution(args.profile_name, profile_dir,
                                      f"explicit --profile-name={args.profile_name}", False)
    else:
        resolution = fpr.resolve(source_path, facts)
    if resolution.skipped:
        print(f"SKIP: {source_path.name}: {resolution.reason}")
        return EXIT_OK
    if resolution.profile_dir is None:
        print(
            f"ERROR: unable to resolve an existing FA profile directory for {source_path.name}: {resolution.reason}",
            file=sys.stderr,
        )
        return EXIT_MISSING_PREREQ
    profile_dir = resolution.profile_dir
    profile_yaml_path = profile_dir / "profile.yaml"
    profile_bytes = profile_yaml_path.read_bytes()
    profile = yaml.safe_load(profile_bytes.decode("utf-8")) or {}

    section = find_section(profile, args.section_id)

    languages = parse_languages(args.languages)
    tpl_paths = fpr.template_paths(profile_dir, languages)
    primary_tpl = tpl_paths.get("en") or next(iter(tpl_paths.values()))
    template_bytes = primary_tpl.read_bytes()
    template_text = template_bytes.decode("utf-8", errors="replace")
    snippet = template_snippet(template_text, section.get("number"), section.get("title"))

    complete_md_path = REPO_ROOT / "docs" / "en" / source_path.name / "complete.md"
    complete_md = complete_md_path.read_text(encoding="utf-8", errors="replace") if complete_md_path.exists() else ""
    excerpt = heading_excerpt(complete_md, section.get("number"), section.get("title"))

    facts_slice = slice_facts(facts, args.section_id)
    diagrams = collect_diagrams(doc_dir / "diagrams", list(section.get("embed_diagrams") or []))
    fm_values = front_matter_values(facts, profile, source_path)

    output_paths: dict[str, str] = {}
    for lang in languages:
        out_md = doc_dir / "_fa-sections" / lang / f"{args.section_id}.md"
        output_paths[lang] = rel(out_md)

    bundle = {
        "bundle_version":   "1.0",
        "scope":            "per-section",
        "source_path":      rel(source_path),
        "source_kind":      facts.get("source_kind", source_path.suffix.lstrip(".").lower() or "cobol"),
        "source_platform":  facts.get("source_platform", "mainframe"),
        "profile_name":     resolution.profile,
        "profile_path":     rel(profile_yaml_path),
        "profile":          profile,
        "profile_sha":      sha256_bytes(profile_bytes),
        "section":          section,
        "facts_slice":      facts_slice,
        "facts_slice_sha":  canonical_json_sha(facts_slice),
        "chunk_excerpt":    excerpt,
        "chunk_excerpt_sha": sha256_bytes(excerpt.encode("utf-8")),
        "template_path":    rel(primary_tpl),
        "template_paths_per_language": {l: rel(p) for l, p in tpl_paths.items()},
        "template_snippet": snippet,
        "template_sha":     sha256_bytes(template_bytes),
        "diagrams":         diagrams,
        "front_matter_values": fm_values,
        "languages":        languages,
        "output_paths":     output_paths,
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
            md_path = out_path.with_suffix(".md")
            md_path.write_text(render_md_view(bundle), encoding="utf-8")
            md_note = f", md_view={md_path.name}"
        print(
            f"OK: FA bundle written to {out_path} "
            f"(section={args.section_id}, profile={resolution.profile}, "
            f"languages={','.join(languages)}, "
            f"template_sha={bundle['template_sha'][:8]}, "
            f"slice_sha={bundle['facts_slice_sha'][:8]}{md_note})"
        )
    else:
        sys.stdout.write(payload)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
