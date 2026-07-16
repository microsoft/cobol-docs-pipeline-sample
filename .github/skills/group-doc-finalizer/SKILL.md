---
name: group-doc-finalizer
description: |
  Author per-group `index.md` and `complete.md` for ONE group declared in
  `config/grouping.yaml`. LLM-driven.

  Reads exactly one prepared finalize bundle at
  `docs/_shared/_groups/<group_id>/_doc-bundles/_finalize.bundle.{json,md}`
  (deterministic projection from each member's chunk-manifest.json,
  facts.json TOC fields, incoming_xref[] and per-file index.md/complete.md
  excerpts) and writes
    `docs/<lang>/_groups/<group_id>/index.md` (navigable TOC + executive summary)
    `docs/<lang>/_groups/<group_id>/complete.md` (single-file concatenation
       with stable anchors)
  per requested language.
argument-hint: <group_id> <bundle.bundle.md path> [target_languages]
---

> **Status:** active. Empty `config/grouping.yaml` (`groups: []`) is a graceful
> no-op for the whole phase — the stage and dispatch wrappers both exit 0.

# Scope

This skill owns the phase-I per-group LLM authoring step. One invocation
covers EN plus every requested translation language for a single group.

Sibling skills it does NOT replace:
- `section-doc-finalizer` — per-file `index.md` + `complete.md` (phase E).
- `requirements-group-writer` — group ATE (phase J).
- `functional-analysis-group-writer` — group AFU (phase K).

# Inputs

- `config/grouping.yaml` — group manifest (members, description).
- `docs/_shared/<member>/chunk-manifest.json` — for each member.
- `docs/_shared/<member>/facts.json` — TOC fields + `incoming_xref[]`.
- `docs/en/<member>/index.md` and `docs/en/<member>/complete.md` — the
  per-file deliverables produced by phase E.
- `docs/<target_language>/<member>/{index,complete}.md` — translated
  members when a non-EN target language is requested.

All of the above are projected into the bundle by
`scripts/assemble-inputs.py` so the LLM reads exactly one
`_doc-bundles/_finalize.bundle.md`.

# Outputs

- `docs/_shared/_groups/<group_id>/_doc-bundles/_finalize.bundle.json`
- `docs/_shared/_groups/<group_id>/_doc-bundles/_finalize.bundle.md`
- `docs/en/_groups/<group_id>/index.md`
- `docs/en/_groups/<group_id>/complete.md`
- `docs/<target_language>/_groups/<group_id>/{index,complete}.md`

# Procedure (planned)

1. Stage the per-group finalize bundle from member artefacts.
2. Dispatch the `group-doc-finalizer` agent with the bundle.
3. The agent writes `index.md` (executive summary + cross-member TOC +
   incoming/outgoing call graph excerpts) and `complete.md` (stable
   anchored concatenation of member excerpts) per language.

# Determinism rules

- Member order in TOC and `complete.md` follows
  `config/grouping.yaml.groups[*].members[*]` order.
- Anchors are `<member-basename>__<section-id>` (lowercase).
- No file/line citations in prose; cite the member document instead.
- `complete.md` MUST be a single self-contained file:
  - It MUST NOT link to external content. Every paragraph/section link MUST be
    an internal anchor (`#<member-basename>__<section-id>`) into the same file.
    Relative links to sibling docs (other `*.md`, `*.mmd`, `_coverage.md`,
    glossary, alt-language siblings) are delinked — keep the label text only.
  - It MUST NOT reference `facts.json`; use a generic "code" reference instead.
  - It MUST NOT contain an "Authoring self-check" paragraph or heading.
