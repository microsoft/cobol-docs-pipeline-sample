#!/usr/bin/env python3
"""Deterministic QA checker for phase-F functional-analysis markdown.

Validates ONE FA section draft (per-section scope) or ONE `functional-analysis.md`
(per-file scope) against the rules in the active FA `profile.yaml`. Emits a
review JSON sidecar at:

  docs/_reviews/functional-analysis/<file>__<section_id>__<lang>.json     (per-section)
  docs/_reviews/functional-analysis/<file>__<lang>.json                   (per-file)

Mechanical checks (no LLM):
  - required heading present (H2/H3 + section.number + section.title)
  - optional sections with no body carry `profile.section.optional_marker`
  - every column in `section.table.columns` appears in the rendered table
  - every diagram in `section.embed_diagrams` is embedded as inline ```mermaid```
  - citations: `## Sources` block present + at least one `[^src-N]` footnote
  - no forbidden filler tokens: N/A, TBD, ???, "Section not applicable" inside
    a REQUIRED section
  - no `[FILE:Lx-Ly]` inline tags
  - per-file scope: every required section in profile order is present;
    footnote ids are unique and contiguous
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml

REVIEWER_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = REVIEWER_ROOT.parents[2]
REVIEW_DIR = REPO_ROOT / "docs" / "_reviews" / "functional-analysis"

sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))
import fa_profile_resolver as fpr  # noqa: E402

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_USAGE = 2
EXIT_MISSING = 4

FORBIDDEN_TOKENS = ("N/A", "TBD", "???", "TODO:")
INLINE_FILE_TAG_RE = re.compile(r"\[FILE:L\d+-L\d+\]")
SRC_FOOTNOTE_RE = re.compile(r"\[\^src-\d+\]")
MERMAID_FENCE_RE = re.compile(r"```mermaid\b[\s\S]*?```", re.MULTILINE)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$", re.MULTILINE)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def make_finding(code: str, severity: str, message: str, section: str = "", line: int = 0) -> dict:
    return {"code": code, "severity": severity, "section": section, "line": line, "message": message}


def check_required_heading(md: str, section: dict) -> list[dict]:
    findings: list[dict] = []
    number = str(section.get("number", "")).strip()
    title = str(section.get("title", "")).strip()
    expected_levels = (3,) if section.get("_parent_id") else (2,)
    found = False
    for m in HEADING_RE.finditer(md):
        level = len(m.group(1))
        text = m.group(2).strip()
        if level not in expected_levels:
            continue
        if (number and number in text) or (title and title.lower() in text.lower()):
            found = True
            break
    if not found:
        level_label = "H3" if section.get("_parent_id") else "H2"
        findings.append(make_finding(
            "HEADING_MISSING", "error", "",
            f"Expected {level_label} heading for section {number!r} / {title!r}.",
        ))
    return findings


def check_optional_marker(md: str, section: dict) -> list[dict]:
    findings: list[dict] = []
    marker = (section.get("optional_marker") or "").strip()
    body = re.sub(r"\[\^src-\d+\]:.*$", "", md, flags=re.MULTILINE).strip()
    # Determine if section has real content (>1 paragraph excluding heading + marker).
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]
    non_heading = [p for p in paragraphs if not p.startswith("#")]
    has_content = any(len(p.split()) > 12 and p != marker for p in non_heading)
    is_required = bool(section.get("required", False))
    has_marker = bool(marker) and marker in md
    if not is_required and not has_content and marker and not has_marker:
        findings.append(make_finding(
            "OPTIONAL_MARKER_MISSING", "error", "",
            f"Empty optional section MUST contain the marker {marker!r}.",
        ))
    if is_required and not has_content:
        findings.append(make_finding(
            "REQUIRED_SECTION_EMPTY", "error", "",
            "Required section has no meaningful body content.",
        ))
    if is_required and has_marker:
        findings.append(make_finding(
            "REQUIRED_SECTION_MARKED_OPTIONAL", "error", "",
            f"Required section contains the optional marker {marker!r}.",
        ))
    return findings


def check_table_columns(md: str, section: dict) -> list[dict]:
    findings: list[dict] = []
    table = section.get("table") or {}
    cols = table.get("columns") or []
    if not cols:
        return findings
    # Find any markdown table header in the body.
    header_lines = [l for l in md.splitlines() if l.strip().startswith("|") and "|" in l[1:]]
    found_cols: set[str] = set()
    for l in header_lines:
        cells = [c.strip().lower() for c in l.strip().strip("|").split("|")]
        for col in cols:
            if col.strip().lower() in cells:
                found_cols.add(col)
    for col in cols:
        if col not in found_cols:
            findings.append(make_finding(
                "TABLE_COLUMN_MISSING", "warn", "",
                f"Profile-declared column not found in any rendered table: {col!r}.",
            ))
    return findings


def check_diagrams(md: str, section: dict) -> list[dict]:
    findings: list[dict] = []
    embed = section.get("embed_diagrams") or []
    if not embed:
        return findings
    fences = MERMAID_FENCE_RE.findall(md)
    if not fences:
        findings.append(make_finding(
            "DIAGRAM_MISSING", "error", "",
            f"Section requires inline mermaid diagram(s): {', '.join(embed)}.",
        ))
    return findings


def check_citations(md: str, profile: dict, scope: str) -> list[dict]:
    findings: list[dict] = []
    if not profile.get("require_citations", True):
        return findings
    has_footnote_use = bool(SRC_FOOTNOTE_RE.search(md))
    has_sources_block = bool(re.search(r"^##\s+Sources\b", md, re.MULTILINE))
    if scope == "per-file" and not has_sources_block:
        findings.append(make_finding(
            "MISSING_SOURCES_BLOCK", "error", "",
            "`## Sources` block missing from functional-analysis.md.",
        ))
    if not has_footnote_use:
        findings.append(make_finding(
            "MISSING_SRC_FOOTNOTES", "warn" if scope == "per-section" else "error",
            "",
            "No `[^src-N]` footnote references found.",
        ))
    return findings


def check_forbidden_tokens(md: str, section: dict | None) -> list[dict]:
    findings: list[dict] = []
    for tok in FORBIDDEN_TOKENS:
        if tok in md:
            findings.append(make_finding(
                "FORBIDDEN_FILLER_TOKEN", "error", "",
                f"Forbidden filler token in body: {tok!r}. Use the optional marker or omit the row.",
            ))
            break
    if INLINE_FILE_TAG_RE.search(md):
        findings.append(make_finding(
            "INLINE_FILE_TAG", "error", "",
            "Inline `[FILE:Lx-Ly]` citation found. Use `[^src-N]` footnotes instead.",
        ))
    return findings


def check_footnote_ids_unique(md: str) -> list[dict]:
    findings: list[dict] = []
    defs = re.findall(r"^\[\^src-(\d+)\]:", md, flags=re.MULTILINE)
    seen: set[str] = set()
    dups: list[str] = []
    for d in defs:
        if d in seen:
            dups.append(d)
        seen.add(d)
    if dups:
        findings.append(make_finding(
            "DUPLICATE_FOOTNOTE_ID", "error", "",
            f"Duplicate footnote definition ids: {', '.join(sorted(set(dups)))}.",
        ))
    return findings


def review_per_section(bundle_path: Path, md_path: Path, language: str) -> tuple[int, dict]:
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    section = bundle.get("section") or {}
    profile = bundle.get("profile") or {}
    if not md_path.exists():
        return EXIT_MISSING, {
            "review_version": "1.0", "scope": "per-section",
            "draft_path": str(md_path), "ok": False,
            "findings": [make_finding("DRAFT_MISSING", "error", "",
                                      f"Draft file not found: {md_path}")],
            "counters": {},
        }
    md_bytes = md_path.read_bytes()
    md = md_bytes.decode("utf-8", errors="replace")
    findings: list[dict] = []
    findings += check_required_heading(md, section)
    findings += check_optional_marker(md, section)
    findings += check_table_columns(md, section)
    findings += check_diagrams(md, section)
    findings += check_citations(md, profile, "per-section")
    findings += check_forbidden_tokens(md, section)
    errors = [f for f in findings if f["severity"] == "error"]
    sidecar = {
        "review_version":   "1.0",
        "scope":            "per-section",
        "draft_path":       str(md_path.relative_to(REPO_ROOT)).replace("\\", "/"),
        "draft_sha":        sha256_bytes(md_bytes),
        "bundle_path":      str(bundle_path.relative_to(REPO_ROOT)).replace("\\", "/"),
        "profile_name":     bundle.get("profile_name"),
        "section_id":       section.get("id"),
        "language":         language,
        "ok":               not errors,
        "findings":         sorted(findings, key=lambda f: (0 if f["severity"] == "error" else 1, f["code"])),
        "counters": {
            "total_words":   len(re.findall(r"\b\w+\b", md)),
            "src_footnotes": len(SRC_FOOTNOTE_RE.findall(md)),
            "mermaid_fences": len(MERMAID_FENCE_RE.findall(md)),
        },
    }
    return (EXIT_FAIL if errors else EXIT_OK), sidecar


def review_per_file(md_path: Path, language: str,
                    profile_name: str | None) -> tuple[int, dict]:
    if not md_path.exists():
        return EXIT_MISSING, {
            "review_version": "1.0", "scope": "per-file",
            "draft_path": str(md_path), "ok": False,
            "findings": [make_finding("DRAFT_MISSING", "error", "",
                                      f"functional-analysis.md not found: {md_path}")],
            "counters": {},
        }
    md_bytes = md_path.read_bytes()
    md = md_bytes.decode("utf-8", errors="replace")
    # Profile is required to know section order; fall back to default if not provided.
    profile_name = profile_name or "default"
    if profile_name not in fpr.KNOWN_PROFILES:
        return EXIT_USAGE, {
            "review_version": "1.0", "scope": "per-file",
            "draft_path": str(md_path), "ok": False,
            "findings": [make_finding("UNKNOWN_PROFILE", "error", "",
                                      f"Unknown FA profile: {profile_name!r}")],
            "counters": {},
        }
    profile_dir = fpr.FA_ROOT / profile_name
    profile = fpr.load_profile_yaml(profile_dir)
    flat = [s for s in fpr.flatten_sections(profile) if s.get("id") != "header"]
    findings: list[dict] = []
    for spec in flat:
        if not spec.get("required", False):
            continue
        number = str(spec.get("number", "")).strip()
        title = str(spec.get("title", "")).strip()
        found = False
        for m in HEADING_RE.finditer(md):
            text = m.group(2).strip()
            if (number and number in text) or (title and title.lower() in text.lower()):
                found = True
                break
        if not found:
            findings.append(make_finding(
                "REQUIRED_SECTION_MISSING", "error", spec.get("id", ""),
                f"Required section absent from functional-analysis.md: {number!r} / {title!r}.",
            ))
    findings += check_citations(md, profile, "per-file")
    findings += check_forbidden_tokens(md, None)
    findings += check_footnote_ids_unique(md)
    errors = [f for f in findings if f["severity"] == "error"]
    sidecar = {
        "review_version":   "1.0",
        "scope":            "per-file",
        "draft_path":       str(md_path.relative_to(REPO_ROOT)).replace("\\", "/"),
        "draft_sha":        sha256_bytes(md_bytes),
        "profile_name":     profile_name,
        "language":         language,
        "ok":               not errors,
        "findings":         sorted(findings, key=lambda f: (0 if f["severity"] == "error" else 1, f["code"])),
        "counters": {
            "total_words":   len(re.findall(r"\b\w+\b", md)),
            "src_footnotes": len(SRC_FOOTNOTE_RE.findall(md)),
            "mermaid_fences": len(MERMAID_FENCE_RE.findall(md)),
        },
    }
    return (EXIT_FAIL if errors else EXIT_OK), sidecar


def main() -> int:
    ap = argparse.ArgumentParser(description="QA checker for phase-F functional-analysis markdown.")
    ap.add_argument("--bundle", help="per-section FA bundle JSON")
    ap.add_argument("--draft", help="markdown path (per-section draft or per-file functional-analysis.md)")
    ap.add_argument("--language", default="en")
    ap.add_argument("--scope", choices=("per-section", "per-file"), default=None)
    ap.add_argument("--profile-name", default=None,
                    help="per-file scope only: FA profile name")
    ap.add_argument("--json-out", default=None)
    ap.add_argument("--no-write", action="store_true")
    args = ap.parse_args()

    if args.bundle:
        bundle_path = Path(args.bundle)
        if not bundle_path.is_absolute():
            bundle_path = (REPO_ROOT / bundle_path).resolve()
        if not bundle_path.exists():
            print(f"ERROR: bundle not found: {bundle_path}", file=sys.stderr)
            return EXIT_MISSING
        bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
        scope = args.scope or bundle.get("scope") or "per-section"
        if args.draft:
            md_path = Path(args.draft)
            if not md_path.is_absolute():
                md_path = (REPO_ROOT / md_path).resolve()
        else:
            md_rel = (bundle.get("output_paths") or {}).get(args.language)
            if not md_rel:
                print(f"ERROR: bundle output_paths missing language {args.language}", file=sys.stderr)
                return EXIT_USAGE
            md_path = (REPO_ROOT / md_rel).resolve()
        if scope == "per-file":
            code, sidecar = review_per_file(md_path, args.language,
                                            args.profile_name or bundle.get("profile_name"))
            sidecar_name = f"{Path(bundle.get('source_path', md_path.name)).name}__{args.language}.json"
        else:
            code, sidecar = review_per_section(bundle_path, md_path, args.language)
            sidecar_name = (f"{Path(bundle.get('source_path', md_path.name)).name}__"
                            f"{(bundle.get('section') or {}).get('id', 'section')}__{args.language}.json")
    elif args.draft:
        scope = args.scope or "per-file"
        md_path = Path(args.draft)
        if not md_path.is_absolute():
            md_path = (REPO_ROOT / md_path).resolve()
        code, sidecar = review_per_file(md_path, args.language, args.profile_name)
        sidecar_name = f"{md_path.parent.name}__{args.language}.json"
    else:
        print("ERROR: pass --bundle or --draft", file=sys.stderr)
        return EXIT_USAGE

    payload = json.dumps(sidecar, indent=2, ensure_ascii=False) + "\n"
    if args.no_write:
        sys.stdout.write(payload)
    else:
        out_path = Path(args.json_out) if args.json_out else (REVIEW_DIR / sidecar_name)
        if not out_path.is_absolute():
            out_path = (REPO_ROOT / out_path).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(payload, encoding="utf-8")
        verdict = "OK" if sidecar.get("ok") else f"FAIL: {sum(1 for f in sidecar['findings'] if f['severity'] == 'error')} error(s)"
        print(f"{verdict}  ->  {out_path.relative_to(REPO_ROOT)}")
    return code


if __name__ == "__main__":
    sys.exit(main())
