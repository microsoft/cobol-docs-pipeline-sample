#!/usr/bin/env python3
"""Fan-out qa-reviewer/check-section-doc.py across every existing section MD
for one source.

Walks `docs/<lang>/<file>/sections/` for each requested language and runs the
deterministic mechanical checker on every found `.md`. Aggregates verdicts
and exits non-zero if any error-severity finding is present.

This is the per-source closer for phase-C section-doc QA: per-section MDs
are reviewed individually as they are authored, and this script provides
the end-of-source sweep + summary the orchestrator + CI consume.

Exit codes:
  0  all reviewed MDs are ok (warns allowed)
  1  >= 1 MD has error findings (per-MD detail printed)
  4  missing prerequisite
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
CHECKER_PY = SKILL_ROOT / "scripts" / "check-section-doc.py"
SOURCES_YAML = REPO_ROOT / "config" / "sources.yaml"

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
    ap = argparse.ArgumentParser(description="Review every section MD for one source across languages.")
    ap.add_argument("--source", required=True)
    ap.add_argument("--languages", default="en")
    ap.add_argument("--source-root", default=None)
    ap.add_argument("--profile", default=None)
    args = ap.parse_args()

    if not CHECKER_PY.exists():
        print(f"ERROR: cannot find check-section-doc.py at {CHECKER_PY}", file=sys.stderr)
        return EXIT_MISSING_PREREQ

    source_root = load_source_root(args.source_root)
    source_path = resolve_source(args.source, source_root)
    doc_dir = REPO_ROOT / "docs" / "_shared" / source_path.name
    idx_path = doc_dir / "chunks" / "index.json"
    if not idx_path.exists():
        print(f"ERROR: missing chunks/index.json — run chunk-text-extraction first: {idx_path}", file=sys.stderr)
        return EXIT_MISSING_PREREQ
    chunks_index = json.loads(idx_path.read_text(encoding="utf-8"))
    file_to_id = {Path(c["file"]).stem: c["id"] for c in chunks_index.get("chunks") or []}

    languages = [s.strip() for s in args.languages.split(",") if s.strip()]
    if "en" not in languages:
        languages.insert(0, "en")

    totals = {"reviewed": 0, "ok": 0, "fail": 0, "missing": 0}
    failures: list[tuple[str, str, list[dict]]] = []

    for lang in languages:
        sections_dir = REPO_ROOT / "docs" / lang / source_path.name / "sections"
        if not sections_dir.exists():
            print(f"WARN: no sections directory for {lang}: {sections_dir.relative_to(REPO_ROOT)}")
            continue
        for md_path in sorted(sections_dir.glob("*.md")):
            stem = md_path.stem
            cid = file_to_id.get(stem)
            if not cid:
                totals["missing"] += 1
                print(f"WARN: orphan MD has no chunk_id mapping: {md_path.name}", file=sys.stderr)
                continue
            argv = [sys.executable, str(CHECKER_PY),
                    "--section-doc", str(md_path),
                    "--source", str(source_path),
                    "--chunk-id", cid,
                    "--language", lang,
                    "--source-root", str(source_root)]
            if args.profile:
                argv += ["--profile", args.profile]
            res = subprocess.run(argv, capture_output=True, text=True)
            totals["reviewed"] += 1
            if res.returncode == 0:
                totals["ok"] += 1
            else:
                totals["fail"] += 1
                # Try to load the sidecar that was written so we can show top finding.
                review_name = f"{source_path.name}__{cid.replace('/', '__')}__{lang}.json"
                review_path = REPO_ROOT / "docs" / "_reviews" / "section-doc" / review_name
                top: list[dict] = []
                if review_path.exists():
                    try:
                        sidecar = json.loads(review_path.read_text(encoding="utf-8"))
                        top = [f for f in sidecar.get("findings") or [] if f.get("severity") == "error"][:3]
                    except (OSError, ValueError, json.JSONDecodeError):
                        pass
                failures.append((lang, md_path.name, top))

    print(f"DONE {source_path.name}: reviewed={totals['reviewed']} ok={totals['ok']} "
          f"fail={totals['fail']} missing={totals['missing']} languages={','.join(languages)}")
    if failures:
        for lang, name, top in failures[:20]:
            print(f"  FAIL [{lang}] {name}")
            for f in top:
                print(f"      [{f.get('code')}] L{f.get('line', 0)}  {f.get('message','')}")
        return EXIT_FAIL
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
