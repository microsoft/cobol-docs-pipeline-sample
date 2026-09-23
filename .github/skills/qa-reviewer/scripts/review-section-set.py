#!/usr/bin/env python3
"""Review the complete indexed section set for one source.

Require one markdown and an authoritative bundle per chunk and requested
language before running check-section-doc.py. Languages follow pipeline.yaml
unless explicitly overridden with --languages.

This is the per-source closer for phase-C section-doc QA: per-section MDs
are reviewed individually as they are authored, and this script provides
the end-of-source sweep + summary the orchestrator + CI consume.

Exit codes:
  0  complete section set reviewed successfully (warns allowed)
  1  content findings or an unexpected checker failure
  2  invalid configuration or CLI arguments
  4  missing or invalid prerequisite (including incomplete/orphan sections)
  5  stale source or bundle

For mixed checker failures, missing prerequisites take precedence over stale
inputs, which take precedence over content failures. Child diagnostics and
exit codes are printed; old review sidecars are never used as current results.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SKILL_ROOT.parents[2]
CHECKER_PY = SKILL_ROOT / "scripts" / "check-section-doc.py"
SOURCES_YAML = REPO_ROOT / "config" / "pipeline.yaml"
_spec = importlib.util.spec_from_file_location(
    "output_languages", REPO_ROOT / "scripts" / "tools" / "resolve-output-languages.py"
)
assert _spec and _spec.loader
_languages = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_languages)

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_MISSING_PREREQ = 4
EXIT_STALE = 5


def load_source_root(override: str | None) -> Path:
    cfg = yaml.safe_load(SOURCES_YAML.read_text(encoding="utf-8"))
    if not isinstance(cfg, dict):
        raise ValueError(f"pipeline configuration must be a mapping: {SOURCES_YAML}")
    raw = override if override is not None else cfg.get("source_root", "./samples")
    if not isinstance(raw, str) or not raw.strip():
        raise ValueError("source_root must be a non-empty path string")
    p = Path(raw)
    return (REPO_ROOT / p).resolve()


def resolve_source(source: str, source_root: Path) -> Path:
    p = Path(source)
    for cand in [REPO_ROOT / p, source_root / p]:
        cand = cand.resolve()
        if cand.is_file():
            return cand
    raise FileNotFoundError(f"source not found: {source}")


def read_json_object(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as error:
        raise ValueError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object in {path}")
    return value


def load_review_inputs(source_path: Path, languages: list[str]) -> list[tuple[str, Path, Path]]:
    doc_dir = REPO_ROOT / "docs" / "_shared" / source_path.name
    idx_path = doc_dir / "chunks" / "index.json"
    chunks = read_json_object(idx_path).get("chunks")
    if not isinstance(chunks, list) or not chunks:
        raise ValueError(f"no chunks to review in {idx_path}; run chunk-text-extraction")
    file_to_id: dict[str, str] = {}
    ids: set[str] = set()
    for chunk in chunks:
        if not isinstance(chunk, dict):
            raise ValueError(f"invalid chunk entry in {idx_path}")
        cid, filename = chunk.get("id"), chunk.get("file")
        if not isinstance(cid, str) or not cid.strip() or not isinstance(filename, str):
            raise ValueError(f"chunk entries need non-empty id and file strings in {idx_path}")
        if Path(filename).name != filename or Path(filename).suffix != ".txt":
            raise ValueError(f"invalid chunk filename {filename!r} in {idx_path}")
        stem = Path(filename).stem
        if stem in file_to_id or cid in ids:
            raise ValueError(f"duplicate chunk id or filename in {idx_path}: {cid!r}, {filename!r}")
        file_to_id[stem] = cid
        ids.add(cid)

    for lang in languages:
        sections_dir = REPO_ROOT / "docs" / lang / source_path.name / "sections"
        if not sections_dir.is_dir():
            raise FileNotFoundError(f"missing sections directory for {lang}: {sections_dir}")
        for stem in sorted(file_to_id):
            md_path = sections_dir / f"{stem}.md"
            if not md_path.is_file():
                raise FileNotFoundError(f"missing section markdown for {lang}: {md_path}")
        for md_path in sorted(sections_dir.glob("*.md")):
            if md_path.stem not in file_to_id:
                raise ValueError(f"orphan MD has no chunk_id mapping: {md_path}")

    inputs: list[tuple[str, Path, Path]] = []
    for stem, cid in sorted(file_to_id.items()):
        bundle_path = doc_dir / "_bundles" / f"{stem}.bundle.json"
        bundle = read_json_object(bundle_path)
        source = bundle.get("source_path")
        chunk = bundle.get("chunk")
        if (
            not isinstance(source, str) or (REPO_ROOT / source).resolve() != source_path
            or not isinstance(chunk, dict) or chunk.get("id") != cid
        ):
            raise ValueError(f"bundle source/chunk mismatch: {bundle_path}; re-run stage-bundles.py")
        if not isinstance(bundle.get("facts_slice"), dict):
            raise ValueError(f"bundle missing facts_slice: {bundle_path}; re-run stage-bundles.py")
        outputs = bundle.get("output_paths")
        if not isinstance(outputs, dict):
            raise ValueError(f"bundle missing output_paths: {bundle_path}; re-run stage-bundles.py")
        for lang in languages:
            md_path = REPO_ROOT / "docs" / lang / source_path.name / "sections" / f"{stem}.md"
            output = outputs.get(lang)
            if not isinstance(output, str) or (REPO_ROOT / output).resolve() != md_path.resolve():
                raise ValueError(
                    f"bundle output mismatch for {lang}: {bundle_path}; re-run stage-bundles.py"
                )
            inputs.append((lang, md_path, bundle_path))
    return inputs


def main() -> int:
    ap = argparse.ArgumentParser(description="Review the complete section set for one source across languages.")
    ap.add_argument("--source", required=True)
    ap.add_argument("--languages", default=None,
                    help="comma-separated override; defaults to pipeline.yaml output.languages, then en")
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--profile", default=None)
    args = ap.parse_args()

    try:
        languages = _languages.resolve_languages(SOURCES_YAML, args.languages)[0].split(",")
        source_root = load_source_root(args.source_root)
    except (OSError, ValueError, yaml.YAMLError) as error:
        ap.error(str(error))

    if not CHECKER_PY.is_file():
        print(f"ERROR: cannot find check-section-doc.py at {CHECKER_PY}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    try:
        source_path = resolve_source(args.source, source_root)
        manifest_path = REPO_ROOT / "docs" / "_shared" / source_path.name / "chunk-manifest.json"
        manifest = read_json_object(manifest_path)
        if manifest.get("sha256") != hashlib.sha256(source_path.read_bytes()).hexdigest():
            print(f"STALE: source differs from {manifest_path}; re-run cobol-chunking", file=sys.stderr)
            return EXIT_STALE
        inputs = load_review_inputs(source_path, languages)
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    totals = {"reviewed": 0, "ok": 0, "fail": 0}
    failure_codes: set[int] = set()
    for lang, md_path, bundle_path in inputs:
        argv = [sys.executable, str(CHECKER_PY),
                "--bundle", str(bundle_path),
                "--language", lang,
                "--source-root", str(source_root)]
        if args.profile:
            argv += ["--profile", args.profile]
        try:
            res = subprocess.run(
                argv, capture_output=True, text=True, encoding="utf-8", errors="replace",
                env={**os.environ, "PYTHONIOENCODING": "utf-8"},
            )
        except OSError as error:
            print(f"ERROR: cannot launch checker for [{lang}] {md_path}: {error}", file=sys.stderr)
            return EXIT_MISSING_PREREQ
        totals["reviewed"] += 1
        if res.returncode == 0:
            totals["ok"] += 1
        else:
            totals["fail"] += 1
            failure_codes.add(res.returncode)
            print(f"  FAIL [{lang}] {md_path.name} (exit={res.returncode})")
        if res.stdout:
            print(res.stdout, end="")
        if res.stderr:
            print(res.stderr, end="", file=sys.stderr)

    print(f"DONE {source_path.name}: reviewed={totals['reviewed']} ok={totals['ok']} "
          f"fail={totals['fail']} missing=0 languages={','.join(languages)}")
    for code in (EXIT_MISSING_PREREQ, EXIT_STALE):
        if code in failure_codes:
            return code
    return EXIT_FAIL if failure_codes else EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
