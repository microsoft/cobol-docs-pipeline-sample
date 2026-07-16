---
name: requirements-group-writer
description: |
  Author phase-J group ATE (technical-requirements) markdown for ONE
  group declared in `config/grouping.yaml`. LLM-driven. SCAFFOLD.

  Two scopes:
    Per-section — writes one per-language draft into
      `docs/_shared/_groups/<group_id>/_req-group-sections/<lang>/<section_id>.md`
      from a prepared bundle
      `docs/_shared/_groups/<group_id>/_req-group-bundles/<section_id>.bundle.{json,md}`.
    Per-group finalizer — stitches the per-section drafts into
      `docs/<lang>/_groups/<group_id>/requirements.md` per requested language.

  Reuses the existing per-file ATE profile family under
  `config/templates/docs/requirements/`:
    - `default`
    - `ate-org-applicazione`  (auto-selected when any group member is CICS/BMS)
    - `ate-org-interfaccia`   (auto-selected when any group member is JCL/PRC with batch CBL)
argument-hint: <group_id> <bundle.bundle.md path> [target_languages]
---

> **Status:** scaffold — Day-1 contracts only. Mirrors per-file
> `requirements-writer` and `requirements-finalizer` at group scope.

# Scope

Owns phase-J authoring at the group level. One invocation per section
(per-section scope) or per group (finalizer scope), each covering EN
plus every requested translation language.

Sibling skills:
- `requirements-writer` / `requirements-finalizer` — per-file ATE (phase F).
- `group-doc-finalizer` — group `index.md` / `complete.md` (phase I).
- `functional-analysis-group-writer` — group AFU (phase K).

# Inputs

Per-section scope:
- `docs/_shared/_groups/<group_id>/_req-group-bundles/<section_id>.bundle.json`
  (authoritative) and `.bundle.md` (LLM-facing projection).

Per-group finalizer scope:
- `docs/_shared/_groups/<group_id>/_req-group-bundles/_finalize.bundle.{json,md}`
- Every per-section draft under
  `docs/_shared/_groups/<group_id>/_req-group-sections/<lang>/*.md`

Bundles aggregate, per group:
- Each member's `docs/<lang>/<member>/requirements.md` excerpts (phase F).
- The group's `docs/<lang>/_groups/<group_id>/complete.md` excerpts (phase I).
- `config/grouping.yaml` description + member list.
- The active ATE profile (auto-detected per group).

# Outputs

- `docs/_shared/_groups/<group_id>/_req-group-sections/en/<section_id>.md`
- `docs/_shared/_groups/<group_id>/_req-group-sections/<target_language>/<section_id>.md`
- `docs/en/_groups/<group_id>/requirements.md`
- `docs/<target_language>/_groups/<group_id>/requirements.md`

# Determinism rules

- Requirement ids namespace: `GRP-<group_id>-REQ-NNN` (zero-padded to 3).
- Citations must point at per-file `requirements.md` of the member that
  owns each requirement; never at raw source.
- Member order in the finalized doc follows
  `config/grouping.yaml.groups[*].members[*]` order.
