---
name: section-doc-writer
description: 'Author phase-C markdown for ONE mainframe or IBM i (AS400) source chunk (COBOL, CBLLE, SQLCBLLE, CL, CLP, CLLE, JCL, PROC, copybook, BMS). USE FOR: document IBM i CL programs/commands, ILE COBOL, JCL steps, data records, and EXEC blocks. DO NOT USE FOR: chunking, facts extraction, slicing, QA, finalization, or file-level diagrams.'
argument-hint: '--bundle <docs/_shared/<file>/_bundles/<chunk_id>.bundle.md> (LLM input). The `.bundle.json` sibling remains authoritative for SHAs and mechanical tooling. Writes one markdown per language under the paths declared in the bundle Metadata + Output paths blocks, plus the per-section .mmd diagram.'
---

# Section Doc Writer (per-section, phase C)

## Platform Contract

Read `source_platform` from bundle metadata. For `ibmi`, use IBM i/ILE,
library/object/member, native database file, DB2 for i, commitment-control, and
activation-group terminology only when evidenced. Never invent z/OS artifacts.

LLM-driven phase-C authoring skill. For ONE chunk, produces a single section markdown document per requested language by:

1. Reading exactly one prepared bundle: the rendered Markdown view at `docs/_shared/<file>/_bundles/<chunk_id>.bundle.md`. The `.bundle.json` sibling is the authoritative artifact (referenced by SHAs and consumed by the mechanical `qa-reviewer` checker); the `.md` is a deterministic, regenerated projection optimized for LLM consumption — same data, headed sections + tables instead of nested JSON.
2. Using the bundle payload (`## Metadata`, `## Chunk`, `## Source text`, `## Facts slice`, `## Profile`, `## Template`, `## Output paths`) as the complete authoring context. The `## Template` block only links to the template file at `template_path` (pinned by `template_sha`); read that file to get the authoring rules — the body is not inlined in the MD view.
3. Emitting `docs/<lang>/<basename-with-ext>/sections/<chunk_id_sanitized>.md` per language plus the per-section Mermaid diagram.

The skill consumes an already-built deterministic bundle and defines the authoring contract; the LLM call that fills the template is invoked by the `section-doc-writer` agent. Mechanical compliance is verified by [`qa-reviewer`](../qa-reviewer/SKILL.md) immediately after.

## When to Use

- The user asks to "write a section doc", "document chunk X", "author the markdown for paragraph A000-MAIN", "co-author EN + IT sections", or "regenerate the section docs for DEMO100".
- A bundle exists for the target chunk under `docs/_shared/<file>/_bundles/`.
- A single chunk needs to be re-authored on demand (`--chunk-id <id>`).

Do **not** use this skill for:
- chunking ([`cobol-chunking`](../cobol-chunking/SKILL.md)),
- facts extraction ([`cobol-facts-extraction`](../cobol-facts-extraction/SKILL.md)),
- per-chunk facts/source preparation ([`facts-slicing`](../facts-slicing/SKILL.md), [`chunk-text-extraction`](../chunk-text-extraction/SKILL.md)),
- QA review of the produced markdown ([`qa-reviewer`](../qa-reviewer/SKILL.md)),
- file-level `index.md` / `complete.md` / overview diagrams — those are owned by the per-file `section-doc-writer` finalizer step and the `diagram-renderer` agent (see `config/pipeline-dag.yaml` phase C).

## Output Contract

For chunk `<chunk_id>` of file `<basename-with-ext>`, for exactly each language
`<lang>` in `bundle.languages`, preserving its declared order:

```
docs/<lang>/<basename-with-ext>/sections/<chunk_id_sanitized>.md
```

The authoritative output paths for the markdown(s) and Mermaid diagram come from `bundle.output_paths` — write to those exact paths. Do not re-derive filenames from the chunk id or from any `chunks/index.json`.

Never require or create an unrequested English edition or intermediate.
English defaults only when no language is provided. Shared language-neutral
diagrams remain shared, regardless of the requested documentation languages.
English template headings do not add an English output; apply existing localization rules.

The markdown MUST:

