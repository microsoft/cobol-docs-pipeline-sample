---
name: requirements-group-finalizer
description: |
  Phase-J per-group ATE finalizer for ONE group declared in
  `config/grouping.yaml`. LLM-driven. SCAFFOLD.

  Reads
    `docs/_shared/_groups/<group_id>/_req-group-bundles/_finalize.bundle.{json,md}`
  and every per-section draft under
    `docs/_shared/_groups/<group_id>/_req-group-sections/<lang>/*.md`
  then emits
    `docs/<lang>/_groups/<group_id>/requirements.md`
  per requested language.
argument-hint: <group_id> <_finalize.bundle.md path> [target_languages]
---

> **Status:** scaffold. Mirror `.github/skills/requirements-finalizer/`
> at group scope.

# Scope

Phase-J finalizer step only. Authoring of per-section drafts is owned by
`requirements-group-writer`.

# Inputs

- `docs/_shared/_groups/<group_id>/_req-group-bundles/_finalize.bundle.json` (authoritative)
- `docs/_shared/_groups/<group_id>/_req-group-bundles/_finalize.bundle.md` (LLM-facing)
- `docs/_shared/_groups/<group_id>/_req-group-sections/<lang>/*.md`

# Outputs

- `docs/<lang>/_groups/<group_id>/requirements.md`

Finalize exactly `bundle.languages` in declared order at `bundle.output_paths`.
Never require or create an unrequested English edition or intermediate.
Check structural parity only when multiple languages are requested.

# Determinism rules

- Section order in the finalized file follows the bundle's `section_order[]`.
- Requirement ids are taken verbatim from per-section drafts; no
  renumbering across sections.
- Cross-cutting "Group summary" header includes member list verbatim
  from `config/grouping.yaml`.
