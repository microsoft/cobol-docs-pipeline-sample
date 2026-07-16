"""Assemble per-group requirement finalize bundle for phase J (per-group scope).

SCAFFOLD — not yet implemented.

Planned behaviour:
  - For a given `<group_id>`, project all per-section drafts +
    config/grouping.yaml metadata + active ATE profile into
      docs/_shared/_groups/<group_id>/_req-group-bundles/_finalize.bundle.{json,md}

Mirror `.github/skills/requirements-finalizer/scripts/assemble-inputs.py`.
"""

from __future__ import annotations

import sys


def main() -> int:
    sys.stderr.write(
        "assemble-inputs.py: scaffold \u2014 phase-J per-group finalize "
        "bundle assembler is not implemented yet. Mirror "
        ".github/skills/requirements-finalizer/scripts/assemble-inputs.py.\n"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