- Follow the kind-specific template exactly (headings, sentence/paragraph minima, FORBIDDEN openers). Templates live under `config/templates/`:
  | Chunk kind                        | Template                                        |
  |-----------------------------------|-------------------------------------------------|
  | `paragraph`, `section`            | `procedure-section-doc.template.md`             |
  | `division` (PROCEDURE)            | `procedure-division.template.md`                |
  | `division` (DATA)                 | `data-division.template.md`                     |
  | `division` (IDENTIFICATION)       | `identification-division.template.md`           |
  | `division` (ENVIRONMENT)          | `environment-division.template.md`              |
  | `data-record`, `copybook-record`  | `data-division.template.md` (single-record mode)|
  | `exec-sql`, `exec-cics`           | `procedure-section-doc.template.md`             |
  | `jcl-job`, `jcl-step`, `jcl-proc` | `jcl-job.template.md`                           |
- Cite source ranges via Pandoc footnote form `[^src-N]` defined in a trailing `## Sources` block. Inline `[FILE:Lx-Ly]` tags are **forbidden** (see `citations-and-confidence.instructions.md`).
- Identifier styling: COBOL/JCL identifiers (program names, paragraphs, DD names, copybooks) MUST match the regex in the active `profile.yaml::identifier_lock_regex` (default `[A-Z][A-Z0-9-]*(\.[A-Z0-9-]+)?`) and be wrapped in backticks.
- **Per-section overview diagram.** The same authoring pass produces `docs/_shared/<basename-with-ext>/diagrams/section-<chunk_id_sanitized>.mmd` using the diagram-kind heuristic from `pipeline-dag.yaml` phase C (default `flowchart TD`; `sequenceDiagram` for CICS; `stateDiagram-v2` for cursor lifecycles; `erDiagram` for record-centric data chunks; **`flowchart LR` for copybook chunks** — the sidecar carries the inclusion graph, NOT the structure / ER fragment which is owned by `diagram-renderer` at `docs/_shared/<copybook>/diagrams/er-fragment.mmd` and embedded verbatim by the copybook markdown; see `config/templates/copybook.template.md` "DIAGRAM OWNERSHIP"). When a chunk's diagram gate fails (e.g. copybook with < 2 includers and no `REPLACING` divergence), the sidecar `.mmd` is NOT written and any stale file from a previous run is removed. No `.svg` rendering here — that is owned by phase D.
- Be written in the requested language. When multiple languages are requested, align heading structure and citation footnotes 1:1 across those editions so [`qa-reviewer`](../qa-reviewer/SKILL.md) can compare them.

A companion language-neutral JSON sidecar is emitted **once per chunk**, independent of the requested languages, at `docs/_reviews/section-doc/<file>__<chunk_id>__inputs.json` capturing the exact bundle the LLM received (template hash, slice hash, chunk-text hash, language list). This sidecar is the deterministic record needed to reproduce the authoring call.

## Procedure

