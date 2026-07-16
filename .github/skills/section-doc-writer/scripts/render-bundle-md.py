#!/usr/bin/env python3
"""Render a bundle JSON (from `assemble-inputs.py`) into a Markdown VIEW.

The MD output is a derived, read-only projection of the JSON bundle intended
to make the bundle easier for an LLM to consume. The JSON remains the
authoritative artifact: SHAs, qa-reviewer byte-identity checks, and
downstream tooling all read the `.json`. This script never writes back.

Usage:
    render-bundle-md.py --in <bundle.json> [--out <bundle.md>]
    cat bundle.json | render-bundle-md.py
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

FENCE_BY_SOURCE_KIND = {
    "cobol": "cobol",
    "copybook": "cobol",
    "cl": "cl",
    "jcl": "jcl",
    "proc": "jcl",
    "bms": "text",
}


def fence_for(source_kind: str) -> str:
    return FENCE_BY_SOURCE_KIND.get((source_kind or "").lower(), "text")


def md_escape_cell(value: object) -> str:
    s = "" if value is None else str(value)
    return s.replace("|", "\\|").replace("\n", " ").strip()


def kv_table(rows: list[tuple[str, object]]) -> str:
    out = ["| key | value |", "|---|---|"]
    for k, v in rows:
        out.append(f"| `{k}` | {md_escape_cell(v)} |")
    return "\n".join(out)


def is_uniform_list_of_dicts(value: object) -> bool:
    if not isinstance(value, list) or not value:
        return False
    return all(isinstance(item, dict) for item in value)


def list_of_dicts_table(items: list[dict]) -> str:
    keys: list[str] = []
    seen: set[str] = set()
    for item in items:
        for k in item.keys():
            if k not in seen:
                seen.add(k)
                keys.append(k)
    header = "| " + " | ".join(f"`{k}`" for k in keys) + " |"
    sep = "|" + "|".join(["---"] * len(keys)) + "|"
    rows = []
    for item in items:
        cells = []
        for k in keys:
            v = item.get(k)
            if isinstance(v, (dict, list)):
                v = json.dumps(v, ensure_ascii=False, separators=(",", ":"))
            cells.append(md_escape_cell(v))
        rows.append("| " + " | ".join(cells) + " |")
    return "\n".join([header, sep, *rows])


def render_collection(name: str, value: object) -> str:
    """Render one facts_slice collection as a sub-section."""
    if isinstance(value, list):
        n = len(value)
        heading = f"### {name} ({n})"
        if n == 0:
            return f"{heading}\n\n_(empty)_"
        if is_uniform_list_of_dicts(value):
            return f"{heading}\n\n{list_of_dicts_table(value)}"
        # list of scalars / mixed
        bullets = []
        for item in value:
            if isinstance(item, (dict, list)):
                bullets.append(f"- `{json.dumps(item, ensure_ascii=False, separators=(',', ':'))}`")
            else:
                bullets.append(f"- {md_escape_cell(item)}")
        return f"{heading}\n\n" + "\n".join(bullets)
    if isinstance(value, dict):
        heading = f"### {name}"
        scalar_rows = [(k, v) for k, v in value.items() if not isinstance(v, (dict, list))]
        complex_rows = [(k, v) for k, v in value.items() if isinstance(v, (dict, list))]
        parts = [heading]
        if scalar_rows:
            parts.append("")
            parts.append(kv_table(scalar_rows))
        for k, v in complex_rows:
            parts.append("")
            parts.append(f"#### {name}.{k}")
            parts.append("")
            parts.append("```json")
            parts.append(json.dumps(v, indent=2, ensure_ascii=False))
            parts.append("```")
        if not scalar_rows and not complex_rows:
            parts.append("")
            parts.append("_(empty)_")
        return "\n".join(parts)
    # scalar
    return f"### {name}\n\n`{md_escape_cell(value)}`"


def render_chunk_section(chunk: dict) -> str:
    scalar_keys = ["id", "kind", "name", "start_line", "end_line", "line_count", "parent", "parents"]
    rows: list[tuple[str, object]] = []
    for k in scalar_keys:
        if k in chunk:
            v = chunk[k]
            if isinstance(v, list):
                v = ", ".join(str(x) for x in v)
            rows.append((k, v))
    # any other top-level scalars we haven't shown
    for k, v in chunk.items():
        if k in scalar_keys:
            continue
        if not isinstance(v, (dict, list)):
            rows.append((k, v))
    out = ["## Chunk", "", kv_table(rows)]
    # render complex sub-fields as JSON blocks
    for k, v in chunk.items():
        if isinstance(v, (dict, list)):
            out += ["", f"### chunk.{k}", "", "```json", json.dumps(v, indent=2, ensure_ascii=False), "```"]
    return "\n".join(out)


def render_profile_section(profile_path: str) -> str:
    # Link only — the full profile body lives at profile_path; profile_sha (in
    # Metadata) pins it. Inlining the YAML duplicated ~140 identical lines in
    # every bundle (same profile is shared by all chunks of every source).
    return "\n".join([
        "## Profile",
        "",
        f"Authoring/QA policy: [`{profile_path}`]({profile_path}).",
        "",
        "`profile_sha` (from Metadata) pins the exact bytes the qa-reviewer enforces.",
    ])


def render(bundle: dict) -> str:
    chunk = bundle.get("chunk") or {}
    chunk_id = chunk.get("id", "?")
    chunk_kind = chunk.get("kind", "?")
    source_path = bundle.get("source_path", "?")
    source_kind = bundle.get("source_kind", "?")
    source_platform = bundle.get("source_platform", "mainframe")
    diagram_kind = bundle.get("diagram_kind", "?")
    template_path = bundle.get("template_path", "?")
    profile_path = bundle.get("profile_path", "?")
    languages = bundle.get("languages") or []
    output_paths = bundle.get("output_paths") or {}
    facts_slice = bundle.get("facts_slice") or {}
    chunk_text = bundle.get("chunk_text", "")
    template_text = bundle.get("template_text", "")

    meta_rows: list[tuple[str, object]] = [
        ("bundle_version", bundle.get("bundle_version")),
        ("source_path", source_path),
        ("source_kind", source_kind),
        ("source_platform", source_platform),
        ("chunk.id", chunk_id),
        ("chunk.kind", chunk_kind),
        ("diagram_kind", diagram_kind),
        ("template_path", template_path),
        ("profile_path", profile_path),
        ("languages", ", ".join(languages)),
        ("chunk_text_sha", bundle.get("chunk_text_sha")),
        ("facts_slice_sha", bundle.get("facts_slice_sha")),
        ("template_sha", bundle.get("template_sha")),
        ("profile_sha", bundle.get("profile_sha")),
    ]

    out_lines = [
        f"# Bundle: {chunk_id}",
        "",
        "> Derived view of the bundle JSON. The `.json` sibling is authoritative — qa-reviewer, SHAs and downstream tooling read it, not this file. Do not edit by hand.",
        "",
        "## Metadata",
        "",
        kv_table(meta_rows),
        "",
        "## Output paths",
        "",
    ]
    if output_paths:
        for k, v in output_paths.items():
            out_lines.append(f"- **{k}** → `{v}`")
    else:
        out_lines.append("_(none)_")
    out_lines += ["", render_chunk_section(chunk), ""]

    # Source text
    start = chunk.get("start_line")
    end = chunk.get("end_line")
    range_str = f" (lines {start}–{end})" if start is not None and end is not None else ""
    out_lines += [
        f"## Source text{range_str}",
        "",
        f"From `{source_path}`.",
        "",
        f"```{fence_for(source_kind)}",
        chunk_text.rstrip("\n"),
        "```",
        "",
    ]

    # Facts slice
    out_lines += ["## Facts slice", ""]
    if not facts_slice:
        out_lines.append("_(empty)_")
    else:
        for k, v in facts_slice.items():
            out_lines.append(render_collection(k, v))
            out_lines.append("")

    # Profile (link only — see render_profile_section docstring).
    out_lines += [render_profile_section(profile_path), ""]

    # Template (link only — full body lives at template_path; SHA pins it).
    # Inlining the template body bloats every .bundle.md by hundreds of lines
    # and duplicates content already pinned by template_sha in Metadata.
    _ = template_text  # kept for signature stability; JSON sibling still carries the text
    out_lines += [
        "## Template",
        "",
        f"Read the authoring rules from [`{template_path}`]({template_path}).",
        "",
        f"`template_sha` (from Metadata) pins the exact bytes the agent must obey.",
        "",
    ]
    return "\n".join(out_lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Render a section-doc-writer bundle JSON to a Markdown view.")
    ap.add_argument("--in", dest="in_path", default=None, help="bundle JSON path (default: stdin)")
    ap.add_argument("--out", default=None, help="output MD path (default: stdout)")
    args = ap.parse_args()

    if args.in_path:
        text = Path(args.in_path).read_text(encoding="utf-8")
    else:
        text = sys.stdin.read()
    bundle = json.loads(text)
    md = render(bundle)
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(md, encoding="utf-8")
        print(f"OK: bundle MD written to {out} ({len(md):,} bytes)")
    else:
        sys.stdout.write(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
