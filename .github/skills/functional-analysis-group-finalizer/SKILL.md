---
name: functional-analysis-group-finalizer
description: |
  Phase-K per-group AFU finalizer for ONE group declared in
  `config/grouping.yaml`. LLM-driven. SCAFFOLD.

  Reads
    `docs/_shared/_groups/<group_id>/_fa-group-bundles/_finalize.bundle.{json,md}`
  and every per-section draft under
    `docs/_shared/_groups/<group_id>/_fa-group-sections/<lang>/*.md`
  then emits
    `docs/<lang>/_groups/<group_id>/functional-analysis.md`
  per requested language.
argument-hint: <group_id> <_finalize.bundle.md path> [target_languages]
---

> **Status:** scaffold. Mirror `.github/skills/functional-analysis-finalizer/`
> at group scope.

# Scope

Phase-K finalizer step only. Authoring of per-section drafts is owned by
`functional-analysis-group-writer`.

# Inputs

- `docs/_shared/_groups/<group_id>/_fa-group-bundles/_finalize.bundle.json` (authoritative)
- `docs/_shared/_groups/<group_id>/_fa-group-bundles/_finalize.bundle.md` (LLM-facing)
- `docs/_shared/_groups/<group_id>/_fa-group-sections/<lang>/*.md`

# Outputs

- `docs/<lang>/_groups/<group_id>/functional-analysis.md`

Finalize exactly `bundle.languages` in declared order at `bundle.output_paths`.
Never require or create an unrequested English edition or intermediate.
Check structural parity only when multiple languages are requested.

# Determinism rules

- Section order in the finalized file follows the bundle's `section_order[]`.
- Citations to `GRP-<group_id>-REQ-NNN` must resolve in the matching
  `docs/<lang>/_groups/<group_id>/requirements.md`.