1. **Resolve bundle input.** Locate `docs/_shared/<basename-with-ext>/_bundles/<chunk_id_sanitized>.bundle.md` (LLM input). If only the `.bundle.json` exists, re-run `assemble-inputs.py` (or `render-bundle-md.py --in <bundle.json> --out <bundle.md>`) to regenerate the MD view. On miss: exit `4` and report the exact missing path.
2. **Validate bundle schema.** Ensure the MD view contains every required block referenced in the Bundle Schema section below: `## Metadata` (with `bundle_version`, `source_path`, `source_kind`, `chunk.id`, `chunk.kind`, `diagram_kind`, `template_path`, `languages`, `chunk_text_sha`, `facts_slice_sha`, `template_sha`), `## Output paths`, `## Chunk`, `## Source text`, `## Facts slice`, `## Profile`, `## Template`. On miss: exit `4`.
3. **Author.** The `section-doc-writer` agent reads the bundle and writes one `.md` per language plus the per-section `.mmd`. The skill does NOT shell out to an LLM CLI — authoring is an agent responsibility.
4. **Populate Cross-references from the bundle.** The `## Cross-references` block is NOT optional filler — it is the deterministic xref view for the chunk and MUST be filled from the bundle's `## Facts slice` block, not guessed:
   - `### Calls / uses (outgoing)` — enumerate every entry in the `performs`, `calls`, `go_tos`, `copybooks`, `exec_sql` (call/cursor targets) and `exec_cics` (LINK/XCTL/READ/WRITE targets) sub-sections of `## Facts slice` whose `chunk_id` equals the current chunk. Each entry MUST include the target identifier, the `via` kind (`PERFORM`, `CALL`, `GO TO`, `COPY`, `cics-link`, `cics-xctl`, `exec-sql`, …) and the source line.
   - `### Called / used by (incoming)` — copy every entry from the `incoming_xref` table under `## Facts slice` (file-level: external programs / JCL steps / copybook consumers that reach THIS source file). For paragraph/section chunks, ALSO list intra-file PERFORM callers if they are discoverable from the bundle (e.g. the `siblings` table plus the parent chunk record under `## Chunk`). Each row MUST cite the caller source path and line.
   - `### Data touched (records read / written by this section)` — REQUIRED on procedure paragraphs / sections / divisions, on `exec-sql` and `exec-cics` chunks, and on `data-record` / `copybook-record` chunks. For each `01`-level (or elementary field) the chunk reads or writes, list: data name, mode (`R` / `W` / `R/W` / `INIT`), verb (`READ`, `WRITE`, `MOVE`, `EXEC SQL FETCH`, `EXEC CICS RECEIVE MAP`, `CALL … USING`, …), the source file that DECLARES the record (the current source for in-line records; the copybook member for `COPY`-included records), and every OTHER workspace source that also touches the same record. Cross-source partners are derived from the file-level `incoming_xref[]` rows whose `via == "copy"` (programs that include the same copybook layout) and from the `data_records[]` / `copybooks[]` projections under `## Facts slice`. Use `_None._` when the record is private to this program; never silently omit the table.
   - `### File / dataset bindings` — REQUIRED on every chunk that opens, reads or writes an external file (procedure sections issuing `OPEN` / `READ` / `WRITE`, `data-division` chunks declaring `FD` / `SELECT`, `jcl-step` chunks declaring `DD` statements). Build by joining the file-level `files[]` slice (logical SELECT/FD ↔ external DDNAME ↔ DSN) with every JCL step recorded in the bundle's `incoming_xref[]` (rows with `via == "jcl-step"`) — those rows pin the JCL source file and step that schedules this program. For JCL chunks, the dual table (`### DDNAME ↔ program data bindings`) joins each `DD` to the FD/SELECT and `01`-level inside the invoked program; when the invoked program's `files[]` / `data_records[]` are NOT embedded in this bundle, mark the partner cells as `—` and surface a `_Warnings_` bullet explaining the missing cross-source data — never guess.
   - `### External dependencies` — datasets / DD names / SQL tables / CICS maps / external programs referenced by the chunk (from the `files`, `jcl_steps`, `exec_sql`, `exec_cics`, `bms_maps` sub-sections under `## Facts slice`).
   - For data chunks (`data-record`, `copybook-record`, `data-division`), additionally fill `### Producers (write the record)`, `### Consumers (read the record)` and `### Shared layout` / `### Workspace data lineage` from `incoming_xref[]` (`via == "copy"` rows and `via == "jcl-step"` rows when the dataset bound to an FD is also referenced by a JCL DD) — workspace scope, not just the current source file.
   - If a subsection is genuinely empty after exhausting the bundle, write `_None._` explicitly. Never silently omit a subsection. NEVER guess a `DSN`, an FD binding or a caller that is not present in the bundle; surface the gap as a `_Warnings_` bullet instead.
5. **Validate mechanically.** Immediately invoke [`qa-reviewer`](../qa-reviewer/SKILL.md) on the produced markdown. Fail-fast: do not move on to the next chunk while findings remain.
6. **Report.** Print one summary line per requested language: `OK: wrote docs/<lang>/<file>/sections/<chunk_id>.md  (words=…, sources=…, diagram=…)` and the qa-reviewer verdict.

## Bundle Schema

Two sibling artifacts live next to each other under `docs/_shared/<file>/_bundles/<chunk_id>.bundle.{json,md}`:

- `.bundle.json` — **authoritative**; consumed by the mechanical `qa-reviewer` checker (`check-section-doc.py`), tracked by `scripts/dispatchers/run-docs-copilot-batch.ps1`'s SHA/state map, and referenced by all three SHA fields. Schema below.
- `.bundle.md` — **LLM input**; deterministic Markdown projection rendered by [scripts/render-bundle-md.py](./scripts/render-bundle-md.py) and emitted automatically by `assemble-inputs.py --out`. Same data, headed sections + tables for easier reading. Never edit by hand.

The authoritative JSON MUST contain (top-level keys, in this order):

