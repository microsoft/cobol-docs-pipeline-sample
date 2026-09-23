---
name: requirements-finalizer
description: 'Author phase-F per-file `requirements.md` for ONE mainframe or IBM i (AS400) source from its prepared section drafts. LLM-driven. USE FOR: assemble IBM i or mainframe technical requirements, stitch REQ sections, and phase-F finalization. DO NOT USE FOR: per-section authoring, index/complete, QA, or portal build.'
argument-hint: 'Source file path + optional --languages en,it. Writes docs/<lang>/<file>/requirements.md per language. The agent finalises by reading `_finalize.bundle.md` + the per-section drafts and emitting one stitched file per language.'
---

# Requirements Finalizer (per-file, phase F)

LLM-driven phase-F finalizer. For ONE source file, stitches the per-section
requirements drafts written by [`requirements-writer`](../requirements-writer/SKILL.md)
into a single, complete `requirements.md` for exactly `bundle.languages`, in
declared order at `bundle.output_paths`, co-finalised in the same LLM call.
Never require or create an unrequested English edition or intermediate.

> **Status:** implemented. The contract and bundle schema are pinned, and the
> requirements-specific packager under [scripts/](./scripts/) is implemented.

This is the **per-file scope** of the requirements family. The per-section
`requirements-writer` skill explicitly **forbids** authoring the final stitched
document; that scope lives here. The same agent
(`requirements-writer.agent.md`) handles both scopes — only the bundle input
differs.

## When to Use

- Every per-section requirements draft for the file has been authored and
  passed [`qa-reviewer`](../qa-reviewer/SKILL.md) (`kind: "requirements"`).
- The user asks to "build requirements.md", "finalize the ATE", "stitch the
  requirements sections", "produce the per-language requirements document for
  DEMO100".

Do **not** use this skill for:
- Per-section drafts (`_req-sections/<lang>/*.md`) — owned by
  [`requirements-writer`](../requirements-writer/SKILL.md) per-section.
- Phase G functional-analysis — owned by
  [`functional-analysis-finalizer`](../functional-analysis-finalizer/SKILL.md).
- Phase C `index.md` / `complete.md` — owned by
  [`section-doc-finalizer`](../section-doc-finalizer/SKILL.md).
- File-level overview `.mmd` diagrams — owned by
  [`diagram-renderer`](../diagram-renderer/SKILL.md).
- Per-file QA review — owned by [`qa-reviewer`](../qa-reviewer/SKILL.md).
- Portal aggregation across files — owned by phase N.

## Output Contract

For file `<basename-with-ext>` and each language `<lang>`:

```
docs/<lang>/<basename-with-ext>/requirements.md
```

The document MUST:

- Open with the H1 banner from `profile.front_matter.title_pattern` (or the
  `header` section spec) with placeholders substituted from
  `bundle.front_matter_values`.
- Render the classification + metadata tables from `profile.front_matter` when
  `show_classification` / `show_metadata_table` are true.
- Concatenate every per-section draft from `bundle.section_drafts.<lang>` in
  **profile order**.
- Replace missing optional sections with the section heading followed by a
  single paragraph containing exactly `profile.section.optional_marker`.
- Renumber per-section `[^src-N]` footnotes into ONE consolidated `## Sources`
  block at the end of the document.
- Append the footer from `profile.footer` verbatim when present.
- When multiple languages are requested, align heading structure, requirement ids,
  table row count, and consolidated footnote ids 1:1 across those languages only.

## Procedure

1. **Resolve inputs.** Required under `docs/_shared/<basename-with-ext>/`:
   - `_req-bundles/_finalize.bundle.json` (+ `.md` view).
   - `_req-sections/<lang>/<section_id>.md` for every required section in
     `profile.sections` × every requested language.
   On any miss: exit `4` and report exactly which drafts are missing.
2. **Tombstone check.** If `_req-bundles/_skipped.json` exists, the file is
   opted out of phase F entirely. Exit `0` without writing.
3. **Stale-input check.** Re-hash `_req-bundles/_finalize.bundle.json::manifest_sha`
   against the on-disk source sha. Mismatch → exit `5` and prompt to re-run
   phase A.
4. **Assemble the bundle.** Invoke [scripts/assemble-inputs.py](./scripts/assemble-inputs.py).
5. **Author.** The `requirements-writer` agent reads the bundle and writes
   `requirements.md` per language at the exact path declared under
   `bundle.output_paths`.
6. **Validate mechanically.** Invoke [`qa-reviewer`](../qa-reviewer/SKILL.md)
   `--kind requirements` per language.

## Bundle Schema

Mirror of the functional-analysis-finalizer bundle. See
[`functional-analysis-finalizer/SKILL.md`](../functional-analysis-finalizer/SKILL.md#bundle-schema)
substituting `_fa-` → `_req-` and `functional-analysis.md` → `requirements.md`.
Key fields: `bundle_version`, `scope: "per-file"`, `source_path`, `source_kind`,
`manifest_sha`, `profile_name`, `profile_path`, `profile`, `profile_sha`,
`front_matter_values`, `languages`, `ordered_sections`, `section_drafts.<lang>`,
`missing_sections.<lang>`, `output_paths.<lang>`.

## Determinism Rules

- The bundle packager is fully deterministic: re-running on unchanged inputs
  emits a byte-identical bundle (per-section drafts hashed individually).
- The LLM finalisation step is NOT deterministic — that is expected. What IS
  deterministic is the **shape**: same section order, same consolidated
  footnote numbering, same `optional_marker` for missing sections, same
  front-matter substitutions, same requirement-id sequence.
- Forbidden re-derivations from the finalisation path:
  - Never re-derive output paths — use `bundle.output_paths` verbatim.
  - Never load `facts.json` / `profile.yaml` / per-section drafts directly at
    runtime — every byte lives in the bundle.

## Resources

- [scripts/assemble-inputs.py](./scripts/assemble-inputs.py) — deterministic per-file finalizer bundle packager.
- [`requirements-writer`](../requirements-writer/SKILL.md) — sibling per-section authoring skill.

## Pipeline Wiring

`config/pipeline-dag.yaml` phase F lists `requirements-writer` at `per-file`
scope as the finalizer step, immediately after every per-section authoring call
has completed and been QA'd. The `qa-reviewer` per-file step
(`kind: "requirements"`) closes phase F per language.

## Common Pitfalls

- **Out-of-order stitching.** Section order MUST come from
  `bundle.ordered_sections`, never from filesystem enumeration of
  `_req-sections/<lang>/*.md`.
- **Footnote collision.** Each per-section draft restarts `[^src-N]` from 1;
  the finalizer MUST re-number across the consolidated document.
- **Requirement-id collision.** REQ-NNN / NFR-NNN ids MUST be globally unique
  across the consolidated document. The qa-reviewer flags duplicates.
- **Optional-section drift.** A required section missing from `_req-sections/`
  is an `error` — never silently fill it with `optional_marker`.
- **Front-matter fabrication.** Every `{{PLACEHOLDER}}` MUST resolve from
  `bundle.front_matter_values`.
