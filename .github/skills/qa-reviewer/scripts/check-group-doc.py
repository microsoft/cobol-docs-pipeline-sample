#!/usr/bin/env python3
"""Mechanical QA checks for phase-I group documentation.

For ONE group + language, reads:
  - docs/_shared/_groups/<gid>/_doc-bundles/_finalize.bundle.json (authoritative)
  - docs/<lang>/_groups/<gid>/index.md
  - docs/<lang>/_groups/<gid>/complete.md

Emits a findings[] JSON sidecar at
  docs/_reviews/group-doc/<gid>__<lang>.json

NO LLM CALLS. Fully deterministic.

Exit codes:
  0  ok=true, no error findings
  1  ok=false, >= 1 error finding (sidecar still written)
  4  missing prerequisite (bundle or markdown not found)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SKILL_ROOT.parents[2]
DEFAULT_REVIEW_ROOT = REPO_ROOT / "docs" / "_reviews" / "group-doc"

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_MISSING_PREREQ = 4

SEVERITY_ORDER = {"error": 0, "warn": 1, "info": 2}

INLINE_FILE_TAG_RE = re.compile(r"\[FILE:[^\]]+\]")
FORBIDDEN_TODO_RE = re.compile(r"\b(TBD|TODO|FIXME)\b")
ANCHOR_HTML_RE = re.compile(r'<a\s+(?:id|name)\s*=\s*"([^"]+)"', re.IGNORECASE)
ANCHOR_MD_RE = re.compile(r"\{#([A-Za-z0-9_\-:.]+)\}")
H2_RE = re.compile(r"^##\s+", re.MULTILINE)


def add_finding(findings: list[dict], code: str, severity: str,
                section: str | None, line: int | None, message: str) -> None:
    findings.append({
        "code": code,
        "severity": severity,
        "section": section or "",
        "line": int(line or 0),
        "message": message,
    })


def sort_findings(findings: list[dict]) -> list[dict]:
    return sorted(findings, key=lambda f: (SEVERITY_ORDER.get(f["severity"], 9), f["line"], f["code"]))


def collect_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    for m in ANCHOR_HTML_RE.finditer(text):
        anchors.add(m.group(1).lower())
    for m in ANCHOR_MD_RE.finditer(text):
        anchors.add(m.group(1).lower())
    return anchors


def check_members(index_text: str, complete_text: str, bundle: dict,
                  findings: list[dict]) -> None:
    members = bundle.get("members") or []
    if not members:
        add_finding(findings, "GROUP_NO_MEMBERS", "error", None, 0,
                    "Bundle declares zero members.")
        return
    lower_index = index_text.lower()
    positions: list[tuple[int, str]] = []
    for m in members:
        basename = m["basename"]
        idx = lower_index.find(basename.lower())
        if idx < 0:
            add_finding(findings, "MEMBER_MISSING_IN_INDEX", "error", "Members", 0,
                        f"Member {basename!r} not referenced in index.md.")
        else:
            positions.append((idx, basename))
    sorted_by_pos = [b for _, b in sorted(positions)]
    declared = [m["basename"] for m in members if any(b == m["basename"] for _, b in positions)]
    if sorted_by_pos != declared:
        add_finding(findings, "MEMBER_ORDER_MISMATCH", "error", "Members", 0,
                    f"Member order in index.md ({sorted_by_pos}) does not match grouping.yaml ({declared}).")
    anchors = collect_anchors(complete_text)
    lower_complete = complete_text.lower()
    for m in members:
        basename_lower = m["basename"].lower()
        toc = m.get("toc") or []
        if not toc:
            if basename_lower not in lower_complete:
                add_finding(findings, "MEMBER_MISSING_IN_COMPLETE", "error", "Complete", 0,
                            f"Member {m['basename']!r} not present in complete.md.")
            continue
        found_any = False
        for c in toc:
            cid = (c.get("chunk_id") or "").lower()
            if not cid:
                continue
            expected = f"{basename_lower}__{cid}"
            if expected in anchors or expected in lower_complete:
                found_any = True
                break
        if not found_any:
            add_finding(findings, "MEMBER_ANCHOR_MISSING", "warn", "Complete", 0,
                        f"complete.md has no stable anchor for member {m['basename']!r} "
                        f"(expected `<basename>__<section-id>`).")


def check_no_inline_tags(text: str, section: str, findings: list[dict]) -> None:
    for tag in INLINE_FILE_TAG_RE.findall(text)[:5]:
        add_finding(findings, "INLINE_FILE_TAG", "error", section, 0,
                    f"Forbidden inline citation tag: {tag!r}.")


def check_no_todo_in_tldr(index_text: str, findings: list[dict]) -> None:
    # Canonical heading is `## Summary`; `## TL;DR` accepted as legacy alias.
    m = re.search(r"^##\s+(?:Summary|TL;DR)\s*$", index_text, flags=re.MULTILINE | re.IGNORECASE)
    if not m:
        add_finding(findings, "TLDR_MISSING", "warn", "Summary", 0,
                    "No `## Summary` block found in index.md.")
        return
    rest = index_text[m.end():]
    n = H2_RE.search(rest)
    body = rest[: n.start()] if n else rest
    for tk in set(FORBIDDEN_TODO_RE.findall(body)):
        add_finding(findings, "TLDR_FORBIDDEN_TOKEN", "error", "Summary", 0,
                    f"Summary contains forbidden token: {tk!r}.")


def main() -> int:
    ap = argparse.ArgumentParser(description="Mechanical QA for phase-I group docs.")
    ap.add_argument("--group-id", required=True)
    ap.add_argument("--language", default="en")
    ap.add_argument("--bundle", default=None)
    ap.add_argument("--json-out", default=None)
    ap.add_argument("--no-write", action="store_true")
    args = ap.parse_args()

    bundle_path = Path(args.bundle) if args.bundle else (
        REPO_ROOT / "docs" / "_shared" / "_groups" / args.group_id /
        "_doc-bundles" / "_finalize.bundle.json"
    )
    if not bundle_path.is_absolute():
        bundle_path = (REPO_ROOT / bundle_path).resolve()
    if not bundle_path.exists():
        print(f"ERROR: bundle not found: {bundle_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))

    lang = args.language
    index_path = REPO_ROOT / "docs" / lang / "_groups" / args.group_id / "index.md"
    complete_path = REPO_ROOT / "docs" / lang / "_groups" / args.group_id / "complete.md"
    if not index_path.exists():
        print(f"ERROR: group index.md not found: {index_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    if not complete_path.exists():
        print(f"ERROR: group complete.md not found: {complete_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    index_text = index_path.read_text(encoding="utf-8", errors="replace")
    complete_text = complete_path.read_text(encoding="utf-8", errors="replace")

    findings: list[dict] = []
    check_members(index_text, complete_text, bundle, findings)
    check_no_inline_tags(index_text, "index.md", findings)
    check_no_inline_tags(complete_text, "complete.md", findings)
    check_no_todo_in_tldr(index_text, findings)

    findings = sort_findings(findings)
    errors = [f for f in findings if f["severity"] == "error"]
    warnings = [f for f in findings if f["severity"] == "warn"]

    sidecar = {
        "schema_version": "1.0",
        "group_id": args.group_id,
        "language": lang,
        "bundle_path": str(bundle_path.relative_to(REPO_ROOT)).replace("\\", "/"),
        "index_path": f"docs/{lang}/_groups/{args.group_id}/index.md",
        "complete_path": f"docs/{lang}/_groups/{args.group_id}/complete.md",
        "members_sha": bundle.get("members_sha"),
        "ok": len(errors) == 0,
        "findings": findings,
        "summary": {"errors": len(errors), "warnings": len(warnings)},
    }

    out_path = Path(args.json_out) if args.json_out else (
        DEFAULT_REVIEW_ROOT / f"{args.group_id}__{lang}.json"
    )
    if not out_path.is_absolute():
        out_path = (REPO_ROOT / out_path).resolve()

    if not args.no_write:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(
            json.dumps(sidecar, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(
            f"OK: review sidecar at {out_path.relative_to(REPO_ROOT)} "
            f"(errors={len(errors)}, warnings={len(warnings)})"
        )
    else:
        sys.stdout.write(json.dumps(sidecar, ensure_ascii=False, indent=2) + "\n")

    return EXIT_OK if len(errors) == 0 else EXIT_FAIL


if __name__ == "__main__":
    sys.exit(main())
