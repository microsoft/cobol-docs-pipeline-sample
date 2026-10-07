"""Select group narrative inputs using the upstream per-file skip decisions."""
from __future__ import annotations

import json
from pathlib import Path


def select_members(
    repo_root: Path, members: list[str], scope: str
) -> tuple[list[str], list[dict[str, str]]]:
    eligible = []
    skipped = []
    for member in members:
        basename = Path(member).name
        marker = repo_root / "docs" / "_shared" / basename / f"_{scope}-bundles" / "_skipped.json"
        if Path(member).suffix.lower() == ".prc":
            reason = "PRC generation is disabled upstream"
        elif marker.is_file():
            # The per-file stager removes this marker when an explicit profile
            # enables generation again. Old Markdown must not override it.
            decision = json.loads(marker.read_text(encoding="utf-8"))
            reason = decision["reason"]
        else:
            eligible.append(member)
            continue
        skipped.append({"source_path": member.replace("\\", "/"), "reason": reason})
    return eligible, skipped
