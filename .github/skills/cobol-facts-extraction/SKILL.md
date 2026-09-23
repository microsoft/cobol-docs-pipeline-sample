---
name: cobol-facts-extraction
description: 'Deterministically extract `facts.json` from mainframe or IBM i (AS400) COBOL, CBLLE, SQLCBLLE, CL, CLP, CLLE, JCL, PROC, copybook, or BMS. USE FOR: IBM i CL command facts, CALL/CALLPRC/SBMJOB, OVRDBF/MONMSG, COBOL facts, call graphs, and incoming xref. DO NOT USE FOR: chunking, markdown docs, copybook expansion, or LLM summarization.'
argument-hint: 'Path to a source file (e.g. repos/sample1/COBOL/DEMO100.CBL) plus its chunk-manifest.json, optional --output, --source-root, --manifest, or `--xref-pass` for the workspace-scope incoming xref pass.'
---

# COBOL / CL / JCL Facts Extraction

## Platform Contract

Preserve `source_platform` from the manifest in `facts.json`. For `ibmi`, file
assignments such as `DATABASE-*`, DB2 for i SQL options, library/object/member
references, and ILE calls are IBM i evidence; do not reinterpret them as JCL,
DDNAME, z/OS dataset, CICS, or load-module semantics.
For `source_kind: cl`, preserve `PGM`, `DCL`, `CALL`, `CALLPRC`, `SBMJOB`,
`OVRDBF`, `DLTOVR`, `MONMSG`, and message commands as IBM i CL evidence.

Deterministic phase-B facts extractor for the COBOL/CL/JCL reverse-engineering pipeline. Produces a `facts.json` knowledge graph consumed by downstream phases. No LLM calls.

## When to Use

- The user asks to "extract facts", "generate facts.json", "build call graph", or "cross-reference" for a COBOL, JCL, copybook, BMS or PROC source.
- A `chunk-manifest.json` already exists (phase A is done) and the per-file facts file is missing or stale.
- The workspace incoming-xref pass needs to be (re-)computed across all per-file `facts.json` files (`--xref-pass`).
- Validating an existing `facts.json` against [schemas/outputs.schema.json](./schemas/outputs.schema.json).

Do **not** use this skill for chunking (phase A — see [`cobol-chunking`](../cobol-chunking/SKILL.md)), markdown generation (phase C), copybook *expansion*, or free-form summarization.

## Output Contract

A single JSON file (canonical name `facts.json`) validated by [schemas/outputs.schema.json](./schemas/outputs.schema.json). Top-level shape:

```jsonc
{
  "facts_version":     "1.0",
  "source_path":       "repos/sample1/COBOL/DEMO100.CBL", // relative to source_root
  "source_kind":       "cobol|cl|jcl|proc|copybook|bms",
  "manifest_sha256":   "<64-hex of the chunk-manifest.json bytes used as input>",
  "source_sha256":     "<64-hex of the raw source bytes>",
  "program_id":        "DEMO100",            // null for jcl/proc/copybook/bms
  "paragraphs":        [ /* call-graph nodes, see below */ ],
  "performs":          [ /* PERFORM edges */ ],
  "go_tos":            [ /* GO TO edges */ ],
  "calls":             [ /* CALL / LINK / XCTL edges */ ],
  "copybooks":         [ /* COPY references */ ],
  "exec_sql":          [ /* EXEC SQL blocks */ ],
  "exec_cics":         [ /* EXEC CICS blocks */ ],
  "data_records":      [ /* DATA DIVISION 01-levels */ ],
  "files":             [ /* SELECT/FD entries (cobol) or DD statements (jcl) */ ],
  "jcl_steps":         [ /* jcl/proc only */ ],
  "cl_commands":       [ /* IBM i CL only */ ],
  "bms_maps":          [ /* bms only */ ],
  "incoming_xref":     [ /* populated by --xref-pass; empty on first write */ ],
  "errors":            [ /* {code, message, line} */ ]
}
```

Collection element shapes (see the schema for the binding contract):

