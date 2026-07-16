---
name: functional-analysis-writer
description: 'Author phase-G functional analysis for ONE mainframe or IBM i (AS400) COBOL source against the configured profile. Reads one prepared bundle and writes per-language section drafts or final functional-analysis.md. USE FOR: COBOL or ILE COBOL functional analysis, IBM i analysis, AFU sections, phase G authoring and finalization. DO NOT USE FOR: section docs, chunking, facts extraction, QA review, or portal build.'
argument-hint: 'Per-section: --bundle <docs/_shared/<file>/_fa-bundles/<section_id>.bundle.md>. Per-file finalizer: --bundle <docs/_shared/<file>/_fa-bundles/_finalize.bundle.md>. Output paths live in the bundle Metadata + Output paths blocks. Always co-authors EN + every requested target language in one LLM call.'
---

# Functional Analysis Writer (per-FA-section + per-file finalizer, phase G)

Use bundle `source_platform` to distinguish z/OS execution from IBM i jobs,
native database files, DB2 for i, ILE calls, and commitment control.

LLM-driven phase-G authoring skill. For ONE source file, produces a complete
the organization's functional-analysis document (`functional-analysis.md`) per
requested language. The skill operates in two scopes mirroring `section-doc-writer`:

| Scope               | Reads                                                          | Writes                                                              |
|---------------------|----------------------------------------------------------------|---------------------------------------------------------------------|
| `per-section` (LLM) | `docs/_shared/<file>/_fa-bundles/<section_id>.bundle.md`       | `docs/_shared/<file>/_fa-sections/<lang>/<section_id>.md` per lang  |
| `per-file` (LLM)    | `docs/_shared/<file>/_fa-bundles/_finalize.bundle.md` + drafts | `docs/<lang>/<file>/functional-analysis.md` per language            |

Bundles are produced deterministically by [scripts/stage-bundles.py](./scripts/stage-bundles.py)
(per-section) and [`functional-analysis-finalizer/scripts/assemble-inputs.py`](../functional-analysis-finalizer/scripts/assemble-inputs.py)
(per-file). The LLM call that fills the template is invoked by the
`functional-analysis-writer` agent. Mechanical compliance is verified by
[`qa-reviewer`](../qa-reviewer/SKILL.md) (`kind: "functional-analysis"`)
immediately after each authoring call.

## When to Use

- The user asks to "write the functional analysis", "produce the AFU document", "draft section 5.1 of the FA", "co-author EN + IT FA for DEMO100", "regenerate functional-analysis.md".
- A per-section FA bundle exists at `docs/_shared/<file>/_fa-bundles/<section_id>.bundle.md`.
- The per-file finalizer bundle `_finalize.bundle.md` exists and every per-section draft for the file has been authored.

Do **not** use this skill for:
- phase C per-section docs ([`section-doc-writer`](../section-doc-writer/SKILL.md)),
- chunking ([`cobol-chunking`](../cobol-chunking/SKILL.md)),
- facts extraction ([`cobol-facts-extraction`](../cobol-facts-extraction/SKILL.md)),
- QA review of the produced FA ([`qa-reviewer`](../qa-reviewer/SKILL.md)),
- portal aggregation across files (phase N).

## Output Contract

### Per-section scope

For each language `<lang>` in `bundle.languages` (EN first, then every target):

```
docs/_shared/<file>/_fa-sections/<lang>/<section_id>.md
```

This is an INTERMEDIATE artifact — never user-facing. The finalizer concatenates
these per-language drafts into the final `functional-analysis.md`.

The draft MUST:

- Begin with the section's H2 heading line built from `profile.section.number`
  and `profile.section.title` (e.g. `## 5.1 Business processes`). Subsections
  use H3.
- Honour `profile.section.required`. If the section is optional and there is
  not enough evidence in `facts_slice` / `chunk_excerpt` to write meaningful
  content, emit the heading followed by a single paragraph containing exactly
  `profile.section.optional_marker` (default `"Paragrafo non necessario"`
  in IT, `"Section not applicable"` in EN).
- Respect `profile.section.min_paragraphs` and any `min_sentences` /
  `min_words` thresholds declared on the section.
