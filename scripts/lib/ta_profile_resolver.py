#!/usr/bin/env python3
"""Resolve the technical-analysis (ATE) profile for one source file.

Mirrors `fa_profile_resolver` but points at
`config/templates/docs/technical-analysis/` and its profile family.

Auto-detection rules (in evaluation order):
  1. `.cpy` / `.bms`                                  -> SKIP   (no ATE doc)
  2. `.jcl` / `.prc`                                  -> ate-org-interfaccia
  3. `.cbl` / `.cob` AND (exec_cics OR bms_maps_used) -> ate-org-applicazione
  4. `.cbl` / `.cob`                                  -> ate-org-interfaccia
  5. anything else                                    -> default

The workspace-level `technical_analysis_profile` in `config/pipeline.yaml`
is used as a fallback when auto-detection yields `default` and the user
configured something more specific.

Consumed by the technical-analysis staging scripts so a single source of
truth governs which profile a file gets.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
TA_ROOT = REPO_ROOT / "config" / "templates" / "docs" / "technical-analysis"
SOURCES_YAML = REPO_ROOT / "config" / "pipeline.yaml"

# Sentinel value returned when the file should not get an ATE document at all.
SKIP = "__skip__"

KNOWN_PROFILES: tuple[str, ...] = (
    "default",
    "ate-org-applicazione",
    "ate-org-interfaccia",
)


@dataclass(frozen=True)
class TAResolution:
    """Outcome of profile resolution for ONE source file."""

    profile: str            # one of KNOWN_PROFILES or SKIP
    profile_dir: Path | None
    reason: str             # short human-readable explanation
    skipped: bool

    def to_dict(self) -> dict:
        return {
            "profile": self.profile,
            "profile_dir": str(self.profile_dir.relative_to(REPO_ROOT)).replace("\\", "/")
                if self.profile_dir else None,
            "reason": self.reason,
            "skipped": self.skipped,
        }


def _has_nonempty(facts: dict, *keys: str) -> bool:
    for k in keys:
        v = facts.get(k)
        if isinstance(v, list) and len(v) > 0:
            return True
        if isinstance(v, dict) and len(v) > 0:
            return True
    return False


def _workspace_default() -> str:
    if not SOURCES_YAML.exists():
        return "default"
    cfg = yaml.safe_load(SOURCES_YAML.read_text(encoding="utf-8")) or {}
    name = cfg.get("technical_analysis_profile") or "default"
    return name if name in KNOWN_PROFILES else "default"


def _profile_dir(name: str) -> Path | None:
    if name == SKIP:
        return None
    p = TA_ROOT / name
    return p if p.exists() else None


def resolve_profile_dir(name: str, *, fallback_to_default: bool = True) -> tuple[str, Path | None, str | None]:
    """Resolve a TA profile name to an existing directory."""
    profile_dir = _profile_dir(name)
    if profile_dir is not None:
        return name, profile_dir, None

    if fallback_to_default and name != "default":
        default_dir = _profile_dir("default")
        if default_dir is not None:
            return (
                "default",
                default_dir,
                f"requested profile '{name}' is not available under config/templates/docs/technical-analysis; using 'default'",
            )

    return name, None, None


def resolve(source_path: Path, facts: dict | None = None) -> TAResolution:
    """Decide which ATE profile to use for `source_path`.

    `facts` is the loaded `docs/_shared/<file>/facts.json` dict (optional —
    when not supplied, CICS/BMS heuristics are skipped and we fall back on the
    extension-only branch).
    """
    facts = facts or {}
    ext = source_path.suffix.lower()
    name = source_path.name

    if ext in (".cpy",):
        return TAResolution(SKIP, None, f"{name}: copybook — no ATE document produced", True)
    if ext in (".bms",):
        return TAResolution(SKIP, None, f"{name}: BMS mapset — no ATE document produced", True)

    if ext in (".jcl", ".prc", ".cl", ".clp", ".clle"):
        profile_name, profile_dir, note = resolve_profile_dir("ate-org-interfaccia")
        return TAResolution(
            profile_name,
            profile_dir,
            f"{name}: JCL/PROC or IBM i CL -> interfaccia profile" + (f"; {note}" if note else ""),
            False,
        )

    if ext in (".cbl", ".cob", ".cblle", ".sqlcblle"):
        if _has_nonempty(facts, "exec_cics", "bms_maps_used", "bms_maps"):
            profile_name, profile_dir, note = resolve_profile_dir("ate-org-applicazione")
            return TAResolution(
                profile_name,
                profile_dir,
                f"{name}: COBOL with CICS/BMS -> applicazione profile" + (f"; {note}" if note else ""),
                False,
            )
        profile_name, profile_dir, note = resolve_profile_dir("ate-org-interfaccia")
        return TAResolution(
            profile_name,
            profile_dir,
            f"{name}: batch CBL (no CICS/BMS) -> interfaccia profile" + (f"; {note}" if note else ""),
            False,
        )

    fallback = _workspace_default()
    effective_name, profile_dir, note = resolve_profile_dir(fallback)
    return TAResolution(
        effective_name,
        profile_dir,
        f"{name}: unrecognized extension '{ext}' -> workspace default '{fallback}'" + (f"; {note}" if note else ""),
        False,
    )


def resolve_for_group(members: Iterable[Path]) -> TAResolution:
    """Decide which ATE profile a GROUP gets.

    Rule (mirrors phases J/K group auto-detection):
      - any CICS/BMS member (by extension)             -> ate-org-applicazione
      - else any JCL/PRC member                        -> ate-org-interfaccia
      - else                                           -> default
    Copybook-only / BMS-only groups still get `default` (a group always
    produces a document, unlike a standalone copybook).
    """
    exts = [p.suffix.lower() for p in members]
    if any(e == ".bms" for e in exts):
        profile_name, profile_dir, note = resolve_profile_dir("ate-org-applicazione")
        return TAResolution(
            profile_name,
            profile_dir,
            "group has BMS member -> applicazione profile" + (f"; {note}" if note else ""),
            False,
        )
    if any(e in (".jcl", ".prc", ".cl", ".clp", ".clle") for e in exts):
        profile_name, profile_dir, note = resolve_profile_dir("ate-org-interfaccia")
        return TAResolution(
            profile_name,
            profile_dir,
            "group has JCL/PROC or IBM i CL member -> interfaccia profile" + (f"; {note}" if note else ""),
            False,
        )
    return TAResolution(
        "default", _profile_dir("default"),
        "group default profile", False,
    )


def load_profile_yaml(profile_dir: Path) -> dict:
    """Load `profile.yaml` from a profile directory."""
    p = profile_dir / "profile.yaml"
    if not p.exists():
        raise FileNotFoundError(f"profile.yaml missing under {profile_dir}")
    return yaml.safe_load(p.read_text(encoding="utf-8")) or {}


def template_paths(profile_dir: Path, languages: Iterable[str]) -> dict[str, Path]:
    """Return the template file each language should use.

    Resolution order, per language `<lang>`:
      1. `template.<lang>.md`
      2. `template.md` (fallback)
    """
    out: dict[str, Path] = {}
    fallback = profile_dir / "template.md"
    for lang in languages:
        cand = profile_dir / f"template.{lang}.md"
        if cand.exists():
            out[lang] = cand
        elif fallback.exists():
            out[lang] = fallback
        else:
            raise FileNotFoundError(
                f"No template.{lang}.md or template.md under {profile_dir}"
            )
    return out


def flatten_sections(profile: dict) -> list[dict]:
    """Flatten profile.sections (with subsections) into a single ordered list."""
    out: list[dict] = []
    for top in profile.get("sections") or []:
        spec = dict(top)
        spec["_id_path"] = (top["id"],)
        spec["_parent_id"] = None
        out.append(spec)
        for sub in top.get("subsections") or []:
            sub_spec = dict(sub)
            sub_spec["_id_path"] = (top["id"], sub["id"])
            sub_spec["_parent_id"] = top["id"]
            out.append(sub_spec)
    return out


__all__ = [
    "SKIP",
    "KNOWN_PROFILES",
    "TA_ROOT",
    "TAResolution",
    "resolve_profile_dir",
    "resolve",
    "resolve_for_group",
    "load_profile_yaml",
    "template_paths",
    "flatten_sections",
]
