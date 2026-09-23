---
name: requirements-writer
description: 'Author phase-F technical requirements for ONE mainframe or IBM i (AS400) COBOL source against the configured requirements profile. Reads one prepared bundle and writes per-language section drafts or final requirements.md. USE FOR: COBOL or ILE COBOL requirements, IBM i requirements, REQ/NFR blocks, phase F section authoring and finalization. DO NOT USE FOR: functional analysis, section docs, chunking, facts extraction, QA review, or portal build.'
argument-hint: 'Per-section: --bundle <docs/_shared/<file>/_req-bundles/<section_id>.bundle.md>. Per-file finalizer: --bundle <docs/_shared/<file>/_req-bundles/_finalize.bundle.md>. Output paths live in the bundle Metadata + Output paths blocks. Authors exactly bundle.languages in one LLM call.'
---

# Requirements Writer (per-section + per-file finalizer, phase F)

Use bundle `source_platform` to distinguish z/OS requirements from IBM i ILE,
library-list, activation-group, commitment-control, and DB2 for i requirements.

LLM-driven phase-F authoring skill. For ONE source file, produces a complete
the organization's technical-requirements document (`requirements.md`) per
requested language. The skill mirrors [`functional-analysis-writer`](../functional-analysis-writer/SKILL.md)
1:1 in shape and contract; only the profile family and output filename differ.

> **Status:** implemented. The skill metadata, output contract, bundle schema and
> determinism rules are pinned, and the requirements-specific packagers under
> [scripts/](./scripts/) (`stage-bundles.py`, `assemble-inputs.py`) plus the
> shared `scripts/lib/req_profile_resolver.py` are implemented.

| Scope               | Reads                                                            | Writes                                                                 |
|---------------------|------------------------------------------------------------------|------------------------------------------------------------------------|
| `per-section` (LLM) | `docs/_shared/<file>/_req-bundles/<section_id>.bundle.md`        | `docs/_shared/<file>/_req-sections/<lang>/<section_id>.md` per lang    |
| `per-file` (LLM)    | `docs/_shared/<file>/_req-bundles/_finalize.bundle.md` + drafts  | `docs/<lang>/<file>/requirements.md` per language                      |

Bundles are produced deterministically by [scripts/stage-bundles.py](./scripts/stage-bundles.py)
(per-section) and [`requirements-finalizer/scripts/assemble-inputs.py`](../requirements-finalizer/scripts/assemble-inputs.py)
(per-file). The LLM call that fills the template is invoked by the
`requirements-writer` agent. Mechanical compliance is verified by
[`qa-reviewer`](../qa-reviewer/SKILL.md) (`kind: "requirements"`) immediately
after each authoring call.

## When to Use

- The user asks to "write the technical requirements", "produce the ATE document",
  "draft REQ-007", "co-author EN + IT requirements for DEMO100", "regenerate
  requirements.md".
- A per-section requirements bundle exists at
  `docs/_shared/<file>/_req-bundles/<section_id>.bundle.md`.
- The per-file finalizer bundle `_finalize.bundle.md` exists and every
  per-section draft for the file has been authored.

Do **not** use this skill for:
- phase G functional-analysis ([`functional-analysis-writer`](../functional-analysis-writer/SKILL.md)),
- phase C per-section docs ([`section-doc-writer`](../section-doc-writer/SKILL.md)),
- chunking ([`cobol-chunking`](../cobol-chunking/SKILL.md)),
- facts extraction ([`cobol-facts-extraction`](../cobol-facts-extraction/SKILL.md)),
- QA review of the produced requirements ([`qa-reviewer`](../qa-reviewer/SKILL.md)),
- portal aggregation across files (phase N).

## Output Contract

### Per-section scope

For exactly each language `<lang>` in `bundle.languages`, in its declared order,
use `bundle.output_paths` verbatim. Never add an unrequested English edition or
intermediate; English is the default only when no language is provided.

```
docs/_shared/<file>/_req-sections/<lang>/<section_id>.md
```

This is an INTERMEDIATE artifact — never user-facing. The finalizer concatenates
these per-language drafts into the final `requirements.md`.

The draft MUST:

