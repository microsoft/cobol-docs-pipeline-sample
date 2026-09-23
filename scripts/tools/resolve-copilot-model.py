#!/usr/bin/env python3
"""Resolve Copilot model precedence without overriding an agent fallback."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

import yaml


def validate_model(value: object, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]*", value):
        raise ValueError(f"{label} must be a nonempty Copilot model ID (or 'auto')")
    return value


def agent_model(path: Path | None) -> str | None:
    if path is None or not path.exists():
        return None
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            frontmatter = yaml.safe_load("\n".join(lines[1:index]))
            if not isinstance(frontmatter, dict):
                raise ValueError(f"agent frontmatter must be a mapping: {path}")
            if "model" not in frontmatter:
                return None
            model = frontmatter["model"]
            if not isinstance(model, str) or not model.strip() or "\n" in model or "\r" in model:
                raise ValueError(f"agent model must be a nonempty single-line string: {path}")
            return model.strip()
    raise ValueError(f"unterminated agent frontmatter: {path}")


def resolve_model(
    config_path: Path, model: str | None = None, agent_file: Path | None = None
) -> dict[str, str]:
    config = yaml.safe_load(config_path.read_text(encoding="utf-8")) if config_path.exists() else {}
    if not isinstance(config, dict):
        raise ValueError(f"pipeline configuration must be a mapping: {config_path}")
    copilot = config.get("copilot", {})
    if not isinstance(copilot, dict):
        raise ValueError("copilot must be a mapping")
    configured = None
    if "default_model" in copilot:
        configured = validate_model(copilot["default_model"], "copilot.default_model")
    if model is not None:
        selected = validate_model(model, "-CopilotModel")
        return {"model": selected, "source": "cli", "cli_model": selected}
    if configured is not None:
        return {"model": configured, "source": "config", "cli_model": configured}
    fallback = agent_model(agent_file)
    if fallback is not None:
        # Preserve CLI handling of agent-specific display names and availability.
        return {"model": fallback, "source": "agent", "cli_model": ""}
    return {"model": "auto", "source": "auto", "cli_model": "auto"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--model")
    parser.add_argument("--agent-file", type=Path)
    parser.add_argument("--format", choices=("json", "lines", "override"), default="json")
    args = parser.parse_args()
    try:
        result = resolve_model(args.config, args.model, args.agent_file)
    except (OSError, ValueError, yaml.YAMLError) as error:
        parser.error(str(error))
    if args.format == "lines":
        print("\n".join(result[key] for key in ("model", "source", "cli_model")))
    elif args.format == "override":
        print(result["model"] if result["source"] in ("cli", "config") else "")
    else:
        print(json.dumps(result))


if __name__ == "__main__":
    main()
