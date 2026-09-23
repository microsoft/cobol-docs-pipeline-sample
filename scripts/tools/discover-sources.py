#!/usr/bin/env python3
"""Resolve configured source files for the public pipeline launchers."""

from __future__ import annotations

import argparse
from collections import defaultdict
import fnmatch
import os
from pathlib import Path, PurePosixPath
import sys

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = REPO_ROOT / "config" / "pipeline.yaml"
SUPPORTED_EXTENSIONS = {
    ".bms",
    ".cbl",
    ".cblle",
    ".cl",
    ".clle",
    ".clp",
    ".cob",
    ".cpy",
    ".jcl",
    ".prc",
    ".sqlcblle",
}


def _matches(relative_path: str, pattern: str) -> bool:
    path = PurePosixPath(relative_path)
    normalized = pattern.replace("\\", "/").lstrip("./")
    return (
        fnmatch.fnmatchcase(relative_path.casefold(), normalized.casefold())
        or path.match(normalized)
        or (normalized.startswith("**/") and path.match(normalized[3:]))
    )


def _included_candidates(source_root: Path, pattern: str):
    normalized = pattern.replace("\\", "/").strip("/")
    literal_path = source_root / normalized
    if not any(character in normalized for character in "*?[") and literal_path.is_dir():
        yield from literal_path.rglob("*")
        return
    yield from source_root.glob(normalized)


def _matches_include(relative_path: str, pattern: str) -> bool:
    normalized = pattern.replace("\\", "/").strip("/")
    if _matches(relative_path, normalized):
        return True
    return (
        not any(character in normalized for character in "*?[")
        and relative_path.casefold().startswith(f"{normalized}/".casefold())
    )


def _load_config(config_path: Path) -> dict:
    config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    if not isinstance(config, dict):
        raise ValueError(f"source configuration must be a mapping: {config_path}")
    return config


def _resolve_source_root(
    config: dict, config_path: Path, source_root_override: str | None
) -> Path:
    configured_root = source_root_override or config.get("source_root")
    if not configured_root:
        raise ValueError(f"source_root is required in {config_path}")

    source_root = Path(configured_root).expanduser()
    if not source_root.is_absolute():
        source_root = REPO_ROOT / source_root
    source_root = source_root.resolve()
    if not source_root.is_dir():
        raise ValueError(f"source_root is not a directory: {source_root}")
    return source_root


def _is_configured_source(relative_path: str, config: dict) -> bool:
    include_patterns = config.get("include") or ["**/*"]
    exclude_patterns = config.get("exclude") or []
    return (
        Path(relative_path).suffix.lower() in SUPPORTED_EXTENSIONS
        and any(_matches_include(relative_path, included) for included in include_patterns)
        and not any(_matches(relative_path, excluded) for excluded in exclude_patterns)
    )


def filter_candidates(
    config_path: Path, source_root_override: str | None, candidates: list[str]
) -> list[Path]:
    config = _load_config(config_path)
    source_root = _resolve_source_root(config, config_path, source_root_override)
    filtered: set[Path] = set()
    for raw_candidate in candidates:
        if (
            os.name == "nt"
            and len(raw_candidate) >= 3
            and raw_candidate[0] == "/"
            and raw_candidate[1].isalpha()
            and raw_candidate[2] == "/"
        ):
            raw_candidate = f"{raw_candidate[1]}:{raw_candidate[2:]}"
        candidate = Path(raw_candidate).expanduser()
        if not candidate.is_absolute():
            candidate = Path.cwd() / candidate
        candidate = candidate.resolve()
        try:
            relative_path = candidate.relative_to(source_root).as_posix()
        except ValueError:
            filtered.add(candidate)
            continue
        if _is_configured_source(relative_path, config):
            filtered.add(candidate)
    return sorted(filtered, key=lambda path: path.as_posix().casefold())


def discover_sources(config_path: Path, source_root_override: str | None) -> tuple[Path, list[Path]]:
    config = _load_config(config_path)
    source_root = _resolve_source_root(config, config_path, source_root_override)

    include_patterns = config.get("include") or ["**/*"]
    discovered: set[Path] = set()
    for pattern in include_patterns:
        for candidate in _included_candidates(source_root, pattern):
            if not candidate.is_file():
                continue
            relative_path = candidate.relative_to(source_root).as_posix()
            if not _is_configured_source(relative_path, config):
                continue
            discovered.add(candidate.resolve())

    sorted_files = sorted(discovered, key=lambda path: path.as_posix().casefold())
    files_by_name: dict[str, list[Path]] = defaultdict(list)
    for source_file in sorted_files:
        files_by_name[source_file.name.casefold()].append(source_file)
    collisions = [files for files in files_by_name.values() if len(files) > 1]
    if collisions:
        details = "; ".join(
            ", ".join(str(path.relative_to(source_root)) for path in files)
            for files in collisions
        )
        raise ValueError(
            "duplicate source basenames would overwrite docs/_shared artifacts: " + details
        )

    return source_root, sorted_files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--source-root")
    parser.add_argument(
        "--filter-candidates",
        action="store_true",
        help="read candidate paths from stdin and apply configured rules under source_root",
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = REPO_ROOT / config_path

    try:
        if args.filter_candidates:
            files = filter_candidates(
                config_path.resolve(),
                args.source_root,
                [line for line in (line.strip() for line in sys.stdin) if line],
            )
            source_root = None
        else:
            source_root, files = discover_sources(config_path.resolve(), args.source_root)
    except (OSError, ValueError, yaml.YAMLError) as error:
        parser.error(str(error))

    if source_root is not None:
        print(source_root)
    for source_file in files:
        print(source_file)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())