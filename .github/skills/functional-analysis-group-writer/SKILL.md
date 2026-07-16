---
name: functional-analysis-group-writer
description: |
  Author phase-K group AFU (functional-analysis) markdown for ONE group
  declared in `config/grouping.yaml`. LLM-driven. SCAFFOLD.

  Two scopes:
    Per-section — writes one per-language draft into
      `docs/_shared/_groups/<group_id>/_fa-group-sections/<lang>/<section_id>.md`
      from a prepared bundle
      `docs/_shared/_groups/<group_id>/_fa-group-bundles/<section_id>.bundle.{json,md}`.
    Per-group finalizer — stitches the per-section drafts into
      `docs/<lang>/_groups/<group_id>/functional-analysis.md` per requested language.

  Reuses the existing per-file AFU profile family under
  `config/templates/docs/functional-analysis/`:
    - `default`
    - `afu-org-applicazione`  (auto-selected when any group member is CICS/BMS)
    - `afu-org-interfaccia`   (auto-selected when any group member is JCL/PRC with batch CBL)
argument-hint: <group_id> <bundle.bundle.md path> [target_languages]
---

> **Status:** scaffold — Day-1 contracts only. Mirrors per-file
> `functional-analysis-writer` at group scope.

# Scope

Owns phase-K authoring at the group level. One invocation per section
(per-section scope) or per group (finalizer scope), each covering EN
plus every requested translation language.

Sibling skills:
- `functional-analysis-writer` — per-file AFU (phase G).
- `requirements-group-writer` — group ATE (phase J).
- `group-doc-finalizer` — group `index.md` / `complete.md` (phase I).

# Inputs

Per-section scope:
- `docs/_shared/_groups/<group_id>/_fa-group-bundles/<section_id>.bundle.json` (authoritative)
- `docs/_shared/_groups/<group_id>/_fa-group-bundles/<section_id>.bundle.md` (LLM-facing)

Per-group finalizer scope:
- `docs/_shared/_groups/<group_id>/_fa-group-bundles/_finalize.bundle.{json,md}`
- Every per-section draft under
  `docs/_shared/_groups/<group_id>/_fa-group-sections/<lang>/*.md`

Bundles aggregate, per group:
- Each member's `docs/<lang>/<member>/functional-analysis.md` excerpts (phase G).
- The group's `docs/<lang>/_groups/<group_id>/requirements.md` excerpts (phase J)
  so AFU sections can cite group ATE requirement ids `GRP-<group_id>-REQ-NNN`.
- `config/grouping.yaml` description + member list.
- The active AFU profile (auto-detected per group).

# Outputs

- `docs/_shared/_groups/<group_id>/_fa-group-sections/en/<section_id>.md`
- `docs/_shared/_groups/<group_id>/_fa-group-sections/<target_language>/<section_id>.md`
- `docs/en/_groups/<group_id>/functional-analysis.md`
- `docs/<target_language>/_groups/<group_id>/functional-analysis.md`

# Determinism rules

- Citations point at group `requirements.md` (for `GRP-...-REQ-NNN`)
  and per-file `functional-analysis.md` of the owning member.
- Member order follows `config/grouping.yaml.groups[*].members[*]`.
