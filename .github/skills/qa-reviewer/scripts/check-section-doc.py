#!/usr/bin/env python3
"""Deterministic mechanical checker for phase-C per-section markdown.

Enforces the binding authoring rules from
  - `config/templates/procedure-section-doc.template.md`
  - the active `config/templates/docs/<profile>/profile.yaml`

Emits a JSON review sidecar at
  `docs/_reviews/section-doc/<file>__<chunk_id>__<lang>.json`

NO LLM CALLS. Fully deterministic.

Exit codes:
  0  ok=true, no errors
  1  ok=false, >= 1 error finding (sidecar still written)
  4  required input missing (markdown not found or bundle unavailable)
  5  stale bundle (bundle.chunk_text_sha != re-hash of bundle.chunk_text)
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
DEFAULT_REVIEW_ROOT = REPO_ROOT / "docs" / "_reviews" / "section-doc"

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_MISSING_PREREQ = 4
EXIT_STALE = 5

SEVERITY_ORDER = {"error": 0, "warn": 1, "info": 2}

# --- Rule constants -----------------------------------------------------

TLDR_FORBIDDEN_TOKENS = [
    r"\bPERFORM\b",
    r"\bEVALUATE\b",
    r"\bWORKING-STORAGE\b",
    r"\bGO\s+TO\b",
    r"\bDECLARATIVES\b",
    # explicit line / verb count phrases
    r"\b\d+\s+lines?\b",
    r"\bline\s+\d+\b",
    r"\b\d+\s+PERFORMs?\b",
    r"\b\d+\s+CALLs?\b",
]

PURPOSE_FORBIDDEN_OPENERS = [
    r"^\s*This section contains the following",
    r"^\s*The section spans lines",
    r"^\s*This `?PROCEDURE DIVISION`? section implements the following",
    r"^\s*This `?PROCEDURE DIVISION`? section contains",
]

PURPOSE_LINE_COUNT_PROSE_PATTERNS = [
    r"\blines?\s+\d+(\s*[-\u2013\u2014]\s*\d+)?\b",
    r"\b\d+\s+lines?\b",
    r"\b\d+\s+(?:PERFORM|CALL|GO\s+TO|EVALUATE)s?\b",
    r"\bspans?\s+\d+\s+lines?\b",
]

INLINE_FILE_TAG_RE = re.compile(r"\[FILE:[^\]]+\]")
SRC_FOOTNOTE_REF_RE = re.compile(r"\[\^src-[A-Za-z0-9_-]+\]")
SOURCES_HEADING_RE = re.compile(r"^##\s+Sources\s*$", re.MULTILINE)
BANNED_BANNER_RE = re.compile(r"Self-contained document\.\s*Bundles.*?from\s+facts\.json", re.IGNORECASE | re.DOTALL)
SENTENCE_SPLIT_RE = re.compile(r"(?<=[\.!\?])\s+")
SECTION_HEADING_RE = re.compile(r"^##\s+([^\n]+?)\s*$", re.MULTILINE)
BACKTICK_RE = re.compile(r"`[^`]+`")
FOOTNOTE_INLINE_RE = re.compile(r"\[\^[^\]]+\]")
CODE_FENCE_RE = re.compile(r"```.*?```", re.DOTALL)


# --- Helpers ------------------------------------------------------------

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
    cand_repo = (REPO_ROOT / p).resolve()
    if cand_repo.exists():
        return cand_repo
    cand_root = (source_root / p).resolve()
    if cand_root.exists():
        return cand_root
    raise SystemExit(f"ERROR: source not found: {source}")


def default_doc_dir_for(source_path: Path) -> Path:
    return DEFAULT_DOC_ROOT / source_path.name


def find_chunk_filename(chunks_index: dict, chunk_id: str) -> str:
    for c in chunks_index.get("chunks") or []:
        if c.get("id") == chunk_id:
            return c["file"]
    raise SystemExit(f"ERROR: chunk_id not found in chunks/index.json: {chunk_id!r}")


def derive_md_path(source_path: Path, chunk_filename: str, language: str) -> Path:
    md_name = Path(chunk_filename).with_suffix(".md").name
    return REPO_ROOT / "docs" / language / source_path.name / "sections" / md_name


def derive_diagram_path(source_path: Path, chunk_filename: str) -> Path:
    diagram_name = f"section-{Path(chunk_filename).stem}.mmd"
    return DEFAULT_DOC_ROOT / source_path.name / "diagrams" / diagram_name


def sanitize_id_for_review_name(chunk_id: str) -> str:
    return chunk_id.replace("/", "__")


# --- Section extraction -------------------------------------------------

def extract_sections(text: str) -> dict[str, tuple[str, int]]:
    """Return {heading_text: (body, body_start_line)} for `##` H2 headings.

    Body excludes the heading line itself and runs until the next `##` heading
    or EOF. Line numbers are 1-based.
    """
    out: dict[str, tuple[str, int]] = {}
    lines = text.splitlines()
    headings: list[tuple[str, int]] = []
    for i, line in enumerate(lines, start=1):
        m = re.match(r"^##\s+([^\n]+?)\s*$", line)
        if m:
            headings.append((m.group(1).strip(), i))
    for idx, (name, ln) in enumerate(headings):
        body_start = ln + 1
        body_end = headings[idx + 1][1] - 1 if idx + 1 < len(headings) else len(lines)
        body = "\n".join(lines[body_start - 1: body_end]).strip("\n")
        out[name] = (body, body_start)
    return out


def strip_quote_blocks(body: str) -> str:
    """Drop blockquote `> …` lines (the template's authoring-rule annotations).

    The reviewer cares about the prose the author wrote, not the template's
    self-documenting `>` annotations which are intentionally retained.
    Authors are expected to leave the `>` rules in place; the reviewer
    discounts them from word/sentence counts so they do not inflate metrics.
    """
    keep = []
    for ln in body.splitlines():
        if ln.lstrip().startswith(">"):
            continue
        keep.append(ln)
    return "\n".join(keep).strip()


def strip_code_and_tables(body: str) -> str:
    """Drop fenced code blocks and markdown tables for prose counting."""
    body = CODE_FENCE_RE.sub("", body)
    keep = []
    for ln in body.splitlines():
        s = ln.strip()
        if s.startswith("|") or re.match(r"^\|?\s*[-:]+(\s*\|[-:\s]+)+\|?\s*$", s):
            continue
        keep.append(ln)
    return "\n".join(keep)


def count_sentences(text: str) -> int:
    text = text.strip()
    if not text:
        return 0
    parts = [p for p in SENTENCE_SPLIT_RE.split(text) if p.strip()]
    return max(1, len(parts)) if text.endswith((".", "!", "?")) else len(parts) or (1 if text else 0)


def count_words(text: str) -> int:
    return len(re.findall(r"\b[\w'-]+\b", text))


# --- Finding helpers ----------------------------------------------------

def add_finding(findings: list[dict], code: str, severity: str, section: str | None, line: int | None, message: str) -> None:
    findings.append({
        "code": code,
        "severity": severity,
        "section": section or "",
        "line": int(line or 0),
        "message": message,
    })


def sort_findings(findings: list[dict]) -> list[dict]:
    return sorted(findings, key=lambda f: (SEVERITY_ORDER.get(f["severity"], 9), f["line"], f["code"]))


# --- The check pipeline -------------------------------------------------

def check_tldr(sections: dict[str, tuple[str, int]], thresholds: dict, findings: list[dict]) -> int:
    # The canonical heading is `## Summary`. `## TL;DR` is accepted as a
    # legacy alias so already-approved documents keep passing the gate.
    key = "Summary" if "Summary" in sections else ("TL;DR" if "TL;DR" in sections else None)
    if key is None:
        add_finding(findings, "TLDR_MISSING", "error", "Summary", 0, "No `## Summary` block found.")
        return 0
    raw, start_line = sections[key]
    body = strip_quote_blocks(raw)
    if not body.strip():
        add_finding(findings, "TLDR_MISSING", "error", "Summary", start_line, "Summary block is empty.")
        return 0
    words = count_words(body)
    max_words = int(thresholds.get("max_tldr_words", 30))
    if words > max_words:
        add_finding(findings, "TLDR_TOO_LONG", "error", "Summary", start_line,
                    f"Summary has {words} words; max {max_words}.")
    sentences = count_sentences(body)
    if sentences > 1:
        add_finding(findings, "TLDR_MULTI_SENTENCE", "error", "Summary", start_line,
                    f"Summary contains {sentences} sentences; must be exactly 1.")
    for pat in TLDR_FORBIDDEN_TOKENS:
        m = re.search(pat, body, re.IGNORECASE)
        if m:
            add_finding(findings, "TLDR_FORBIDDEN_TOKEN", "error", "Summary", start_line,
                        f"Summary contains forbidden token: {m.group(0)!r}.")
    return words


def check_purpose(sections: dict[str, tuple[str, int]], thresholds: dict, findings: list[dict]) -> tuple[int, int]:
    if "Purpose" not in sections:
        add_finding(findings, "PURPOSE_MISSING", "error", "Purpose", 0, "No `## Purpose` block found.")
        return 0, 0
    raw, start_line = sections["Purpose"]
    body = strip_quote_blocks(raw)
    body = strip_code_and_tables(body)
    sentences = count_sentences(body)
    words = count_words(body)
    min_sentences = int(thresholds.get("min_purpose_sentences", 4))
    min_words = int(thresholds.get("min_purpose_words", 80))
    if sentences < min_sentences:
        add_finding(findings, "PURPOSE_TOO_SHORT_SENTENCES", "error", "Purpose", start_line,
                    f"Purpose has {sentences} sentences; need at least {min_sentences}.")
    if words < min_words:
        add_finding(findings, "PURPOSE_TOO_SHORT_WORDS", "error", "Purpose", start_line,
                    f"Purpose has {words} words; need at least {min_words}.")
    first_line = next((ln for ln in body.splitlines() if ln.strip()), "")
    for pat in PURPOSE_FORBIDDEN_OPENERS:
        if re.match(pat, first_line, re.IGNORECASE):
            add_finding(findings, "PURPOSE_FORBIDDEN_OPENER", "error", "Purpose", start_line,
                        f"Purpose opens with forbidden transcript-style preface: {first_line[:60]!r}.")
            break
    for pat in PURPOSE_LINE_COUNT_PROSE_PATTERNS:
        m = re.search(pat, body, re.IGNORECASE)
        if m:
            add_finding(findings, "PURPOSE_LINE_COUNT_PROSE", "error", "Purpose", start_line,
                        f"Purpose mentions structural statistics: {m.group(0)!r}.")
            break
    return sentences, words


def check_citations(full_text: str, thresholds: dict, findings: list[dict]) -> tuple[int, int]:
    # Inline [FILE:Lx-Ly] tags are always forbidden.
    inline_tags = INLINE_FILE_TAG_RE.findall(full_text)
    for tag in inline_tags[:5]:
        add_finding(findings, "INLINE_FILE_TAG", "error", None, 0,
                    f"Forbidden inline citation tag: {tag!r}; use `[^src-N]` footnotes.")
    src_refs = SRC_FOOTNOTE_REF_RE.findall(full_text)
    if thresholds.get("require_citations", True):
        if not SOURCES_HEADING_RE.search(full_text):
            add_finding(findings, "MISSING_SOURCES_BLOCK", "error", None, 0,
                        "Document has no `## Sources` block but profile requires citations.")
        if not src_refs:
            add_finding(findings, "MISSING_SRC_FOOTNOTES", "error", None, 0,
                        "Document has zero `[^src-N]` footnote references but profile requires citations.")
    return len(src_refs), len(inline_tags)


def check_banner(full_text: str, findings: list[dict]) -> None:
    m = BANNED_BANNER_RE.search(full_text)
    if m:
        add_finding(findings, "BANNED_BANNER", "error", None, 0,
                    "Document contains the forbidden 'Self-contained document. Bundles… facts.json' banner.")


def check_identifier_styling(full_text: str, regex: str, findings: list[dict]) -> None:
    if not regex:
        return
    try:
        ident_re = re.compile(regex)
    except re.error:
        return
    # Build a body view with backticked spans + code fences + footnote refs removed.
    body = CODE_FENCE_RE.sub("", full_text)
    body = BACKTICK_RE.sub("", body)
    body = FOOTNOTE_INLINE_RE.sub("", body)
    # Collect candidate tokens; skip very common English acronyms to limit noise.
    skip = {"SQL", "CICS", "DB2", "JCL", "BMS", "API", "JSON", "YAML", "URL", "HTTP", "TLD", "ID", "OK"}
    seen_unbacked: set[str] = set()
    for m in ident_re.finditer(body):
        tok = m.group(0)
        if tok in skip or len(tok) < 3:
            continue
        if tok in seen_unbacked:
            continue
        seen_unbacked.add(tok)
        if len(seen_unbacked) > 10:
            break
        add_finding(findings, "IDENTIFIER_NOT_BACKTICKED", "warn", None, 0,
                    f"Identifier {tok!r} appears in prose without backticks.")


def check_total_words(full_text: str, thresholds: dict, findings: list[dict]) -> int:
    body = strip_code_and_tables(full_text)
    body = "\n".join(ln for ln in body.splitlines() if not ln.lstrip().startswith(">"))
    n = count_words(body)
    min_total = int(thresholds.get("min_total_words", 1500))
    if n < min_total:
        add_finding(findings, "MIN_TOTAL_WORDS", "warn", None, 0,
                    f"Document has {n} words; per-file threshold is {min_total}. "
                    f"Per-section docs may legitimately be shorter — escalated to error only by the per-file reviewer.")
    return n


def check_diagram(source_path: Path, chunk_filename: str, findings: list[dict]) -> None:
    p = derive_diagram_path(source_path, chunk_filename)
    if not p.exists():
        add_finding(findings, "MISSING_DIAGRAM", "warn", None, 0,
                    f"Companion diagram not found: {p.relative_to(REPO_ROOT)}.")


XREF_IN_H3_RE = re.compile(r"^###\s+Called\s*/\s*used by\s*\(incoming\)\s*$", re.MULTILINE | re.IGNORECASE)
H3_RE = re.compile(r"^###\s+", re.MULTILINE)
XREF_EMPTY_MARKER_RE = re.compile(r"^\s*[-*]?\s*_?None\.?_?\s*$", re.IGNORECASE | re.MULTILINE)


def _extract_xref_in_block(full_text: str) -> str | None:
    """Return the body of the `### Called / used by (incoming)` H3, or None if missing."""
    m = XREF_IN_H3_RE.search(full_text)
    if not m:
        return None
    start = m.end()
    rest = full_text[start:]
    nxt = H3_RE.search(rest)
    end = nxt.start() if nxt else len(rest)
    return rest[:end].strip()


def check_xref_in(full_text: str, bundle: dict | None, findings: list[dict]) -> None:
    """Flag when bundle.facts_slice.incoming_xref is non-empty but the
    `### Called / used by (incoming)` block is missing or marked _None_.

    File-level `incoming_xref` rows (external programs / JCL steps / copybook
    consumers reaching THIS source) MUST be reproduced in every per-section
    doc for the file. An empty block in that case indicates the writer
    ignored xref data carried in the bundle.
    """
    if not bundle:
        return
    slice_obj = bundle.get("facts_slice") or {}
    incoming = slice_obj.get("incoming_xref") or []
    if not incoming:
        return
    body = _extract_xref_in_block(full_text)
    if body is None:
        add_finding(findings, "XREF_IN_MISSING_BLOCK", "error", "Cross-references", 0,
                    f"`### Called / used by (incoming)` heading is missing but bundle.facts_slice.incoming_xref "
                    f"has {len(incoming)} entries.")
        return
    # Treat a block whose only content is `_None_` / `- _None._` as empty.
    cleaned = "\n".join(ln for ln in body.splitlines() if ln.strip())
    only_none = bool(cleaned) and all(
        XREF_EMPTY_MARKER_RE.match(ln) for ln in cleaned.splitlines()
    )
    if not cleaned or only_none:
        add_finding(findings, "XREF_IN_EMPTY", "error", "Cross-references", 0,
                    f"`### Called / used by (incoming)` is empty but bundle.facts_slice.incoming_xref "
                    f"has {len(incoming)} entries — copy them verbatim into the block.")


# --- main ---------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Mechanical phase-C qa-reviewer for one section markdown.")
    ap.add_argument("--bundle", default=None,
                    help="path to docs/_shared/<file>/_bundles/<chunk_id>.bundle.json (preferred)")
    ap.add_argument("--section-doc", default=None, help="path to the markdown to review")
    ap.add_argument("--source", default=None)
    ap.add_argument("--chunk-id", default=None)
    ap.add_argument("--language", default="en")
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--profile", default=None)
    ap.add_argument("--json-out", default=None)
    ap.add_argument("--no-write", action="store_true")
    args = ap.parse_args()

    if not args.bundle and not args.section_doc and not (args.source and args.chunk_id):
        print("ERROR: provide --bundle <path> (preferred), or --section-doc <path>, or (--source <path> + --chunk-id <id>).", file=sys.stderr)
        return 2

    cfg = load_sources_yaml()
    source_root = Path(args.source_root or cfg.get("source_root", "./samples"))
    if not source_root.is_absolute():
        source_root = (REPO_ROOT / source_root).resolve()

    # Resolve source/chunk context.
    source_path: Path | None = None
    chunk_filename: str | None = None
    chunk_id: str | None = args.chunk_id
    bundle: dict | None = None

    if args.bundle:
        bundle_path = Path(args.bundle)
        if not bundle_path.is_absolute():
            bundle_path = (REPO_ROOT / bundle_path).resolve()
        if not bundle_path.exists():
            print(f"ERROR: bundle not found: {bundle_path}", file=sys.stderr)
            return EXIT_MISSING_PREREQ
        bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
        for key in ("source_path", "chunk", "chunk_text", "chunk_text_sha", "output_paths"):
            if key not in bundle:
                print(f"ERROR: bundle missing required key {key!r}: {bundle_path}", file=sys.stderr)
                return EXIT_MISSING_PREREQ
        # Integrity / staleness: re-hash the embedded chunk text and compare.
        rehash = sha256_bytes(bundle["chunk_text"].encode("utf-8"))
        if rehash != bundle["chunk_text_sha"]:
            print(
                f"STALE: bundle.chunk_text_sha {bundle['chunk_text_sha'][:12]}… "
                f"!= re-hash {rehash[:12]}… — re-run stage-bundles.py",
                file=sys.stderr,
            )
            return EXIT_STALE
        sp = Path(bundle["source_path"])
        source_path = sp if sp.is_absolute() else (REPO_ROOT / sp).resolve()
        chunk_id = bundle["chunk"].get("id") or chunk_id
        out_paths = bundle["output_paths"]
        if args.section_doc:
            md_path = Path(args.section_doc)
        else:
            if args.language not in out_paths:
                print(
                    f"ERROR: language {args.language!r} not in bundle.output_paths "
                    f"(have: {sorted(k for k in out_paths if k != 'diagram')})",
                    file=sys.stderr,
                )
                return EXIT_MISSING_PREREQ
            md_path = Path(out_paths[args.language])
        # Use the markdown filename as the chunk filename for diagram derivation.
        chunk_filename = md_path.name
    elif args.source:
        source_path = resolve_source(args.source, source_root)
        doc_dir = default_doc_dir_for(source_path)
        manifest_path = doc_dir / "chunk-manifest.json"
        if not manifest_path.exists():
            print(f"ERROR: missing chunk-manifest.json — re-run cobol-chunking: {manifest_path}", file=sys.stderr)
            return EXIT_MISSING_PREREQ
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        on_disk_sha = sha256_bytes(source_path.read_bytes())
        if manifest.get("sha256") != on_disk_sha:
            print(
                f"STALE: chunk-manifest.json sha {manifest.get('sha256','?')[:12]}… "
                f"!= source sha {on_disk_sha[:12]}… — re-run cobol-chunking",
                file=sys.stderr,
            )
            return EXIT_STALE
        idx_path = doc_dir / "chunks" / "index.json"
        if not idx_path.exists():
            print(f"ERROR: missing chunks/index.json — re-run chunk-text-extraction: {idx_path}", file=sys.stderr)
            return EXIT_MISSING_PREREQ
        chunks_index = json.loads(idx_path.read_text(encoding="utf-8"))
        chunk_filename = find_chunk_filename(chunks_index, args.chunk_id)
        md_path = Path(args.section_doc) if args.section_doc else derive_md_path(source_path, chunk_filename, args.language)
    else:
        md_path = Path(args.section_doc)

    if not md_path.is_absolute():
        md_path = (REPO_ROOT / md_path).resolve()
    if not md_path.exists():
        print(f"ERROR: section markdown not found: {md_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    profile_path = Path(args.profile) if args.profile else DEFAULT_PROFILE
    if not profile_path.is_absolute():
        profile_path = (REPO_ROOT / profile_path).resolve()
    profile = yaml.safe_load(profile_path.read_text(encoding="utf-8")) or {}

    thresholds = {
        "min_total_words": int(profile.get("min_total_words", 1500)),
        "min_purpose_sentences": int(profile.get("min_purpose_sentences", 4)),
        "min_purpose_words": int(profile.get("min_purpose_words", 80)),
        "max_tldr_words": int(profile.get("max_tldr_words", 30)),
        "identifier_lock_regex": profile.get("identifier_lock_regex", "[A-Z][A-Z0-9-]*(\\.[A-Z0-9-]+)?"),
        "require_citations": bool(profile.get("require_citations", True)),
    }

    md_bytes = md_path.read_bytes()
    text = md_bytes.decode("utf-8", errors="replace")
    sections = extract_sections(text)

    findings: list[dict] = []
    tldr_words = check_tldr(sections, thresholds, findings)
    purpose_sentences, purpose_words = check_purpose(sections, thresholds, findings)
    src_count, inline_count = check_citations(text, thresholds, findings)
    check_banner(text, findings)
    check_identifier_styling(text, thresholds["identifier_lock_regex"], findings)
    total_words = check_total_words(text, thresholds, findings)
    if source_path and chunk_filename:
        check_diagram(source_path, chunk_filename, findings)
    check_xref_in(text, bundle, findings)

    findings = sort_findings(findings)
    error_count = sum(1 for f in findings if f["severity"] == "error")
    warn_count = sum(1 for f in findings if f["severity"] == "warn")

    review = {
        "review_version": "1.0",
        "section_doc": str(md_path.relative_to(REPO_ROOT)).replace("\\", "/") if md_path.is_relative_to(REPO_ROOT) else str(md_path),
        "section_doc_sha": sha256_bytes(md_bytes),
        "source_path": str(source_path.relative_to(REPO_ROOT)).replace("\\", "/") if source_path else None,
        "chunk_id": chunk_id,
        "language": args.language,
        "profile_path": str(profile_path.relative_to(REPO_ROOT)).replace("\\", "/") if profile_path.is_relative_to(REPO_ROOT) else str(profile_path),
        "thresholds": thresholds,
        "ok": error_count == 0,
        "findings": findings,
        "counters": {
            "total_words": total_words,
            "tldr_words": tldr_words,
            "purpose_sentences": purpose_sentences,
            "purpose_words": purpose_words,
            "src_footnotes": src_count,
            "inline_file_tags": inline_count,
        },
    }
    payload = json.dumps(review, indent=2, ensure_ascii=False) + "\n"

    if args.no_write:
        sys.stdout.write(payload)
    else:
        if args.json_out:
            out_path = Path(args.json_out)
            if not out_path.is_absolute():
                out_path = (REPO_ROOT / out_path).resolve()
        else:
            if not (source_path and chunk_id):
                print("ERROR: --json-out is required when chunk_id cannot be resolved (need --bundle or --source/--chunk-id).", file=sys.stderr)
                return 2
            out_name = f"{source_path.name}__{sanitize_id_for_review_name(chunk_id)}__{args.language}.json"
            out_path = DEFAULT_REVIEW_ROOT / out_name
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(payload, encoding="utf-8")
        verdict = "OK " if review["ok"] else "FAIL"
        rel_out = out_path.relative_to(REPO_ROOT) if out_path.is_relative_to(REPO_ROOT) else out_path
        print(f"{verdict}: errors={error_count} warns={warn_count}  ->  {rel_out}")
        if error_count:
            for f in findings:
                if f["severity"] != "error":
                    continue
                print(f"  [{f['code']}] line={f['line']}  {f['message']}")

    return EXIT_OK if review["ok"] else EXIT_FAIL


if __name__ == "__main__":
    sys.exit(main())
