#!/usr/bin/env python3
"""Resolve documentation languages for both public pipeline runners."""

from __future__ import annotations

import argparse
from pathlib import Path
import re

import yaml


LANGUAGE_PATTERN = r"[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*"
SCOPES = ("sections", "requirements", "functional_analysis", "technical_analysis", "groups")


def normalize_languages(value: object, label: str) -> str:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{label} must be a non-empty list of language codes")
    languages = []
    for item in value:
        if not isinstance(item, str) or not re.fullmatch(LANGUAGE_PATTERN, item.strip()):
            raise ValueError(f"{label}: invalid language code {item!r}")
        language = item.strip().lower()
        if language not in languages:
            languages.append(language)
    return ",".join(languages)


def resolve_languages(
    config_path: Path, languages: str | None = None, **overrides: str | None
) -> list[str]:
    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ValueError(f"source configuration must be a mapping: {config_path}")
    output = config.get("output", {})
    if not isinstance(output, dict):
        raise ValueError("output must be a mapping")
    default = normalize_languages(output.get("languages", ["en"]), "output.languages")
    if languages is not None:
        default = normalize_languages(languages.split(","), "-Languages")
    resolved = []
    for scope in SCOPES:
        override = overrides.get(scope)
        resolved.append(
            default if override is None
            else normalize_languages(override.split(","), scope)
        )
    return resolved


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--languages")
    for scope in SCOPES:
        parser.add_argument(f"--{scope.replace('_', '-')}")
    args = parser.parse_args()
    try:
        resolved = resolve_languages(
            args.config, args.languages,
            **{scope: getattr(args, scope) for scope in SCOPES},
        )
    except (OSError, ValueError, yaml.YAMLError) as error:
        parser.error(str(error))
    print("\n".join(resolved))


if __name__ == "__main__":
    main()