| collection      | required keys                                            | notes |
|-----------------|----------------------------------------------------------|-------|
| `paragraphs`    | `chunk_id`, `name`, `section`, `start_line`, `end_line`  | One per COBOL paragraph or section (PROCEDURE division). |
| `performs`      | `from`, `to`, `kind` (`simple`/`thru`/`times`/`until`/`varying`), `line` | `from` and `to` are paragraph/section `name`s. |
| `go_tos`        | `from`, `to`, `line`                                     | `to` may be a list when `DEPENDING ON` is used. |
| `calls`         | `from`, `target`, `kind` (`call`/`cics-link`/`cics-xctl`/`exec-program`), `dynamic` (bool), `line` | `target` is a literal program name OR a working-storage variable name when `dynamic=true`. |
| `copybooks`     | `name`, `library`, `replacing`, `line`                   | `library` null when not specified; `replacing` is a list of `{from, to}` pairs. |
| `exec_sql`      | `chunk_id`, `statement`, `tables`, `cursors`, `host_vars`, `start_line`, `end_line` | `statement` is the first SQL verb (`SELECT`/`FETCH`/`OPEN`/...). |
| `exec_cics`     | `chunk_id`, `command`, `args`, `start_line`, `end_line`  | `command` is the CICS verb (`LINK`/`XCTL`/`READ`/...). |
| `data_records`  | `chunk_id`, `name`, `level`, `picture`, `usage`, `redefines`, `occurs`, `start_line`, `end_line` | One per 01-level item; nested 02–49 items are not enumerated here. |
| `files`         | `name`, `assign_to`, `organization`, `access_mode`, `record_name`, `line` | COBOL `SELECT`+`FD` merge; for JCL this collection is empty. |
| `jcl_steps`     | `chunk_id`, `name`, `program`, `proc`, `resolved_source`, `resolved_kind`, `dds`, `start_line`, `end_line` | `dds` is a list of `{name, dsn, disp}` records. `resolved_source`/`resolved_kind` are populated by the `--xref-pass` (null on first write) with the workspace `source_path`/`source_kind` of the EXEC `PGM=`/`PROC` target. |
| `bms_maps`      | `chunk_id`, `mapset`, `map`, `fields`, `start_line`, `end_line` | `fields` is a list of `{name, attrb, length, initial}` records. |
| `incoming_xref` | `caller_source`, `caller_kind`, `via`, `line`            | Populated by the `--xref-pass` (workspace scope). `via` ∈ `call`/`cics-link`/`cics-xctl`/`copy`/`jcl-step`. |

Every collection entry that originates from inside a chunk MUST carry a `chunk_id` matching a chunk in the input `chunk-manifest.json`. This is the join key the per-section subagents in phase C rely on for the `scripts/slice-facts.py` fan-out.

## Procedure

