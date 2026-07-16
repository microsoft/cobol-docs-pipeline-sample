"""Slice per-group requirement bundles into per-section bundles for phase J.

SCAFFOLD — not yet implemented.

Planned behaviour:
  - Load `config/grouping.yaml` and select the requested `<group_id>`.
  - Read the staged group payload (members' requirements.md excerpts +
    group complete.md excerpts + auto-detected profile).
  - Fan into per-section bundles
    `docs/_shared/_groups/<group_id>/_req-group-bundles/<section_id>.bundle.{json,md}`
    so phase J.2 can author sections in parallel.

Mirror `.github/skills/requirements-writer/scripts/stage-bundles.py`.
"""

from __future__ import annotations

import sys


def main() -> int:
    sys.stderr.write(
        "stage-bundles.py: scaffold \u2014 phase-J per-section bundle slicer "
        "is not implemented yet. Mirror "
        ".github/skills/requirements-writer/scripts/stage-bundles.py.\n"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