- Populate the table declared under `profile.section.table.columns` from the
  bundle's `facts_slice` — never invent rows. Use `_None._` (markdown italic)
  for genuinely empty cells, never `N/A`.
- Embed every diagram listed in `profile.section.embed_diagrams` as an inline
  fenced ```` ```mermaid ```` block with the source taken VERBATIM from the
  bundle's `## Diagrams` block. Do not re-author the diagram.
- Cite source ranges via Pandoc footnote form `[^src-N]`. Footnote definitions
  go at the BOTTOM of the per-section draft; the finalizer renumbers and
  consolidates them into a single `## Sources` block at the end of
  `functional-analysis.md`.
- Identifier styling: COBOL/JCL identifiers MUST match
  `profile.identifier_lock_regex` (default `[A-Z][A-Z0-9-]*(\.[A-Z0-9-]+)?`)
  and be wrapped in backticks.
- For repeatable subsections (e.g. `profile.section.repeatable_subsections`)
  emit one H3 per discovered item (from `facts_slice.business_rules`,
  `facts_slice.trk_records`, …) following the `template.required_paragraphs`
  skeleton declared in the profile.
- Co-author EN + every target language in the SAME LLM call. The non-EN drafts
  MUST mirror the heading structure, table row count, and citation footnote ids
  of EN 1:1 so the qa-reviewer can compare them.

### Per-file finalizer scope

For each language `<lang>`:

```
docs/<lang>/<file>/functional-analysis.md
```

The document MUST:

- Start with the H1 banner built from `profile.front_matter.title_pattern` (or
  the `header` section spec) with `{{INTERFACE_NAME}}` / `{{ACRONYM}}`
  substituted from `bundle.front_matter_values`.
