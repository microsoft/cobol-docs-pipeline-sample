#!/usr/bin/env python3
# Deterministic builder for docs/<lang>/<file>/complete.md.
#
# Reads docs/_shared/<file>/_finalize.bundle.json and, for each language listed
# in the bundle, stitches:
#   <index.md body>
#   \n# Sections\n
#   for chunk in toc:
#       <a id="<section-stem>"></a>
#       <section_md body, all ATX headings demoted one level,
#        footnote ids [^src-N] -> [^<chunk_id>-src-N] for definitions AND refs>
#
# The produced complete.md is a self-contained single file:
#   * The trailing "Authoring self-check" block is stripped from every section.
#   * References to the internal facts.json knowledge graph are rewritten to a
#     generic "code" reference.
#   * Relative links to embedded sections become internal anchors; any other
#     relative documentation link is delinked (label kept) so nothing points at
#     external content. Absolute URLs and existing "#" anchors are preserved.
#
# The agent (section-doc-finalizer) no longer writes complete.md; it only
# authors index.md. This script regenerates complete.md from those bytes,
# saving LLM tokens and guaranteeing index/complete coherence.
#
# Exit codes:
#   0  ok (one or more complete.md written or already current)
#   2  bundle missing / malformed
#   3  required index.md or per-section MD missing
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

EXIT_OK = 0
EXIT_BUNDLE = 2
EXIT_MISSING_INPUT = 3

REPO_ROOT = Path(__file__).resolve().parents[4]

_ATX_RE = re.compile(r"^(#{1,5})(\s+\S.*)$")
_FENCE_RE = re.compile(r"^(\s*)(`{3,}|~{3,})")
_FOOTNOTE_DEF_RE = re.compile(r"^(\s{0,3})\[\^src-(\d+)\]:")
_FOOTNOTE_REF_RE = re.compile(r"\[\^src-(\d+)\]")

# Authoring self-check block: a generator-side contract that must never surface
# in the published complete.md. It starts at its HTML-comment preamble or its
# rendered heading (whichever appears first) and runs to end-of-body.
_SELF_CHECK_HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s+Authoring self-check\b", re.IGNORECASE)
_SELF_CHECK_COMMENT_RE = re.compile(r"^\s{0,3}<!--\s*Authoring self-check\b", re.IGNORECASE)
_HR_RE = re.compile(r"^\s{0,3}(-{3,}|\*{3,}|_{3,})\s*$")

# References to the internal facts.json knowledge graph must read as a generic
# "code" reference in the human-facing single-file deliverable.
_FACTS_JSON_RE = re.compile(r"facts\.json", re.IGNORECASE)