1. **Resolve inputs.** Locate the source file (same rules as [`cobol-chunking`](../cobol-chunking/SKILL.md): tried relative to repo root first, then to `source_root` from `config/pipeline.yaml`). Locate the chunk manifest at `docs/_shared/<basename-with-ext>/chunk-manifest.json` unless `--manifest <path>` overrides it. Reject if either input is missing.
2. **Run the extractor.** Invoke [scripts/extract-facts.py](./scripts/extract-facts.py):
   ```powershell
   python .github/skills/cobol-facts-extraction/scripts/extract-facts.py `
     --source repos/sample1/COBOL/DEMO100.CBL
   ```
   Flags:
   - `--output <path>` — override the default `docs/_shared/<basename-with-ext>/facts.json`.
   - `--source-root <root>` — override `pipeline.yaml::source_root`.
   - `--manifest <path>` — override the default chunk-manifest location.
   - `--xref-pass` — switch to workspace mode: re-scan all per-file `facts.json` files under `docs/_shared/**/facts.json` and populate `incoming_xref[]` on every file. Equivalent to running [scripts/xref-incoming-pass.py](./scripts/xref-incoming-pass.py) directly. No `--source` is required in this mode.
3. **Validate.** The script self-validates against [schemas/outputs.schema.json](./schemas/outputs.schema.json) when `jsonschema` is installed (`pip install jsonschema pyyaml`). On schema failure: exit code `3`, error on stderr, **no file written**.
4. **Spot-check.** Compare the shape against [samples/DEMO100.expected.facts.json](./samples/DEMO100.expected.facts.json) for the bundled fixture [samples/DEMO100.sample.cbl](./samples/DEMO100.sample.cbl) (+ [samples/DEMO100.chunk-manifest.json](./samples/DEMO100.chunk-manifest.json)). Confirm:
   - Every `chunk_id` referenced in any collection exists in the input chunk manifest.
   - Every `performs[].from` / `go_tos[].from` / `calls[].from` matches a `paragraphs[].name`.
   - `manifest_sha256` matches the sha256 of the manifest file actually consumed.
   - `incoming_xref[]` is `[]` on a first write (it is populated only by `--xref-pass`).
5. **Report.** The script prints `OK: wrote …`, total counts per collection (`paragraphs=N performs=N calls=N copybooks=N exec_sql=N …`), detected source kind, source/manifest sha256 prefixes, and any entries from `errors[]`. Do not echo the full JSON.

## Batch / Parallel Extraction

When the user asks to extract facts for **more than one file** (a list, a glob, a folder, "all COBOL files", etc.), do **not** run `extract-facts.py` once per file inline.

**Preferred path — use the bundled runner.** Invoke [scripts/extract_facts_batch.ps1](./scripts/extract_facts_batch.ps1), which is the reusable, parameterized parallel wrapper (mirrors `cobol-chunking`'s `chunk_batch.ps1`):

```powershell
pwsh -File .github/skills/cobol-facts-extraction/scripts/extract_facts_batch.ps1 `
     -Paths repos/sample1/COBOL/*.CBL
```

Useful parameters:
- `-Files <string[]>` — explicit list of paths.
- `-Paths <string[]>` — directories or globs to expand.
- `-Manifest <path.json|.csv>` — per-entry inputs `{path, sourceRoot, output, manifest}` when files need different overrides.
- `-SourceRoot` — applied to every input when uniform.
- `-Throttle <int>` — defaults to `[Environment]::ProcessorCount`.
- `-ResultsXml <path>` — defaults to `facts_results.xml`.
- `-ExcludeExtensions <string[]>` — case-insensitive extensions skipped when expanding `-Paths`. Default: `.cob, .inp, .itt` (same rationale as the chunking batch runner — copybooks and JCL inline-data are consumed by reference, not extracted as standalone sources).
- `-XrefPass` — switch the runner into workspace mode; ignores all input parameters and invokes `xref-incoming-pass.py` once.

The runner is deterministic (sorted inputs and results, no timestamps), captures per-file stdout/stderr/exit, persists results via `Export-Clixml`, and exits `1` if any child failed.

**Workspace xref pass is single-shot.** After the per-file fan-out completes, run:
```powershell
pwsh -File .github/skills/cobol-facts-extraction/scripts/extract_facts_batch.ps1 -XrefPass
```
This step is **not** parallelizable — it reads every `facts.json` in `docs/_shared/**/facts.json`, builds the inverted caller map (CALL / EXEC CICS LINK / EXEC CICS XCTL / COPY / JCL `EXEC PGM=`), then rewrites each file's `incoming_xref[]` in place. Re-running with no upstream changes MUST yield byte-identical files.

**Ad-hoc helpers go in `temp/`.** Same rule as `cobol-chunking`: only create a custom wrapper when `extract_facts_batch.ps1` genuinely cannot express the run. Put it in `temp/` (e.g. `temp/extract_facts_<short-name>.ps1`), never at the repo root or alongside sources.

Report only the summary line (`DONE total=… ok=… failed=…`) plus any failures, matching the single-file reporting contract in step 5.

## Determinism Rules

