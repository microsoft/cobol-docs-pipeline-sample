#!/usr/bin/env python3
"""Resolve default output phases, including prerequisites, for both public runners."""

from __future__ import annotations

import argparse
from pathlib import Path

import yaml


PHASE_ORDER = tuple("ABCDEFGHIJKLMN")
OUTPUT_PHASES = {
    "docs": ("E", "H", "I"),
    "functional_analysis": ("G", "K"),
    "requirements": ("F", "J"),
    "technical_analysis": ("L", "M"),
}
# Public runner phase IDs: unlike the agent DAG, section authoring/finalization
# are separate D/E steps. Technical analysis reads complete.md, not FA/REQ.
PREREQUISITES = {
    "A": (),
    "B": ("A",),
    "C": ("B",),
    "D": ("C",),
    "E": ("D",),
    "F": ("E",),
    "G": ("E",),
    "H": ("B",),
    "I": ("E",),
    "J": ("F", "I"),
    "K": ("G", "J"),
    "L": ("E",),
    "M": ("I", "L"),
    "N": (),
}


def resolve_phases(config_path: Path) -> list[str]:
    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ValueError(f"pipeline configuration must be a mapping: {config_path}")
    output = config.get("output", {})
    if not isinstance(output, dict):
        raise ValueError("output must be a mapping")
    generate = output.get("generate", {})
    if not isinstance(generate, dict):
        raise ValueError("output.generate must be a mapping of output names to booleans")
    for key, value in generate.items():
        if key not in OUTPUT_PHASES:
            raise ValueError(f"output.generate: unknown output {key!r}")
        if not isinstance(value, bool):
            raise ValueError(f"output.generate.{key} must be true or false (not a quoted string)")

    selected: set[str] = set()

    def include(phase: str) -> None:
        if phase in selected:
            return
        selected.add(phase)
        for prerequisite in PREREQUISITES[phase]:
            include(prerequisite)

    for key, phases in OUTPUT_PHASES.items():
        if generate.get(key, True):
            for phase in phases:
                include(phase)
    if selected:
        selected.add("N")
    return [phase for phase in PHASE_ORDER if phase in selected]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    try:
        phases = resolve_phases(args.config)
    except (OSError, ValueError, yaml.YAMLError) as error:
        parser.error(str(error))
    for phase in phases:
        print(phase)


if __name__ == "__main__":
    main()
