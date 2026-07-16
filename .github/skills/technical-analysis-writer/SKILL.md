---
name: technical-analysis-writer
description: 'Author phase-L/M technical-analysis documents for mainframe or IBM i (AS400) sources and groups. LLM-driven, single-pass from the prepared finalize bundle, with deterministic DOCX export. USE FOR: IBM i or mainframe technical analysis, analisi tecnica, ATE, phase L per-file and phase M group finalization. DO NOT USE FOR: functional analysis, requirements, section docs, chunking, facts extraction, QA, or portal build.'
argument-hint: 'Per-file: --source <path> (stages bundle, then dispatch reads docs/_shared/<file>/_ta-bundles/_finalize.bundle.md). Per-group: --group-id <id> (stages bundle, then dispatch reads docs/_shared/_groups/<id>/_ta-group-bundles/_finalize.bundle.md). Output paths live in the bundle Metadata + Output paths blocks. Always co-authors EN + every requested target language in one LLM call; DOCX is produced deterministically by the phase driver.'
---

# Technical Analysis Writer (per-file phase L + per-group phase M)

LLM-driven authoring skill for the organization's **ATE — Analisi Tecnica**
deliverable. For ONE source file (phase L) or ONE group (phase M) it produces a
complete `technical-analysis.md` per requested language, then a deterministic
pandoc step renders a sibling `technical-analysis.docx`.

This is a **single-pass finalizer**: unlike the functional-analysis (phase F/G)
and requirements (phase F) families, there are no per-section drafts. The
consolidated narrative source is the already-authored `complete.md`, which the
LLM reorganizes and rewrites into the technical-analysis template structure.
`complete.md` is the **only** narrative input — the writer never reads
`functional-analysis.md`. The SISBA tracciato catalog needed for the
`trk-gestiti` section (§7 of the `ate-org-interfaccia` profile) is the
deterministic `Record types (TRK)` block that phase E appends to `complete.md`;
when that block is present the writer authors the per-TRK subsections from it
instead of stamping the not-applicable marker.

| Scope               | Reads                                                                                | Writes                                                            |
|---------------------|---------------------------------------------------------------------------------------|-------------------------------------------------------------------|
| `per-file` (LLM)    | `docs/_shared/<file>/_ta-bundles/_finalize.bundle.md` (embeds `docs/en/<file>/complete.md`) | `docs/<lang>/<file>/technical-analysis.md` per language           |
| `per-group` (LLM)   | `docs/_shared/_groups/<gid>/_ta-group-bundles/_finalize.bundle.md` (embeds `docs/en/_groups/<gid>/complete.md`) | `docs/<lang>/_groups/<gid>/technical-analysis.md` per language    |

Bundles are produced deterministically by
[scripts/assemble-inputs.py](./scripts/assemble-inputs.py) (per-file) and
[scripts/assemble-group-inputs.py](./scripts/assemble-group-inputs.py)
(per-group). The LLM call that fills the template is invoked by the
`technical-analysis-writer` agent. DOCX export is handled by the phase driver
via [`scripts/lib/Convert-MdToDocx.ps1`](../../../scripts/lib/Convert-MdToDocx.ps1)
(pandoc, plain default styling).

## When to Use

- The user asks to "write the technical analysis", "produce the ATE document",
  "generate analisi tecnica for DEMO100", "co-author EN + IT ATE", "export the
  technical analysis to Word", "regenerate technical-analysis.md".
- A per-file finalize bundle exists at
  `docs/_shared/<file>/_ta-bundles/_finalize.bundle.md`, or a per-group bundle
  at `docs/_shared/_groups/<gid>/_ta-group-bundles/_finalize.bundle.md`.

Do **not** use this skill for:
- phase F functional analysis ([`functional-analysis-writer`](../functional-analysis-writer/SKILL.md)),
- phase F requirements ([`requirements-writer`](../requirements-writer/SKILL.md)),
- phase C per-section docs ([`section-doc-writer`](../section-doc-writer/SKILL.md)),
- chunking ([`cobol-chunking`](../cobol-chunking/SKILL.md)),
- facts extraction ([`cobol-facts-extraction`](../cobol-facts-extraction/SKILL.md)),
- QA review of the produced ATE ([`qa-reviewer`](../qa-reviewer/SKILL.md)),
- portal aggregation across files (phase N).

## Profile resolution

The active profile is resolved deterministically by
[`scripts/lib/ta_profile_resolver.py`](../../../scripts/lib/ta_profile_resolver.py)
from `config/templates/docs/technical-analysis/`:

