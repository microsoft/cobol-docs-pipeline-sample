---
name: cobol-chunking
description: 'Deterministically chunk mainframe or IBM i (AS400) sources (COBOL, CBLLE, SQLCBLLE, CL, CLP, CLLE, JCL, PROC, copybook, BMS) into `chunk-manifest.json`. USE FOR: chunk COBOL, ILE COBOL, IBM i Control Language, CLLE program, JCL job, copybook, phase A chunking, EXEC SQL/CICS blocks, and 01-level records. DO NOT USE FOR: copybook expansion, LLM summarization, or markdown docs.'
argument-hint: 'Path to a source file (e.g. DEMO100.CBL or ORDENTRY.SQLCBLLE), optional --output, --source-root, --kind-hint, --platform-hint mainframe|ibmi|auto, --encoding-hint'
---

# COBOL / CL / JCL Chunking

## Platform Contract

- `source_kind` remains structural (`cobol`, `cl`, `jcl`, `proc`, `copybook`, `bms`).
- `source_platform` is always resolved to `mainframe` or `ibmi`; `ibmi`
  covers IBM i, AS/400, iSeries, and ILE COBOL terminology.
- `.CBLLE` and `.SQLCBLLE` resolve to COBOL on IBM i. Use
  `--platform-hint` or `config/pipeline.yaml::platforms` for explicit overrides.
- `.CL`, `.CLP`, and `.CLLE` resolve to CL on IBM i. CL is IBM i control
  language and must not be interpreted as mainframe JCL.

Deterministic phase-A chunker for the COBOL/CL/JCL reverse-engineering pipeline. Produces a `chunk-manifest.json` consumed by downstream phases. No LLM calls.

## When to Use

- The user asks to "chunk", "split", "segment", or "create chunks.json / chunk-manifest.json" for a COBOL, JCL, copybook, BMS or PROC source.
- A new source has been added and needs a manifest before facts extraction.
- An existing manifest is stale (source `sha256` changed) and must be regenerated.
- Validating the structure of an existing manifest against [outputs.schema.json](./schemas/outputs.schema.json).

Do **not** use this skill for copybook *expansion* (inlining `COPY` statements), free-form summarization, or markdown generation — those are owned by other agents in the pipeline.

## Output Contract

A single JSON file (canonical name `chunk-manifest.json`) validated by [schemas/outputs.schema.json](./schemas/outputs.schema.json). Top-level shape:

```jsonc
{
  "manifest_version": "1.0",
  "source_path":      "repos/sample1/COBOL/DEMO100.CBL", // relative to source_root
  "source_kind":      "cobol|cl|jcl|proc|copybook|bms",
  "encoding_detected":"utf-8|cp037|cp1252|latin-1",
  "sha256":           "<64-hex of raw bytes>",
  "line_count":       12345,
  "copybooks_expanded": [],   // populated only if expansion is enabled (not yet)
  "chunks":           [ /* see below */ ],
  "errors":           [ /* {code,message,line} */ ]
}
```

Chunk `kind` values, by `source_kind`:

| source_kind  | emitted chunk kinds |
|--------------|---------------------|
| `cobol`      | `division`, `section` (PROCEDURE only), `paragraph` (PROCEDURE only), `exec-sql`, `exec-cics`, `data-record` (DATA DIVISION 01-levels) |
| `copybook`   | `copybook-record` (top-level 01s) |
| `cl`         | `cl-program`, `cl-command` |
| `jcl`/`proc` | `jcl-job`, `jcl-step`, `jcl-proc` |
| `bms`        | `bms-mapset`, `bms-map`, `bms-field` |

`id` is a slash-delimited hierarchical path (e.g. `DEMO100/procedure-division/MAIN-PROCESSING/A000-MAIN`). `parent_id` is `null` for top-level chunks.

## Procedure

1. **Resolve inputs.** `--source` is tried first relative to repo root, then to `source_root` from `config/pipeline.yaml`. Reject if neither resolves.
2. **Run the chunker.** Invoke [scripts/chunk.py](./scripts/chunk.py):
   ```powershell
   python .github/skills/cobol-chunking/scripts/chunk.py `
     --source repos/sample1/COBOL/DEMO100.CBL
   ```
   Flags:
   - `--output <path>` — override the default `docs/_shared/<basename-with-ext>/chunk-manifest.json`.
   - `--source-root <root>` — override `pipeline.yaml::source_root`.
  - `--kind-hint cobol|cl|jcl|copybook|bms|proc|auto` — force a kind when auto-detection is wrong.
3. **Validate.** The script self-validates against [schemas/outputs.schema.json](./schemas/outputs.schema.json) when `jsonschema` is installed (`pip install jsonschema pyyaml`). On schema failure: exit code `3`, error on stderr, **no manifest written**.
4. **Spot-check.** Compare the shape against [samples/DEMO100.expected.manifest.json](./samples/DEMO100.expected.manifest.json) for the bundled fixture [samples/DEMO100.sample.cbl](./samples/DEMO100.sample.cbl). Confirm:
   - Every non-null `parent_id` references an existing chunk `id`.
   - `end_line >= start_line` for every chunk; sibling ranges within the same parent do not overlap.
   - `division` chunks cover the file without gaps (first division starts at line 1 to capture the prologue header).
5. **Report.** The script prints `OK: wrote …`, total chunks with `kind=count` breakdown, line count, detected encoding, source kind, sha256 prefix, and any entries from `errors[]`. Do not echo the full JSON.

## Batch / Parallel Chunking

When the user asks to chunk **more than one file** (a list, a glob, a folder, "all COBOL files", etc.), do **not** run `chunk.py` once per file inline.

**Preferred path — use the bundled runner.** Invoke [scripts/chunk_batch.ps1](./scripts/chunk_batch.ps1), which is the reusable, parameterized parallel wrapper:

```powershell
pwsh -File .github/skills/cobol-chunking/scripts/chunk_batch.ps1 `
     -Paths repos/sample1/COBOL/*.CBL
```