- Render the classification + metadata tables from `profile.front_matter` when
  `show_classification` / `show_metadata_table` are true (default
- Concatenate every per-section draft in **profile order** (the order produced
  by `fa_profile_resolver.flatten_sections`). Missing optional drafts are
  replaced by the heading + `optional_marker` paragraph.
- Renumber the per-section `[^src-N]` footnotes into one consolidated
  `## Sources` block at the end of the document (each footnote definition kept
  verbatim, ids re-sequenced from 1).
- Append the footer block from `profile.footer` verbatim when present (e.g.
  `V5.0.0` + the `<!-- kpi-functional-analysis -->` marker for the
  applicazione profile).

## Procedure

1. **Resolve bundle input.** Locate `docs/_shared/<file>/_fa-bundles/<section_id>.bundle.md`
   (per-section) or `_finalize.bundle.md` (finalizer). If only the `.bundle.json`
   exists, re-run `assemble-inputs.py` to regenerate the `.md` view. On miss:
   exit `4` with the missing path.
2. **Validate bundle schema.** Required `## Metadata` keys per-section:
   `bundle_version`, `source_path`, `profile_name`, `section.id`,
   `section.number`, `section.title`, `template_path`, `languages`,
   `facts_slice_sha`, `template_sha`, `profile_sha`. Required `## Output paths`
   keys: one per language. On miss: exit `4`.
3. **Tombstone check.** If `docs/_shared/<file>/_fa-bundles/_skipped.json`
   exists (copybook / BMS), the file is opted out of phase G. Print
   `SKIP: <file> (<reason>)` and exit `0` without writing anything.
4. **Author.** The agent reads the bundle and writes one `.md` per language at
   the exact path declared in `bundle.output_paths.<lang>`. The skill does NOT
   shell out to an LLM CLI — authoring is an agent responsibility.
5. **Validate mechanically.** Invoke [`qa-reviewer`](../qa-reviewer/SKILL.md)
   `--kind functional-analysis` immediately. Fail-fast: do not start the next
   section while findings remain.
6. **Report.** Print one summary line per language:
   `OK: wrote docs/_shared/<file>/_fa-sections/en/<section_id>.md (words=…, sources=…)`
   and the qa-reviewer verdict.

## Bundle Schema (per-section)

```jsonc
{
  "bundle_version":   "1.0",
  "scope":            "per-section",
  "source_path":      "repos/sample1/COBOL/DEMO100.CBL",
  "source_kind":      "cobol",
  "profile_name":     "default
  "profile_path":     "config/templates/docs/functional-analysis/default
  "profile":          { /* full profile.yaml */ },
  "profile_sha":      "<64-hex>",
  "section":          { /* the profile.sections[] entry (with _id_path / _parent_id) */ },
  "facts_slice":      { /* section-scoped subset of facts.json */ },
  "facts_slice_sha":  "<64-hex>",
  "chunk_excerpt":    "…relevant heading-matched excerpt from docs/en/<file>/complete.md…",
  "chunk_excerpt_sha":"<64-hex>",
  "template_path":    "config/templates/docs/functional-analysis/default
  "template_snippet": "…the matching `## N. Title` block from template.<lang>.md…",
  "template_paths_per_language": {
    "en": "config/templates/docs/functional-analysis/default
    "it": "config/templates/docs/functional-analysis/default
  },
  "template_sha":     "<64-hex>",
  "diagrams":         [
    { "kind": "call-graph", "path": "docs/_shared/DEMO100.CBL/diagrams/call-graph.mmd",
      "source": "flowchart TD\n…", "sha256": "<64-hex>" }
  ],
  "front_matter_values": {
    "ACRONYM": "DEMO100", "SSA": "AX", "INTERFACE_NAME": "DEMO100",
    "CLASSIFICATION": "USO INTERNO", "AUTHORIZED_OFFICE": "Ufficio Sistemi Vigilanza",
    "AUTHOR": "", "VERSION": "1.0", "CREATION_DATE": "", "STATE": "DRAFT"
  },
  "languages":        ["en", "it"],
  "output_paths": {
    "en": "docs/_shared/DEMO100.CBL/_fa-sections/en/processi-business.md",
    "it": "docs/_shared/DEMO100.CBL/_fa-sections/it/processi-business.md"
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
  - Never invent table rows, citations, or diagram nodes that have no anchor
    in `facts_slice` / `chunk_excerpt` / `diagrams`.
- Non-EN drafts are co-authored in the SAME LLM call as EN. Post-hoc translation
  via a later `translator` fallback pass is permitted only to reconcile missing
  or drifted siblings.

## Resources

- [scripts/assemble-inputs.py](./scripts/assemble-inputs.py) — deterministic per-section bundle packager.
- [scripts/stage-bundles.py](./scripts/stage-bundles.py) — bulk per-section bundle runner for ONE source file (also emits the `_finalize.bundle.json` for the finalizer scope).
- [`functional-analysis-finalizer`](../functional-analysis-finalizer/SKILL.md) — sibling skill that produces `_finalize.bundle.json` / `.md` and (after authoring) the per-language `functional-analysis.md`.
- [`scripts/lib/fa_profile_resolver.py`](../../../scripts/lib/fa_profile_resolver.py) — shared profile auto-detection (CPY/BMS skip, JCL/PRC → interfaccia, CBL+CICS → applicazione, else interfaccia).

## Pipeline Wiring

`config/pipeline-dag.yaml` phase G lists `functional-analysis-writer` twice:
first at `per-section` scope (one LLM call per FA section), then at `per-file`
scope (finalizer). Each call is followed by a `qa-reviewer` step with
`kind: "functional-analysis"`. The phase depends on phase C so the writer can
reuse the EN `complete.md` narrative when building per-section excerpts.

## Common Pitfalls

- **Missing bundle.** Author requires the bundle. Never read `facts.json`,
  `complete.md`, or `profile.yaml` directly at runtime.
- **Profile drift.** If `profile.yaml` is edited mid-flight, re-run
  `stage-bundles.py --force` so the cached bundle `profile_sha` matches; the
  qa-reviewer fails fast on mismatched profile hashes.
- **Table fabrication.** Every row in a profile-declared table MUST cite a
  fact / line range. Empty cells use `_None._` italic; the qa-reviewer flags
  `N/A`, `TBD`, `???` as `error`.
- **Diagram re-authoring.** Diagrams are embedded VERBATIM from the bundle.
  The qa-reviewer compares the inlined fence with the bundle source byte-for-byte.
- **Co-authoring drift.** EN and IT drafts MUST share heading count, table row
  count, and `[^src-N]` ids. The finalizer aborts on a structural diff.