- Begin with the section's H2 heading line built from `profile.section.number`
  (when present) and `profile.section.title` (e.g. `## Functional requirements`).
  Subsections use H3, with one H3 per requirement (`### REQ-NNN — <title>`)
  when `profile.section.per_requirement_subsection` is true.
- Honour `profile.section.required`. If the section is optional and there is
  not enough evidence in `facts_slice` / `chunk_excerpt` to write meaningful
  content, emit the heading followed by a single paragraph containing exactly
  `profile.section.optional_marker`.
- Respect `profile.section.min_paragraphs`, `min_count`, and any
  `min_sentences` / `min_words` thresholds declared on the section.
- For requirement sub-sections (REQ-NNN / NFR-NNN), render the fields declared
  in the profile (`Statement`, `Rationale`, `Source citations`, `Dependencies`,
  `Acceptance criteria`, `Confidence`). After the per-requirement narrative,
  emit a roll-up table for traceability when `render_mode: narrative-then-table`.
- Populate every table declared under `profile.section.table.columns` from the
  bundle's `facts_slice` — never invent rows. Use `_None._` (markdown italic)
  for genuinely empty cells, never `N/A`.
- Embed every diagram listed in `profile.section.embed_diagrams` as an inline
  fenced ```` ```mermaid ```` block with the source taken VERBATIM from the
  bundle's `## Diagrams` block.
- Cite source ranges via Pandoc footnote form `[^src-N]`. Footnote definitions
  go at the BOTTOM of the per-section draft; the finalizer renumbers and
  consolidates them into a single `## Sources` block at the end of
  `requirements.md`.
- Identifier styling: COBOL/JCL identifiers MUST match
  `profile.identifier_lock_regex` and be wrapped in backticks. Requirement ids
  follow `profile.functional_id_prefix` / `profile.non_functional_id_prefix`
  with `profile.id_padding` (e.g. `REQ-001`, `NFR-007`).
- Author exactly the requested languages in the SAME LLM call. When multiple
  languages are requested, align structure 1:1 (heading count, table row count,
  `[^src-N]` ids, requirement ids).

### Per-file finalizer scope

For each language `<lang>`:

```
docs/<lang>/<file>/requirements.md
```

The document MUST:

- Start with the H1 banner built from `profile.front_matter.title_pattern`
  (or the `header` section spec) with placeholders substituted from
  `bundle.front_matter_values`.
- Render the classification + metadata tables from `profile.front_matter` when
  `show_classification` / `show_metadata_table` are true.
- Concatenate every per-section draft in **profile order**. Missing optional
  drafts are replaced by the heading + `optional_marker` paragraph.
- Renumber the per-section `[^src-N]` footnotes into one consolidated
  `## Sources` block at the end of the document.
- Append the footer block from `profile.footer` verbatim when present.

## Procedure

1. **Resolve bundle input.** Locate
   `docs/_shared/<file>/_req-bundles/<section_id>.bundle.md` (per-section) or
   `_finalize.bundle.md` (finalizer). If only the `.bundle.json` exists, re-run
   `assemble-inputs.py` to regenerate the `.md` view. On miss: exit `4`.
2. **Validate bundle schema.** Required `## Metadata` keys per-section:
   `bundle_version`, `source_path`, `profile_name`, `section.id`,
   `section.title`, `template_path`, `languages`, `facts_slice_sha`,
   `template_sha`, `profile_sha`. Required `## Output paths` keys: one per
   language. On miss: exit `4`.
3. **Tombstone check.** If `docs/_shared/<file>/_req-bundles/_skipped.json`
   exists (copybook / BMS), the file is opted out of phase F. Print
   `SKIP: <file> (<reason>)` and exit `0` without writing anything.
4. **Author.** The agent reads the bundle and writes one `.md` per language at
   the exact path declared in `bundle.output_paths.<lang>`. The skill does NOT
   shell out to an LLM CLI — authoring is an agent responsibility.
5. **Validate mechanically.** Invoke [`qa-reviewer`](../qa-reviewer/SKILL.md)
   `--kind requirements` immediately. Fail-fast: do not start the next section
   while findings remain.
6. **Report.** Print one summary line per language:
   `OK: wrote docs/_shared/<file>/_req-sections/<lang>/<section_id>.md (words=…, sources=…)`
   and the qa-reviewer verdict.

## Bundle Schema (per-section)

