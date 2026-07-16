#!/usr/bin/env python3
"""Fail if docs/_glossary.md is out of sync with config/glossary.yaml."""

from __future__ import annotations

import difflib
import hashlib
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = REPO_ROOT / "config" / "glossary.yaml"
OUTPUT_PATH = REPO_ROOT / "docs" / "_glossary.md"


def _sha256(data: str) -> str:
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def _load_entries() -> list[dict]:
    if not CONFIG_PATH.exists():
        raise SystemExit(f"ERROR: missing glossary config: {CONFIG_PATH}")
    cfg = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8")) or {}
    entries = cfg.get("entries") or []
    if not isinstance(entries, list):
        raise SystemExit("ERROR: config/glossary.yaml 'entries' must be a list")

    normalized: list[dict] = []
    for raw in entries:
        if not isinstance(raw, dict):
            continue
        normalized.append(
            {
                "term_it": str(raw.get("term_it") or "").strip(),
                "term_en": str(raw.get("term_en") or "").strip(),
                "definition_it": str(raw.get("definition_it") or "").strip(),
                "definition_en": str(raw.get("definition_en") or "").strip(),
                "aliases": [str(v).strip() for v in (raw.get("aliases") or []) if str(v).strip()],
            }
        )
    normalized = [e for e in normalized if e["term_it"] and e["term_en"]]
    normalized.sort(key=lambda e: e["term_it"].lower())
    return normalized


def _render(entries: list[dict]) -> str:
    lines: list[str] = []
    lines.append("# IT-EN Central Glossary")
    lines.append("")
    lines.append("This file is generated from `config/glossary.yaml` by `scripts/validation/sync-glossary.py`.")
    lines.append("Use this glossary as the single source of truth for shared domain terms.")
    lines.append("")
    lines.append("| IT term | EN term | IT definition | EN definition | Aliases |")
    lines.append("|---------|---------|---------------|---------------|---------|")
    for e in entries:
        aliases = ", ".join(f"`{a}`" for a in e["aliases"]) if e["aliases"] else "-"
        it_term = e["term_it"].replace("|", "\\|")
        en_term = e["term_en"].replace("|", "\\|")
        it_def = e["definition_it"].replace("|", "\\|")
        en_def = e["definition_en"].replace("|", "\\|")
        lines.append(
            f"| `{it_term}` | `{en_term}` | {it_def} | {en_def} | {aliases} |"
        )
    lines.append("")
    lines.append(f"Glossary entries: **{len(entries)}**")
    return "\n".join(lines) + "\n"


def main() -> int:
    expected = _render(_load_entries())
    if not OUTPUT_PATH.exists():
        print(
            "ERROR: docs/_glossary.md is missing. "
            "Run: python scripts/validation/sync-glossary.py"
        )
        return 1

    actual = OUTPUT_PATH.read_text(encoding="utf-8", errors="replace")
    if actual == expected:
        print(f"OK: glossary aligned (sha256={_sha256(actual)[:8]})")
        return 0

    print("ERROR: glossary drift detected between config/glossary.yaml and docs/_glossary.md")
    print("Run: python scripts/validation/sync-glossary.py")
    diff = difflib.unified_diff(
        actual.splitlines(),
        expected.splitlines(),
        fromfile="docs/_glossary.md",
        tofile="expected-from-config",
        lineterm="",
        n=3,
    )
    for idx, line in enumerate(diff):
        print(line)
        if idx >= 120:
            print("... diff truncated ...")
            break
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
