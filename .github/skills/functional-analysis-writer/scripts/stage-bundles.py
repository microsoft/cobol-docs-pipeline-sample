#!/usr/bin/env python3
"""Bulk pre-stage all per-FA-section bundles for ONE source.

For each section in the auto-detected (or `--profile-name`-overridden) FA
profile's `profile.yaml`, invoke the deterministic `assemble-inputs.py` packager
and write `docs/_shared/<file>/_fa-bundles/<section_id>.bundle.json`.

Also writes a tombstone at `_fa-bundles/_skipped.json` when the file is opted
out of FA (copybook / BMS) so downstream phase-G steps can no-op cleanly.

Exit codes:
  0  ok (or skipped)
  1  one or more sections failed to package
  4  missing prerequisite (facts.json / profile)
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SKILL_ROOT.parents[2]
ASSEMBLE_PY = SKILL_ROOT / "scripts" / "assemble-inputs.py"
DOC_ROOT = REPO_ROOT / "docs" / "_shared"
SOURCES_YAML = REPO_ROOT / "config" / "sources.yaml"

sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))
import fa_profile_resolver as fpr  # noqa: E402

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_MISSING_PREREQ = 4


def load_source_root(override: str | None) -> Path:
    cfg = yaml.safe_load(SOURCES_YAML.read_text(encoding="utf-8")) if SOURCES_YAML.exists() else {}
    raw = override or (cfg or {}).get("source_root", "./samples")
    p = Path(raw)
    return p if p.is_absolute() else (REPO_ROOT / p).resolve()


def resolve_source(source: str, source_root: Path) -> Path:
    p = Path(source)
    if p.is_absolute() and p.exists():
        return p
    for cand in [REPO_ROOT / p, source_root / p]:
        cand = cand.resolve()
        if cand.exists():
            return cand
    raise SystemExit(f"ERROR: source not found: {source}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Bulk pre-stage per-FA-section bundles for ONE source.")
    ap.add_argument("--source", required=True)
    ap.add_argument("--languages", default="en")
    ap.add_argument("--profile-name", default=None)
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--bundles-dir", default=None)
    ap.add_argument("--prune", action="store_true",
                    help="delete stale FA bundle files whose section_id no longer exists in the profile.")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if not ASSEMBLE_PY.exists():
        print(f"ERROR: cannot find assemble-inputs.py at {ASSEMBLE_PY}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    source_root = load_source_root(args.source_root)
    source_path = resolve_source(args.source, source_root)
    doc_dir = DOC_ROOT / source_path.name
    facts_path = doc_dir / "facts.json"
    if not facts_path.exists():
        print(f"ERROR: missing facts.json — run phase B first: {facts_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    facts = json.loads(facts_path.read_text(encoding="utf-8"))

    bundles_dir = Path(args.bundles_dir) if args.bundles_dir else (doc_dir / "_fa-bundles")
    if not bundles_dir.is_absolute():
        bundles_dir = (REPO_ROOT / bundles_dir).resolve()
    bundles_dir.mkdir(parents=True, exist_ok=True)

    # Profile resolution + skip path.
    if args.profile_name:
        if args.profile_name not in fpr.KNOWN_PROFILES:
            print(f"ERROR: unknown profile: {args.profile_name}", file=sys.stderr)
            return EXIT_MISSING_PREREQ
        profile_dir = fpr.FA_ROOT / args.profile_name
        resolution = fpr.FAResolution(args.profile_name, profile_dir,
                                      f"explicit --profile-name={args.profile_name}", False)
    else:
        resolution = fpr.resolve(source_path, facts)

    skip_marker = bundles_dir / "_skipped.json"
    if resolution.skipped:
        skip_marker.write_text(
            json.dumps({"reason": resolution.reason, "source": source_path.name}, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"SKIP: {source_path.name}: {resolution.reason}  ->  {skip_marker.relative_to(REPO_ROOT)}")
        return EXIT_OK
    # Clear any stale tombstone (e.g. .cpy renamed to .cbl).
    if skip_marker.exists():
        skip_marker.unlink()

    assert resolution.profile_dir is not None
    profile = fpr.load_profile_yaml(resolution.profile_dir)
    sections = [s for s in fpr.flatten_sections(profile) if s.get("id") != "header"]

    expected_names: set[str] = set()
    ok = 0
    failed: list[tuple[str, int, str]] = []
    for spec in sections:
        sid = spec["id"]
        out_name = f"{sid}.bundle.json"
        expected_names.add(out_name)
        out_path = bundles_dir / out_name
        if not args.force and out_path.exists():
            # Up-to-date check is light: section id present + profile_name match.
            try:
                existing = json.loads(out_path.read_text(encoding="utf-8"))
                if (existing.get("section", {}).get("id") == sid
                        and existing.get("profile_name") == resolution.profile
                        and existing.get("languages") == [l for l in (["en"] + [x.strip() for x in args.languages.split(",") if x.strip() and x.strip() != "en"])]):
                    ok += 1
                    continue
            except (OSError, ValueError):
                pass
        argv = [
            sys.executable, str(ASSEMBLE_PY),
            "--source", str(source_path),
            "--section-id", sid,
            "--profile-name", resolution.profile,
            "--languages", args.languages,
            "--source-root", str(source_root),
            "--out", str(out_path),
        ]
        res = subprocess.run(argv, capture_output=True, text=True)
        if res.returncode != 0:
            failed.append((sid, res.returncode, (res.stderr or res.stdout or "").strip()))
        else:
            ok += 1

    pruned = 0
    if args.prune:
        for f in sorted(bundles_dir.glob("*.bundle.json")):
            if f.name not in expected_names and f.name != "_skipped.json":
                f.unlink()
                pruned += 1
                md = f.with_suffix(".md")
                if md.exists():
                    md.unlink()

    total = len(sections)
    print(f"DONE {source_path.name}: profile={resolution.profile} total={total} ok={ok} "
          f"failed={len(failed)} pruned={pruned}  ->  {bundles_dir.relative_to(REPO_ROOT)}")
    if failed:
        for sid, code, msg in failed[:20]:
            short = (msg or "").splitlines()[-1] if msg else ""
            print(f"  [{code}] {sid}  {short}", file=sys.stderr)
        return EXIT_FAIL
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