- No LLM calls.
- Re-running on an unchanged source + manifest pair MUST yield byte-identical JSON (stable key order, no timestamps, sha256 fingerprints of raw bytes for both source and manifest).
- Comment/debug lines (column 7 = `*`, `/`, `D`, `d`, `$`) and continuation lines (`-`) never contribute facts; their content belongs to the *enclosing* statement's logical line.
- COBOL keywords are only recognized when they appear in Area A/B (columns 8–72), never in the sequence area (columns 1–6).
- EXEC SQL / EXEC CICS blocks are extracted atomically — the extractor never splits a block across statements; the whole block is captured under its enclosing paragraph's `chunk_id`.
- `--xref-pass` clears and rewrites `incoming_xref[]` from scratch on every run; it never touches any other collection.

## Resources

- [scripts/extract-facts.py](./scripts/extract-facts.py) — the extractor (per-file entry point).
- [scripts/xref-incoming-pass.py](./scripts/xref-incoming-pass.py) — the workspace-scope incoming-xref pass.
- [scripts/extract_facts_batch.ps1](./scripts/extract_facts_batch.ps1) — reusable parallel batch runner.
- [schemas/outputs.schema.json](./schemas/outputs.schema.json) — JSON Schema (Draft 2020-12), gate for the writer.
- [samples/DEMO100.sample.cbl](./samples/DEMO100.sample.cbl) — minimal COBOL fixture (mirrors `cobol-chunking`).
- [samples/DEMO100.chunk-manifest.json](./samples/DEMO100.chunk-manifest.json) — input chunk manifest for the fixture.
- [samples/DEMO100.expected.facts.json](./samples/DEMO100.expected.facts.json) — expected facts graph for the fixture (sha256 fields left as placeholders).
- [prompts/extract-facts.prompt.md](./prompts/extract-facts.prompt.md) — `/extract-facts` slash-command wrapper.

## Pipeline Wiring

`config/pipeline-dag.yaml` phase B invokes `skills/cobol-facts-extraction/scripts/extract-facts.py` per file and `skills/cobol-facts-extraction/scripts/xref-incoming-pass.py` once for the workspace-scope incoming-xref pass. The expected output path is `docs/_shared/<file>/facts.json` — exactly the default this script writes. Keep the schema path (`schemas/outputs.schema.json`), the output filename, and the default output directory in sync with the DAG.

> Wired in `config/pipeline-dag.yaml` phase B as `skills/cobol-facts-extraction/scripts/extract-facts.py` (per-file) and `skills/cobol-facts-extraction/scripts/xref-incoming-pass.py` (workspace pass).

## Common Pitfalls

- **Stale manifest.** If `manifest_sha256` no longer matches the manifest on disk, re-run phase A (`cobol-chunking`) BEFORE re-running this extractor — `chunk_id` references go silently wrong otherwise.
- **Continuation literals.** A `CALL "PGM" USING …` whose literal is split across a column-7 `-` continuation line is one logical CALL; the extractor folds continuations before regex matching.
- **Dynamic CALLs.** `CALL WS-PROGRAM` produces `calls[*].dynamic=true` with `target` set to the variable name. The xref pass cannot resolve these without value-set analysis; they appear as unresolved targets and are reported in `errors[]` with code `DYNAMIC_CALL_UNRESOLVED` (warning, not fatal).
- **PERFORM THRU.** `PERFORM A-PARA THRU Z-PARA` emits ONE `performs[]` edge with `kind=thru` and `to=A-PARA`; the `thru_to=Z-PARA` field carries the range end. Do not synthesize per-paragraph edges for everything in between.
- **EXEC SQL host variables.** Only `:HOST-VAR` tokens inside an EXEC SQL block are recorded under `host_vars`; SQL identifiers and string literals are not. The block text is preserved verbatim (with continuation lines folded) in `statement_text` for downstream consumers — never re-parsed by this skill.
- **JCL inline data.** `DD *` / `DD DATA` inline data is captured by reference (`dsn=null`, `disp=null`, with `inline=true`); the inline payload itself is not embedded in `facts.json`.
- **Missing deps.** The scripts require `pyyaml` (always) and `jsonschema` (optional but recommended): `pip install pyyaml jsonschema`.
