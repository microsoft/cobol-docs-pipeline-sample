"""Mechanical QA checks for phase-J group ATE (requirements). SCAFFOLD.

Planned checks (mirror .github/skills/qa-reviewer/scripts/check-requirements.py):
  - Group requirement ids are namespaced `GRP-<group_id>-REQ-NNN`
    (zero-padded to 3) with no duplicates or gaps.
  - Group profile auto-detect parity: detected profile (default /
    ate-org-applicazione / ate-org-interfaccia) matches the bundle's
    declared profile.
  - Member coverage: every member in config/grouping.yaml is cited at
    least once in the group requirements.md.
  - Citations resolve to per-file `docs/<lang>/<member>/requirements.md`,
    never to raw source.
  - No forbidden tokens in Summary / Purpose paragraphs.
  - Output a findings[] JSON sidecar at
    docs/_reviews/group-requirements/<group_id>__<section_id>__<language>.json
    (per-section scope) or
    docs/_reviews/group-requirements/<group_id>__<language>.json
    (per-group scope).

Until implemented this scaffold exits non-zero so the new phase J
surfaces the gap.
"""

from __future__ import annotations

import sys


def main() -> int:
    sys.stderr.write(
        "check-group-requirements.py: scaffold \u2014 phase-J group ATE "
        "QA checks are not implemented yet. Mirror "
        ".github/skills/qa-reviewer/scripts/check-requirements.py.\n"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
