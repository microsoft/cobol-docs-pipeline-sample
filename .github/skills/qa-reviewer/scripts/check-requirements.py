#!/usr/bin/env python3
"""Deterministic QA checker for phase-F technical-requirements markdown (SCAFFOLD).

Mirrors `check-functional-analysis.py` but targets the requirements profile
family and writes review sidecars at:

  docs/_reviews/requirements/<file>__<section_id>__<lang>.json   (per-section)
  docs/_reviews/requirements/<file>__<lang>.json                 (per-file)

Mechanical checks (no LLM) when implemented:
  - required heading present (H2/H3 + section.number + section.title)
  - optional sections with no body carry `profile.section.optional_marker`
  - every column in `section.table.columns` appears in the rendered table
  - every diagram in `section.embed_diagrams` is embedded as inline ```mermaid```
  - requirement ids match `profile.functional_id_prefix` / `non_functional_id_prefix`
    + `profile.id_padding`; ids are unique across the document
  - citations: `## Sources` block present + at least one `[^src-N]` footnote
  - no forbidden filler tokens: N/A, TBD, ???, "Section not applicable" inside
    a REQUIRED section
  - no `[FILE:Lx-Ly]` inline tags
  - per-file scope: every required section in profile order is present;
    footnote ids are unique and contiguous

Status: not yet implemented. Exit code 2 until the checker body is filled in.
"""
from __future__ import annotations
import sys


def main(argv: list[str]) -> int:
    sys.stderr.write(
        "qa-reviewer/check-requirements.py: scaffold — not yet implemented.\n"
        "Mirror .github/skills/qa-reviewer/scripts/check-functional-analysis.py\n"
        "with the requirements profile family + requirement-id checks.\n"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