Useful parameters:
- `-Files <string[]>` — explicit list of paths.
- `-Paths <string[]>` — directories or globs to expand.
- `-Manifest <path.json|.csv>` — per-entry inputs `{path, hint, sourceRoot, output}` when files need different `--kind-hint` / `--source-root` / `--output`.
- `-KindHint`, `-SourceRoot` — applied to every input when uniform.
- `-Throttle <int>` — defaults to `[Environment]::ProcessorCount`.
- `-ResultsXml <path>` — defaults to `chunk_results.xml`.
- `-ExcludeExtensions <string[]>` — case-insensitive extensions skipped when expanding `-Paths`. Default: `.cob, .inp, .itt`. Pass `@()` to disable. Does not filter `-Files` or `-Manifest` entries.

**Default exclusions when expanding `-Paths`.** The runner skips `.COB`, `.INP`, and `.ITT` files by default because they are referenced — not chunked — by the pipeline:
- `*.COB` files (typically under `COBOL/COPY/`) are copybooks resolved via `pipeline.yaml::copybook_search_paths`, not standalone programs. This mirrors the `COBOL/COPY/**` exclusion in `config/pipeline.yaml`.
- `*.INP` and `*.ITT` files are JCL inline-data / include members consumed by reference from their parent `.JCL` / `.PRC` job; chunking them in isolation produces no useful job/step structure.
Use `-Files` (or `-Manifest`) to chunk one of these explicitly when needed, or override `-ExcludeExtensions` to change the filter set.

The runner is deterministic (sorted inputs and results, no timestamps), captures per-file stdout/stderr/exit, persists results via `Export-Clixml`, and exits `1` if any child failed.

**Ad-hoc helpers go in `temp/`.** Only create a custom wrapper when `chunk_batch.ps1` genuinely cannot express the run (e.g. a one-off mixed catalog of inputs the user pasted). In that case write it to the workspace `temp/` folder (e.g. `temp/chunk_<short-name>.ps1` or `temp/chunk_inputs.json` for the `-Manifest` form), never to the repo root or alongside source. Create `temp/` if missing; do not commit anything under `temp/`. If the helper proves repeatedly useful, promote it into `scripts/` here instead of leaving copies in `temp/`.

Report only the summary line (`DONE total=… ok=… failed=…`) plus any failures, matching the single-file reporting contract in step 5.

## Determinism Rules

- No LLM calls.
- Re-running on an unchanged source MUST yield byte-identical JSON (stable key order, no timestamps, sha256 fingerprint of raw bytes).
- Comment/debug lines (column 7 = `*`, `/`, `D`, `d`, `$`) and continuation lines (`-`) are never treated as chunk headers; they belong to the *enclosing* chunk's range.
- COBOL headers (DIVISION/SECTION/paragraph) are only recognized when they appear in Area A (columns 8–11).
- EXEC SQL / EXEC CICS blocks are emitted as atomic chunks nested under their enclosing paragraph or section.

## Resources

- [scripts/chunk.py](./scripts/chunk.py) — the chunker (entry point).
- [scripts/chunk_batch.ps1](./scripts/chunk_batch.ps1) — reusable parallel batch runner.
- [schemas/outputs.schema.json](./schemas/outputs.schema.json) — JSON Schema (Draft 2020-12), gate for the writer.
- [samples/DEMO100.sample.cbl](./samples/DEMO100.sample.cbl) — minimal COBOL fixture.
- [samples/DEMO100.expected.manifest.json](./samples/DEMO100.expected.manifest.json) — expected outline for the fixture (sha256 left as a placeholder).
- [prompts/chunk-cobol.prompt.md](./prompts/chunk-cobol.prompt.md) — `/chunk-cobol` slash-command wrapper.

## Pipeline Wiring

`config/pipeline-dag.yaml` phase A invokes `skills/cobol-chunking/scripts/chunk.py` and expects the output at `docs/_shared/<file>/chunk-manifest.json` — exactly the default this script writes. Keep the schema path (`schemas/outputs.schema.json`), the output filename, and the default output directory in sync with the DAG.

## Common Pitfalls

- **Column-7 indicator area.** `*`, `/`, `D`/`d`, `$` mean comment/debug — never start a chunk on those lines.
- **Continuation lines (`-` in column 7).** Belong to the previous statement; never split here.
- **Inline `EXEC SQL` / `EXEC CICS` blocks.** Atomic — never split mid-block. The chunker emits them as `exec-sql`/`exec-cics` children of the enclosing paragraph/section.
- **Sections outside PROCEDURE.** The chunker intentionally does NOT emit `ENVIRONMENT`/`DATA` sub-sections (CONFIGURATION, FILE, WORKING-STORAGE, …) as separate chunks — only DATA DIVISION 01-level records and PROCEDURE sections/paragraphs.
- **JCL JOB extends to EOF.** The `jcl-job` chunk's range spans from the JOB card to end-of-file; nested `jcl-step` / `jcl-proc` chunks carve it up.
- **Missing deps.** The script requires `pyyaml` (always) and `jsonschema` (optional but recommended): `pip install pyyaml jsonschema`.