| Source                                  | Resolved profile                |
|-----------------------------------------|----------------------------------|
| `.cpy` / copybook, `.bms` / BMS mapset  | **SKIP** (tombstoned, no ATE)    |
| `.jcl` / `.prc`                         | `ate-org-interfaccia`         |
| `.cbl` / `.cob` with CICS/BMS usage     | `ate-org-applicazione`        |
| `.cbl` / `.cob` (batch)                 | `ate-org-interfaccia`         |
| otherwise                               | `default`                        |

Group rule (`resolve_for_group`): any BMS member → `ate-org-applicazione`;
any JCL/PRC member → `ate-org-interfaccia`; else → `default`. A workspace
override key `technical_analysis_profile` in `sources.yaml` takes precedence.

## Output Contract

For each language `<lang>` in `bundle.languages` (EN first, then every target):

```
docs/<lang>/<file>/technical-analysis.md                 # per-file (phase L)
docs/<lang>/_groups/<group_id>/technical-analysis.md     # per-group (phase M)
```

with a sibling `technical-analysis.docx` produced by the phase driver.

Each `technical-analysis.md` MUST:

- Begin with the YAML front-matter filled from the bundle's
  `front_matter_values`.
- Author every section declared under the bundle's `## Template` /
  `ordered_sections` block, in profile order, **rewriting** the embedded
  `complete.md` narrative into the template shape — never copying `complete.md`
  verbatim and never inventing facts with no anchor in the narrative.
- Honour `section.required` / `optional_marker`: optional sections with
  insufficient evidence become the heading + a single paragraph containing the
  `optional_marker` verbatim.
- Populate every declared table column from the embedded narrative. Empty cells
  use `_None._` (markdown italic) — never `N/A`, `TBD`, or `???`.
- Cite via Pandoc footnote form `[^src-N]` and consolidate into ONE `## Sources`
  block at the bottom. Per-group docs cite per-file documents, not source lines.
  Inline `[FILE:Lx-Ly]` tags are forbidden.
- Per-group: member order MUST match `grouping.yaml` order verbatim.
- Style COBOL/JCL identifiers per `profile.identifier_lock_regex`, wrapped in
  backticks.
- Co-author EN + every target language in the SAME LLM call; non-EN editions
  mirror EN structurally 1:1 (heading count, table row count, `[^src-N]` ids,
  front-matter keys).

## Pipeline wiring

| Phase | Scope     | Runs in        | Depends on | Driver                                                     |
|-------|-----------|----------------|------------|-------------------------------------------------------------|
| **L** | per-file  | per-file-loop  | G          | [`scripts/phases/phase-L-technical-analysis.ps1`](../../../scripts/phases/phase-L-technical-analysis.ps1) |
| **M** | per-group | workspace      | I, L       | [`scripts/phases/phase-M-group-technical-analysis.ps1`](../../../scripts/phases/phase-M-group-technical-analysis.ps1) |

Each phase runs three steps: **stage** (deterministic bundle packaging) →
**dispatch** (Copilot CLI single-pass authoring) → **docx** (pandoc export).

### Per-file (phase L)

```powershell
# 1. stage the finalize bundle
pwsh -File .github/skills/technical-analysis-writer/scripts/ta_stage_batch.ps1 `
     -Paths repos/sample1/COBOL/*.CBL -Languages en

# 2. dispatch the single-pass finalizer
pwsh -File scripts/dispatchers/run-docs-ta-finalize-batch.ps1 `
     -Paths repos/sample1/COBOL/*.CBL -Languages en

# (3. DOCX export is run automatically by the phase driver)
pwsh -File scripts/phases/phase-L-technical-analysis.ps1 `
     -Paths repos/sample1/COBOL/*.CBL -Languages en
```

### Per-group (phase M)

```powershell
pwsh -File scripts/phases/phase-M-group-technical-analysis.ps1 `
     -Manifest config/grouping.yaml -Languages en
```

## DOCX export

After the Markdown editions are authored, the phase driver dot-sources
[`scripts/lib/Convert-MdToDocx.ps1`](../../../scripts/lib/Convert-MdToDocx.ps1)
and converts each `technical-analysis.md` to a sibling `technical-analysis.docx`
via `pandoc --from markdown --to docx`. No reference-doc is supplied, so pandoc
applies its built-in default Word styling. The conversion is idempotent and
skips files whose `.docx` is newer than the `.md` unless `-Force` is given.
If pandoc is not on `PATH`, the DOCX step is skipped with a warning and the
Markdown editions remain the deliverable.

## Failure modes

- **Missing prereq.** Per-file requires `docs/en/<file>/complete.md` (phase E);
  per-group requires `docs/en/_groups/<gid>/complete.md` (phase I). The stager
  exits 4 and the dispatch records `missing-bundle`.
- **Copybook / BMS.** The stager writes `_skipped.json` and no ATE is produced.
- **pandoc absent.** DOCX step is skipped; Markdown is complete.
- **Empty grouping.yaml.** Phase M is a no-op (exit 0).