```jsonc
{
  "bundle_version":   "1.0",
  "scope":            "per-section",
  "source_path":      "repos/sample1/COBOL/DEMO100.CBL",
  "source_kind":      "cobol",
  "profile_name":     "ate-org-applicazione",
  "profile_path":     "config/templates/docs/requirements/ate-org-applicazione/profile.yaml",
  "profile":          { /* full profile.yaml */ },
  "profile_sha":      "<64-hex>",
  "section":          { /* the profile.sections[] entry (with _id_path / _parent_id) */ },
  "facts_slice":      { /* section-scoped subset of facts.json */ },
  "facts_slice_sha":  "<64-hex>",
  "chunk_excerpt":    "…relevant heading-matched excerpt from bundle.languages[0]'s complete.md…",
  "chunk_excerpt_sha":"<64-hex>",
  "template_path":    "config/templates/docs/requirements/ate-org-applicazione/template.md",
  "template_snippet": "…the matching `## N. Title` block from template.<lang>.md…",
  "template_paths_per_language": {
    "en": "config/templates/docs/requirements/ate-org-applicazione/template.md",
    "it": "config/templates/docs/requirements/ate-org-applicazione/template.it.md"
  },
  "template_sha":     "<64-hex>",
  "diagrams":         [ /* see functional-analysis-writer SKILL */ ],
  "front_matter_values": { /* see functional-analysis-writer SKILL */ },
  "languages":        ["en", "it"],
  "output_paths": {
    "en": "docs/_shared/DEMO100.CBL/_req-sections/en/functional-requirements.md",
    "it": "docs/_shared/DEMO100.CBL/_req-sections/it/functional-requirements.md"
  }
}
```

## Determinism Rules

- The bundle packagers are fully deterministic: re-running on unchanged inputs
  MUST emit a byte-identical bundle.
- Forbidden re-derivations from the authoring path:
  - Never re-derive output paths — use `bundle.output_paths` verbatim.
  - Never load `facts.json`, `complete.md`, `profile.yaml`, or the full
    `template.md` at runtime — every bit of context lives in the bundle.
  - Never invent table rows, citations, requirements, or diagram nodes that
    have no anchor in `facts_slice` / `chunk_excerpt` / `diagrams`.
- Drafts for all requested languages are co-authored in the SAME LLM call.

## Resources

- [scripts/assemble-inputs.py](./scripts/assemble-inputs.py) — deterministic per-section bundle packager.
- [scripts/stage-bundles.py](./scripts/stage-bundles.py) — bulk per-section bundle runner for ONE source file.
- [scripts/req_stage_batch.ps1](./scripts/req_stage_batch.ps1) — PowerShell batch wrapper.
- [`requirements-finalizer`](../requirements-finalizer/SKILL.md) — sibling skill that produces `_finalize.bundle.json` / `.md` and (after authoring) the per-language `requirements.md`.
- `scripts/lib/req_profile_resolver.py` — shared profile auto-detection (planned; mirror of `fa_profile_resolver.py`).

## Pipeline Wiring

`config/pipeline-dag.yaml` phase F lists `requirements-writer` twice: first at
`per-section` scope, then at `per-file` scope (finalizer). Each call is followed
by a `qa-reviewer` step with `kind: "requirements"`. The phase depends on
phase C so the writer can reuse `bundle.languages[0]`'s `complete.md` narrative when building
per-section excerpts. Phase G (functional-analysis) depends on phase F.

## Common Pitfalls

- **Missing bundle.** Author requires the bundle. Never read `facts.json`,
  `complete.md`, or `profile.yaml` directly at runtime.
- **Requirement-id fabrication.** Every `REQ-NNN` / `NFR-NNN` MUST be sourced
  from `facts_slice.business_rules` (or the equivalent NFR slice). The
  qa-reviewer flags fabricated ids.
- **Profile drift.** If `profile.yaml` is edited mid-flight, re-run
  `stage-bundles.py --force` so the cached bundle `profile_sha` matches.
- **Table fabrication.** Every row MUST cite a fact / line range. Empty cells
  use `_None._` italic; the qa-reviewer flags `N/A`, `TBD`, `???` as `error`.
- **Co-authoring drift.** When multiple languages are requested, drafts MUST share heading count, requirement
  ids, table row count, and `[^src-N]` ids.
