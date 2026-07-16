#!/usr/bin/env python3
"""Inspect a prepared section bundle."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def print_bundle_summary(bundle: dict[str, Any]) -> None:
    chunk = bundle["chunk"]
    print(f"Languages: {bundle['languages']}")
    print(f"Diagram kind: {bundle['diagram_kind']}")
    print(f"Template path: {bundle['template_path']}")
    print(f"Chunk ID: {chunk['id']}")
    print(f"Chunk kind: {chunk['kind']}")
    print(f"Chunk name: {chunk['name']}")
    print(f"Lines: {chunk['start_line']}-{chunk['end_line']}")

    facts = bundle.get("facts_slice", {})
    data_records = facts.get("data_records", [])
    print("\n=== FACTS SUMMARY ===")
    print(f"01-level records (data_records): {len(data_records)}")
    print(f"Copybooks (copybooks): {len(facts.get('copybooks', []))}")
    print(f"Files (files): {len(facts.get('files', []))}")

    if data_records:
        print("\nFirst 5 data records:")
        for index, record in enumerate(data_records[:5], start=1):
            print(
                f"  {index}. {record.get('name')} (level {record.get('level')}, "
                f"lines {record.get('start_line')}-{record.get('end_line')})"
            )
        if len(data_records) > 5:
            print(f"\n... and {len(data_records) - 5} more records")

    chunk_text = bundle.get("chunk_text", "")
    print(f"\nChunk text length: {len(chunk_text)} bytes")
    print(f"Contains 'FILE SECTION': {'FILE SECTION' in chunk_text}")
    print(f"Contains 'WORKING-STORAGE SECTION': {'WORKING-STORAGE SECTION' in chunk_text}")
    print(f"Contains 'LINKAGE SECTION': {'LINKAGE SECTION' in chunk_text}")
    print(f"Contains 'LOCAL-STORAGE SECTION': {'LOCAL-STORAGE SECTION' in chunk_text}")

    profile = bundle.get("profile", {})
    print(f"\nProfile identifier regex: {profile.get('identifier_lock_regex', 'N/A')}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="Path to a prepared .bundle.json file.")
    args = parser.parse_args(argv)

    try:
        with args.bundle.open("r", encoding="utf-8") as bundle_file:
            bundle = json.load(bundle_file)
        print_bundle_summary(bundle)
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as error:
        print(f"ERROR: unable to inspect {args.bundle}: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
