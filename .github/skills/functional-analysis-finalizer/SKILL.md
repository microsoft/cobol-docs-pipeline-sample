---
name: functional-analysis-finalizer
description: 'Author phase-G per-file `functional-analysis.md` for ONE mainframe or IBM i (AS400) source from its prepared section drafts. LLM-driven. USE FOR: assemble IBM i or mainframe functional analysis, stitch FA sections, and phase-G finalization. DO NOT USE FOR: per-section authoring, index/complete, QA, or portal build.'
argument-hint: 'Source file path + optional --languages en,it. Writes docs/<lang>/<file>/functional-analysis.md per language. The agent finalises by reading `_finalize.bundle.md` + the per-section drafts and emitting one stitched file per language.'
---

# Functional Analysis Finalizer (per-file, phase G)

LLM-driven phase-G finalizer. For ONE source file, stitches the per-FA-section
drafts written by [`functional-analysis-writer`](../functional-analysis-writer/SKILL.md)
into a single, complete `functional-analysis.md` per requested language. EN is
the source-of-truth; non-EN siblings are co-authored / co-finalised in the same
LLM call.

This is the **per-file scope** of the FA family. The per-section
`functional-analysis-writer` skill explicitly **forbids** authoring the final
stitched document; that scope lives here. The same agent
(`functional-analysis-writer.agent.md`) handles both scopes — only the bundle
input differs.

## When to Use

- Every per-section FA draft for the file has been authored and passed
  [`qa-reviewer`](../qa-reviewer/SKILL.md) (`kind: "functional-analysis"`).
- The user asks to "build functional-analysis.md", "finalize the AFU", "stitch
  the FA sections", "produce the per-language AFU document for DEMO100".

Do **not** use this skill for:
- Per-FA-section drafts (`_fa-sections/<lang>/*.md`) — owned by
  [`functional-analysis-writer`](../functional-analysis-writer/SKILL.md) per-section.
- Phase C `index.md` / `complete.md` — owned by [`section-doc-finalizer`](../section-doc-finalizer/SKILL.md).
- File-level overview `.mmd` diagrams — owned by [`diagram-renderer`](../diagram-renderer/SKILL.md).
- Per-file QA review — owned by [`qa-reviewer`](../qa-reviewer/SKILL.md).
- Portal aggregation across files — owned by phase N.

## Output Contract

For file `<basename-with-ext>` and each language `<lang>`:

```
docs/<lang>/<basename-with-ext>/functional-analysis.md
```

The document MUST:

- Open with the H1 banner from `profile.front_matter.title_pattern` (or the
  `header` section spec) with placeholders substituted from
  `bundle.front_matter_values`.
- Render the classification + metadata tables from `profile.front_matter` when
  `show_classification` / `show_metadata_table` are true.
- Concatenate every per-section draft from `bundle.section_drafts.<lang>` in
  **profile order** (the order from `fa_profile_resolver.flatten_sections`).
- Replace missing optional sections with the section heading followed by a
  single paragraph containing exactly `profile.section.optional_marker`.
- Renumber per-section `[^src-N]` footnotes into ONE consolidated `## Sources`
  block at the end of the document. Definitions are kept verbatim, ids
  re-sequenced starting at 1 in document order.
