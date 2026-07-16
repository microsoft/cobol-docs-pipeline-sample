"""Mechanical QA checks for phase-K group AFU (functional analysis). SCAFFOLD.

Planned checks (mirror .github/skills/qa-reviewer/scripts/check-functional-analysis.py):
  - Group profile auto-detect parity: detected profile (default /
    defaulthes the bundle's
    declared profile.
  - Every cited `GRP-<group_id>-REQ-NNN` id resolves in the matching
    `docs/<lang>/_groups/<group_id>/requirements.md`.
  - Member coverage: every member in config/grouping.yaml is covered by
    at least one section in the group functional-analysis.md.
  - Citations to per-file `docs/<lang>/<member>/functional-analysis.md`
    are well-formed; no raw source citations.
  - No forbidden tokens in Summary / Purpose paragraphs.
  - Output a findings[] JSON sidecar at
    docs/_reviews/group-functional-analysis/<group_id>__<section_id>__<language>.json
    (per-section scope) or
    docs/_reviews/group-functional-analysis/<group_id>__<language>.json
    (per-group scope).

Until implemented this scaffold exits non-zero so the new phase K
surfaces the gap.
"""

from __future__ import annotations

import sys


def main() -> int:
    sys.stderr.write(
        "check-group-functional-analysis.py: scaffold \u2014 phase-K group "
        "AFU QA checks are not implemented yet. Mirror "
        ".github/skills/qa-reviewer/scripts/check-functional-analysis.py.\n"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