# Markdown inline link / image: optional leading '!', label, target, optional
# title. Footnote markers ([^id]) carry no parentheses and are never matched.
_LINK_RE = re.compile(r"(!?)\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def strip_self_check(body: str) -> str:
    """Remove the trailing 'Authoring self-check' block (HTML-comment preamble
    and/or rendered heading through end-of-body), plus any immediately
    preceding horizontal rule and blank lines. Fence-aware: a match inside a
    fenced code block is ignored."""
    lines = body.splitlines()
    in_fence = False
    fence_marker: str | None = None
    cut: int | None = None
    for i, line in enumerate(lines):
        if in_fence:
            m = _FENCE_RE.match(line)
            if m and fence_marker and m.group(2).startswith(fence_marker[0]):
                in_fence = False
                fence_marker = None
            continue
        m = _FENCE_RE.match(line)
        if m:
            in_fence = True
            fence_marker = m.group(2)
            continue
        if _SELF_CHECK_COMMENT_RE.match(line) or _SELF_CHECK_HEADING_RE.match(line):
            cut = i
            break
    if cut is None:
        return body
    j = cut - 1
    while j >= 0 and lines[j].strip() == "":
        j -= 1
    if j >= 0 and _HR_RE.match(lines[j]):
        j -= 1
        while j >= 0 and lines[j].strip() == "":
            j -= 1
    trimmed = "\n".join(lines[: j + 1])
    if trimmed and not trimmed.endswith("\n"):
        trimmed += "\n"
    return trimmed


def _rewrite_link(
    match: "re.Match[str]",
    anchor_by_basename: dict[str, str],
    self_basename: str,
) -> str:
    """Resolve a relative documentation link to an internal anchor when the
    target is one of the embedded sections; otherwise drop the link and keep
    the label so the single-file deliverable stays self-contained. Internal
    anchors and absolute external URLs are preserved verbatim. A self-link to
    the output file itself (complete.md#frag) collapses to its fragment."""
    bang, label, target = match.group(1), match.group(2), match.group(3)
    if target.startswith("#"):
        return match.group(0)
    if re.match(r"^[a-z][a-z0-9+.-]*://", target, re.IGNORECASE) or target.startswith("mailto:"):
        return match.group(0)
    head, _, frag = target.partition("#")
    path_part = head.split("?", 1)[0]
    basename = path_part.rsplit("/", 1)[-1]
    if basename == self_basename:
        # Self-reference into the very file being assembled: keep the in-doc
        # fragment, or drop the (now pointless) whole-file self link.
        return f"{bang}[{label}](#{frag})" if frag else label
    anchor = anchor_by_basename.get(basename)
    if anchor:
        return f"{bang}[{label}](#{anchor})"
    return label


def sanitize_inline(
    text: str,
    anchor_by_basename: dict[str, str],
    self_basename: str = "complete.md",
) -> str:
    """Apply facts.json -> code rewriting and relative-link neutralisation,
    skipping fenced code blocks."""
    out: list[str] = []
    in_fence = False
    fence_marker: str | None = None
    for line in text.splitlines():
        if in_fence:
            out.append(line)
            m = _FENCE_RE.match(line)
            if m and fence_marker and m.group(2).startswith(fence_marker[0]):
                in_fence = False
                fence_marker = None
            continue
        m = _FENCE_RE.match(line)
        if m:
            in_fence = True
            fence_marker = m.group(2)
            out.append(line)
            continue
        line = _LINK_RE.sub(
            lambda mm: _rewrite_link(mm, anchor_by_basename, self_basename), line
        )
        line = _FACTS_JSON_RE.sub("code", line)
        out.append(line)
    result = "\n".join(out)
    if text.endswith("\n") and not result.endswith("\n"):
        result += "\n"
    return result


def demote_and_namespace(body: str, chunk_id: str) -> str:
    """Demote ATX headings one level (H1->H2, ... H5->H6, H6 capped) and
    namespace footnote ids [^src-N] -> [^<chunk_id>-src-N] for both
    definitions and inline references. Skips content inside fenced code
    blocks."""
    out: list[str] = []
    in_fence = False
    fence_marker: str | None = None
    for line in body.splitlines():
        if in_fence:
            out.append(line)
            m = _FENCE_RE.match(line)
            if m and fence_marker and m.group(2).startswith(fence_marker[0]):
                in_fence = False
                fence_marker = None
            continue
        m = _FENCE_RE.match(line)
        if m:
            in_fence = True
            fence_marker = m.group(2)
            out.append(line)
            continue
        # Heading demote (only ATX, only H1..H5; H6 stays at H6).
        h = _ATX_RE.match(line)
        if h:
            hashes = h.group(1)
            if len(hashes) < 6:
                line = "#" + hashes + h.group(2)
        # Footnote definition.
        d = _FOOTNOTE_DEF_RE.match(line)
        if d:
            line = f"{d.group(1)}[^{chunk_id}-src-{d.group(2)}]:" + line[d.end():]
        # Footnote inline refs (skip the definition prefix we just rewrote).
        line = _FOOTNOTE_REF_RE.sub(lambda r: f"[^{chunk_id}-src-{r.group(1)}]", line)
        out.append(line)
    # Preserve trailing newline behaviour.
    result = "\n".join(out)
    if body.endswith("\n") and not result.endswith("\n"):
        result += "\n"
    return result


_TRK_RE = re.compile(r"^REC-(\d{3})-(.+)$")


def build_trk_catalog(src_name: str, toc: list[dict], lang: str) -> str:
    """Deterministic SISBA TRK (tracciato) record catalog for complete.md.

    A TRK record is a level-01 `data_records` entry named
    `REC-<3-digit code>-<file>` whose `<file>` suffix is a declared output file
    in `facts.json.files` (this excludes working-storage flags such as
    `REC-103-CES-FLAG`). Records are grouped by target output file and linked to
    the embedded section anchor that carries their full byte-level layout.

    This is the single point at which the TRK tracciato catalog enters the
    pipeline: technical-analysis (phase L) reads `complete.md` only, so framing
    the output record layouts as a TRK catalog here is what lets the ATE writer
    author its `trk-gestiti` section instead of stamping the not-applicable
    marker. Returns "" when the source emits no TRK records."""
    facts_path = REPO_ROOT / "docs" / "_shared" / src_name / "facts.json"
    if not facts_path.exists():
        return ""
    try:
        facts = json.loads(facts_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return ""
    file_names = {f.get("name") for f in (facts.get("files") or []) if f.get("name")}
    if not file_names:
        return ""
    anchor_by_chunk: dict[str, str] = {}
    for entry in toc or []:
        cid = entry.get("chunk_id")
        rel = (entry.get("section_md") or {}).get(lang)
        if cid and rel:
            anchor_by_chunk[cid] = Path(rel).stem
    by_file: dict[str, list[dict]] = {}
    for rec in (facts.get("data_records") or []):
        if str(rec.get("level")).lstrip("0") not in ("1", ""):
            continue
        name = rec.get("name") or ""
        m = _TRK_RE.match(name)
        if not m:
            continue
        code, suffix = m.group(1), m.group(2)
        if suffix not in file_names:
            continue
        by_file.setdefault(suffix, []).append({
            "code": code,
            "name": name,
            "fields": len(rec.get("fields") or []),
            "anchor": anchor_by_chunk.get(rec.get("chunk_id") or ""),
        })
    if not by_file:
        return ""
    n_files = len(by_file)
    lines: list[str] = []
    lines.append("# Record types (TRK)")
    lines.append("")
    lines.append(
        "This process emits SISBA interchange (tracciato) records to "
        f"{n_files} output file{'s' if n_files != 1 else ''}. Each output "
        "record is named `REC-<TRK code>-<file>` and carries a 3-digit TRK "
        "type code that identifies its layout to the receiving system. The "
        "catalog below is derived from the data-division record definitions; "
        "the full byte-level layout of each record is documented in the linked "
        "section."
    )
    lines.append("")
    for suffix in sorted(by_file):
        recs = sorted(by_file[suffix], key=lambda x: x["code"])
        lines.append(f"## Output file `{suffix}`")
        lines.append("")
        lines.append("| TRK code | Record | Fields | Layout |")
        lines.append("|---|---|---|---|")
        for r in recs:
            link = f"[`{r['name']}`](#{r['anchor']})" if r["anchor"] else f"`{r['name']}`"
            lines.append(f"| {r['code']} | `{r['name']}` | {r['fields']} | {link} |")
        lines.append("")
    return "\n".join(lines).rstrip("\n")


def assemble_one(bundle: dict, lang: str, *, force: bool) -> tuple[str, str]:
    """Returns (status, message). status in {ok, skipped-current, missing}."""
    src_name = Path(bundle["source_path"]).name
    out_rel = bundle.get("output_paths", {}).get(lang, {}).get("complete")
    if not out_rel:
        return ("missing", f"no output_paths.{lang}.complete in bundle")
    out_path = REPO_ROOT / out_rel
    index_rel = bundle["output_paths"][lang].get("index")
    if not index_rel:
        return ("missing", f"no output_paths.{lang}.index in bundle")
    index_path = REPO_ROOT / index_rel
    if not index_path.exists():
        return ("missing", f"index.md not found: {index_rel}")

    section_paths: list[tuple[str, Path]] = []
    for entry in bundle.get("toc") or []:
        chunk_id = entry.get("chunk_id")
        rel = (entry.get("section_md") or {}).get(lang)
        if not chunk_id or not rel:
            return ("missing", f"toc entry missing chunk_id or section_md.{lang}: {entry!r}")
        p = REPO_ROOT / rel
        if not p.exists():
            return ("missing", f"section md not found: {rel}")
        section_paths.append((chunk_id, p))

    # Resume gate: skip if complete.md mtime >= max(index.md, every section.md).
    if not force and out_path.exists():
        out_mt = out_path.stat().st_mtime
        newest_input = index_path.stat().st_mtime
        for _, p in section_paths:
            mt = p.stat().st_mtime
            if mt > newest_input:
                newest_input = mt
        if out_mt >= newest_input:
            return ("skipped-current", str(out_path))

    # Map each embedded section's filename to a stable in-document anchor id so
    # cross-references resolve internally instead of pointing at sibling files.
    anchor_by_basename = {p.name: p.stem for _, p in section_paths}
    self_basename = out_path.name

    parts: list[str] = []
    index_body = index_path.read_text(encoding="utf-8")
    parts.append(sanitize_inline(index_body, anchor_by_basename, self_basename).rstrip("\n"))
    parts.append("")  # blank line before separator
    parts.append("# Sections")
    for chunk_id, p in section_paths:
        body = p.read_text(encoding="utf-8")
        body = strip_self_check(body)
        body = demote_and_namespace(body, chunk_id)
        body = sanitize_inline(body, anchor_by_basename, self_basename)
        parts.append("")
        parts.append(f'<a id="{p.stem}"></a>')
        parts.append("")
        parts.append(body.rstrip("\n"))

    # Deterministic SISBA TRK (tracciato) catalog. Framing the output record
    # layouts as a TRK catalog here is the DAG step that surfaces tracciati to
    # the phase-L technical-analysis writer (which reads complete.md only).
    trk_catalog = build_trk_catalog(src_name, bundle.get("toc") or [], lang)
    if trk_catalog:
        parts.append("")
        parts.append(trk_catalog)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
    return ("ok", f"{out_path} (sections={len(section_paths)})")


def main() -> int:
    ap = argparse.ArgumentParser(description="Deterministic builder for complete.md")
    ap.add_argument("--bundle", required=True, help="Path to _finalize.bundle.json")
    ap.add_argument("--languages", default=None,
                    help="Comma-separated subset; default = bundle.languages")
    ap.add_argument("--force", action="store_true",
                    help="Rebuild even if complete.md is newer than inputs")
    args = ap.parse_args()

    bundle_path = Path(args.bundle)
    if not bundle_path.is_absolute():
        bundle_path = (REPO_ROOT / bundle_path).resolve()
    if not bundle_path.exists():
        print(f"ERROR: bundle not found: {bundle_path}", file=sys.stderr)
        return EXIT_BUNDLE
    try:
        bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"ERROR: malformed bundle {bundle_path}: {exc}", file=sys.stderr)
        return EXIT_BUNDLE

    langs = bundle.get("languages") or ["en"]
    if args.languages:
        wanted = [x.strip() for x in args.languages.split(",") if x.strip()]
        langs = [l for l in langs if l in wanted] or wanted

    rc = EXIT_OK
    src_name = Path(bundle.get("source_path", "")).name
    for lang in langs:
        status, msg = assemble_one(bundle, lang, force=args.force)
        if status == "missing":
            print(f"MISSING file={src_name} lang={lang}: {msg}", file=sys.stderr)
            rc = EXIT_MISSING_INPUT
        elif status == "skipped-current":
            print(f"SKIP file={src_name} lang={lang}: up-to-date {msg}")
        else:
            print(f"OK file={src_name} lang={lang}: {msg}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