```jsonc
{
  "bundle_version":   "1.0",
  "source_path":      "repos/sample1/COBOL/DEMO100.CBL",
  "source_kind":      "cobol|cl|jcl|proc|copybook|bms",
  "chunk":            { /* embedded chunk record */ },
  "chunk_text":       "…raw source bytes of the chunk, LF-normalized…",
  "chunk_text_sha":   "<64-hex>",
  "facts_slice":      { /* embedded per-chunk facts subset */ },
  "facts_slice_sha":  "<64-hex>",
  "template_path":    "config/templates/procedure-section-doc.template.md",
  "template_text":    "…full template…",
  "template_sha":     "<64-hex>",
  "profile":          { /* loaded profile.yaml (thresholds, identifier regex, citation policy) */ },
  "languages":        ["en", "it"],
  "diagram_kind":     "flowchart TD | flowchart LR | sequenceDiagram | stateDiagram-v2 | erDiagram",
  "output_paths": {
    "en":     "docs/en/DEMO100.CBL/sections/DEMO100__procedure-division__MAIN-PROCESSING__A000-MAIN.md",
    "it":     "docs/it/DEMO100.CBL/sections/DEMO100__procedure-division__MAIN-PROCESSING__A000-MAIN.md",
    "diagram":"docs/_shared/DEMO100.CBL/diagrams/section-DEMO100__procedure-division__MAIN-PROCESSING__A000-MAIN.mmd"
  }
}
```

All sha256 fields are over the canonical byte form (template/source bytes UTF-8, facts_slice as `json.dumps(..., sort_keys=True, separators=(",",":"))` to keep the hash stable).

## Determinism Rules

- The bundle packager is fully deterministic: re-running on unchanged inputs MUST emit a byte-identical bundle.
- The LLM authoring step is NOT deterministic — that is expected. What IS deterministic is the **shape**: same template, same citation footnotes, same identifier styling, same diagram-kind heuristic, same thresholds.
- Forbidden re-derivations:
  - Never re-derive output filenames from the chunk id; always use `bundle.output_paths` verbatim.
  - Never load runtime inputs from `facts.json`, `facts-slices`, `chunks`, `chunk-manifest.json`, or `chunks/index.json` directly. Use the prepared bundle only.
- Requested editions are authored in the **same LLM call**. With multiple requested languages, `translator` may repair a missing or drifted requested sibling; it must never create an unrequested English intermediate.

## Resources

- **Runtime input (LLM):** the rendered Markdown view at `docs/_shared/<file>/_bundles/<chunk_id>.bundle.md` is the canonical runtime input for the authoring step.
- **Runtime input (mechanical tooling):** the sibling `.bundle.json` is the authoritative artifact for SHAs, output_paths parsing, and the `qa-reviewer` checker.
- **Bundle producers (out-of-band):**
  - [scripts/assemble-inputs.py](./scripts/assemble-inputs.py) — packages one bundle from `chunk-manifest.json` + `chunks/index.json` + `facts-slices/<chunk>.json` + template + profile; writes both the `.bundle.json` and the `.bundle.md` view (suppress the MD via `--no-md-view`). Run upfront; never invoked from the authoring path.
  - [scripts/render-bundle-md.py](./scripts/render-bundle-md.py) — standalone renderer (`--in <bundle.json> --out <bundle.md>`); used to backfill the MD view if it is missing.
  - [scripts/stage-bundles.py](./scripts/stage-bundles.py) — bulk runner for `assemble-inputs.py` across every chunk of one source.

## Pipeline Wiring

`config/pipeline-dag.yaml` phase C lists `section-doc-writer` as the per-section LLM step with the per-chunk bundle JSON as its single input. The deterministic bundle-producer half lives in `scripts/stage-bundles.py` (which invokes `scripts/assemble-inputs.py` per chunk). The LLM authoring half is owned by `.github/agents/section-doc-writer.agent.md` and orchestrated by `.github/agents/section-agent.agent.md` (writer + reviewer loop).

## Common Pitfalls

- **Missing bundle.** This skill requires a prepared bundle per chunk. Do not bypass the bundle by reading `facts.json`, `facts-slices`, or `chunks` directly in runtime authoring.
- **Output-path drift.** If a downstream consumer derives the filename from the chunk id with its own ad-hoc regex instead of `bundle.output_paths`, it will mis-bind in the presence of phase-A renames. Always use `bundle.output_paths` verbatim.
- **Authoring without QA.** Skipping the immediate `qa-reviewer` call lets mechanical violations (forbidden openers, missing citations, line-count mentions in prose) accumulate silently. Run it after every authoring call, not as a batch sweep.
- **Co-authoring drift.** When multiple languages are requested, factual and structural differences between their editions are flagged by `qa-reviewer`. Co-author those requested languages in the same LLM call; do not create an unrequested translation.