- Append the footer from `profile.footer` verbatim when present
  (`V5.0.0` + `<!-- kpi-functional-analysis -->` for `default
- For non-EN languages, mirror the EN heading structure, table row count, and
  consolidated footnote ids 1:1.

## Procedure

1. **Resolve inputs.** Required under `docs/_shared/<basename-with-ext>/`:
   - `_fa-bundles/_finalize.bundle.json` (+ `.md` view).
   - `_fa-sections/<lang>/<section_id>.md` for every required section in
     `profile.sections` × every requested language.
   On any miss: exit `4` and report exactly which drafts are missing.
2. **Tombstone check.** If `_fa-bundles/_skipped.json` exists, the file is opted
   out of phase G entirely. Exit `0` without writing.
3. **Stale-input check.** Re-hash `_fa-bundles/_finalize.bundle.json::manifest_sha`
   against the on-disk source sha. Mismatch → exit `5` and prompt the user to
   re-run phase A.
4. **Assemble the bundle.** Invoke [scripts/assemble-inputs.py](./scripts/assemble-inputs.py).
   This deterministic packager:
   - resolves the FA profile via `scripts/lib/fa_profile_resolver.py`,
   - loads every per-section draft and embeds its body verbatim under
     `section_drafts.<lang>.<section_id>`,
   - computes `front_matter_values` from `facts.json` (program id, JCL job
     name, CICS transaction id, …),
   - emits `_finalize.bundle.json` + `.md`.
5. **Author.** The `functional-analysis-writer` agent reads the bundle and
   writes `functional-analysis.md` per language at the exact path declared
   under `bundle.output_paths`.
6. **Validate mechanically.** Invoke [`qa-reviewer`](../qa-reviewer/SKILL.md)
   `--kind functional-analysis` per language.

## Bundle Schema

```jsonc
{
  "bundle_version":     "1.0",
  "scope":              "per-file",
  "source_path":        "repos/sample1/COBOL/DEMO100.CBL",
  "source_kind":        "cobol",
  "manifest_sha":       "<64-hex>",
  "profile_name":       "default
  "profile_path":       "config/templates/docs/functional-analysis/default
  "profile":            { /* full profile.yaml */ },
  "profile_sha":        "<64-hex>",
  "front_matter_values":{
    "ACRONYM": "DEMO100", "SSA": "AX", "INTERFACE_NAME": "DEMO100",
    "CLASSIFICATION": "USO INTERNO", "AUTHORIZED_OFFICE": "Ufficio Sistemi Vigilanza",
    "AUTHOR": "", "VERSION": "1.0", "CREATION_DATE": "", "STATE": "DRAFT",
    "SOURCE_PATH": "repos/sample1/COBOL/DEMO100.CBL", "SHA256": "<64-hex>",
    "ENCODING": "auto", "LINE_COUNT": 1908, "GENERATED_AT": "2026-05-28T00:00:00Z"
  },
  "languages":          ["en", "it"],
  "ordered_sections":   [
    { "id": "scopo-ambito", "number": "4", "title": "Scope & boundaries",
      "required": true, "optional_marker": "Paragrafo non necessario" }
    /* in profile.sections order, including subsections */
  ],
  "section_drafts": {
    "en": {
      "scopo-ambito":  "## 4. Scope & boundaries\n\n…draft body with [^src-1]…\n\n[^src-1]: …"
    },
    "it": {
      "scopo-ambito":  "## 4. Scopo e ambito\n\n…corpo della bozza con [^src-1]…\n\n[^src-1]: …"
    }
  },
  "missing_sections": {
    "en": ["interfacce-utente", "ui-standard"],
    "it": ["interfacce-utente", "ui-standard"]
  },
  "output_paths": {
    "en": "docs/en/DEMO100.CBL/functional-analysis.md",
    "it": "docs/it/DEMO100.CBL/functional-analysis.md"
  }
}
```

## Determinism Rules

- The bundle packager is fully deterministic: re-running on unchanged inputs
  emits a byte-identical bundle (per-section drafts hashed individually).
- The LLM finalisation step is NOT deterministic — that is expected. What IS
  deterministic is the **shape**: same section order, same consolidated
  footnote numbering, same `optional_marker` for missing sections, same
  front-matter substitutions.
- Forbidden re-derivations from the finalisation path:
  - Never re-derive output paths — use `bundle.output_paths` verbatim.
  - Never load `facts.json` / `profile.yaml` / per-section drafts directly
    at runtime — every byte lives in the bundle.

## Resources

- [scripts/assemble-inputs.py](./scripts/assemble-inputs.py) — deterministic per-file finalizer bundle packager.
- [`functional-analysis-writer`](../functional-analysis-writer/SKILL.md) — sibling per-section authoring skill.
- [`scripts/lib/fa_profile_resolver.py`](../../../scripts/lib/fa_profile_resolver.py) — shared profile resolution helper.

## Pipeline Wiring

`config/pipeline-dag.yaml` phase G lists `functional-analysis-writer` at `per-file`
scope as the finalizer step, immediately after every per-FA-section authoring
call has completed and been QA'd. The `qa-reviewer` per-file step
(`kind: "functional-analysis"`) closes phase G per language.

## Common Pitfalls

- **Out-of-order stitching.** Section order MUST come from `bundle.ordered_sections`,
  never from filesystem enumeration of `_fa-sections/<lang>/*.md`.
- **Footnote collision.** Each per-section draft restarts `[^src-N]` from 1; the
  finalizer MUST re-number across the consolidated document. Failing this, the
  qa-reviewer flags duplicate footnote ids.
- **Optional-section drift.** A required section missing from `_fa-sections/`
  is an `error` — never silently fill it with `optional_marker`. Only sections
  whose `profile.section.required` is false may be marker-only.
- **Front-matter fabrication.** Every `{{PLACEHOLDER}}` MUST resolve from
  `bundle.front_matter_values`. Unknown placeholders are left literal so the
  qa-reviewer can flag them.
