#!/usr/bin/env python3
"""Resolve bounded Copilot concurrency for both public pipeline runners."""

from __future__ import annotations

import argparse
from pathlib import Path
import re

import yaml


SCOPES = ("sections", "finalizer", "diagrams")


def validate_limit(value: object, label: str) -> int:
    if type(value) is not int or not 1 <= value <= 32:
        raise ValueError(f"{label} must be an integer between 1 and 32")
    return value


def cli_limit(value: str, label: str) -> int:
    if not re.fullmatch(r"[0-9]+", value):
        raise ValueError(f"{label} must be an integer between 1 and 32")
    return validate_limit(int(value), label)


def resolve_parallelism(
    config_path: Path, throttle: str | None = None, **overrides: str | None
) -> list[int]:
    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ValueError(f"pipeline configuration must be a mapping: {config_path}")
    pipeline = config.get("pipeline", {})
    if not isinstance(pipeline, dict):
        raise ValueError("pipeline must be a mapping")
    default = validate_limit(
        pipeline.get("copilot_parallelism", 16), "pipeline.copilot_parallelism"
    )
    if throttle is not None:
        default = cli_limit(throttle, "-CopilotThrottle")
    limits = [default]
    for scope in SCOPES:
        value = overrides.get(scope)
        limits.append(default if value is None else cli_limit(value, scope))
    return limits


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--throttle")
    for scope in SCOPES:
        parser.add_argument(f"--{scope}")
    args = parser.parse_args()
    try:
        limits = resolve_parallelism(
            args.config, args.throttle,
            **{scope: getattr(args, scope) for scope in SCOPES},
        )
    except (OSError, ValueError, yaml.YAMLError) as error:
        parser.error(str(error))
    print("\n".join(str(limit) for limit in limits))


if __name__ == "__main__":
    main()
