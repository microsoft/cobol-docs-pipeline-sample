---
name: facts-slicing
description: 'Deterministically fan a per-file `facts.json` into per-chunk slice files (`docs/_shared/<file>/facts-slices/<chunk_id>.json`) so phase-C per-section subagents (section-doc-writer, qa-reviewer) read only the ~10% of facts they need. USE FOR: slice facts.json, generate facts-slices, per-chunk facts, prepare phase-C inputs, fan facts to per-section subagents, regenerate stale slices, slice one chunk on demand. DO NOT USE FOR: chunking (phase A — use cobol-chunking), facts extraction (phase B — use cobol-facts-extraction), markdown generation (phase C — use section-doc-writer), copybook expansion, or LLM-based summarization.'
argument-hint: 'Path to a source file or its facts.json. Optional --chunk-id <id> to slice one chunk, --all (default) to slice every chunk, --output-dir to override the default facts-slices directory, --manifest to override the chunk-manifest.json location.'
---

# Facts Slicing

Deterministic phase-C input preparer. Reads a per-file `facts.json` + its `chunk-manifest.json` and emits one slice per chunk under `docs/_shared/<file>/facts-slices/<chunk_id>.json`. No LLM calls — pure JSON filtering, schema-validated before write.

The slice is the **only** facts file each per-section subagent is allowed to read in phase C. Loading the full `facts.json` from a per-section subagent is forbidden by `config/pipeline-dag.yaml`; this skill enforces that contract by producing slim, chunk-scoped slices (~5–15% the size of the full file).

## When to Use

- The user asks to "slice facts", "generate facts-slices", "prepare per-chunk facts", or "fan facts.json to per-section subagents".
- Phase B has just (re-)written a `facts.json` and the matching `facts-slices/` directory is missing or stale (different `source_sha256` / `manifest_sha256`).
- A single section needs to be re-rendered and only its slice is required (`--chunk-id <id>`).
- Validating an existing slice against [schemas/outputs.schema.json](./schemas/outputs.schema.json).

Do **not** use this skill for chunking ([`cobol-chunking`](../cobol-chunking/SKILL.md)), facts extraction ([`cobol-facts-extraction`](../cobol-facts-extraction/SKILL.md)), markdown writing (phase C), or copybook *expansion*.

## Output Contract

One JSON file per chunk at `docs/_shared/<basename-with-ext>/facts-slices/<chunk_id_sanitized>.json`, validated by [schemas/outputs.schema.json](./schemas/outputs.schema.json). `<chunk_id_sanitized>` replaces `/` with `__` (the only chunk-id character not safe on Windows/POSIX paths).

Top-level shape:

```jsonc
{
  "slice_version":     "1.0",
  "source_path":       "repos/sample1/COBOL/DEMO100.CBL",
  "source_kind":       "cobol|cl|jcl|proc|copybook|bms",
  "program_id":        "DEMO100",                       // copied from facts.json
  "source_sha256":     "<64-hex>",                      // copied from facts.json
  "manifest_sha256":   "<64-hex>",                      // copied from facts.json
  "facts_sha256":      "<64-hex of the facts.json bytes>",
  "chunk": {
    "id":         "DEMO100/procedure-division/MAIN-PROCESSING/A000-MAIN",
    "kind":       "paragraph",
    "name":       "A000-MAIN",
    "parent_id":  "DEMO100/procedure-division/MAIN-PROCESSING",
    "start_line": 22,
    "end_line":   26
  },
  "descendant_chunk_ids": [ /* every nested chunk id under this one, sorted */ ],
  "paragraphs":   [ /* this chunk + descendants only */ ],
  "performs":     [ /* edges whose chunk_id is in {this} ∪ descendants */ ],
  "go_tos":       [ /* same filter */ ],
  "calls":        [ /* same filter */ ],
  "copybooks":    [ /* same filter */ ],
  "exec_sql":     [ /* same filter */ ],
  "exec_cics":    [ /* same filter */ ],
  "data_records": [ /* same filter */ ],
  "jcl_steps":    [ /* same filter */ ],
  "bms_maps":     [ /* same filter */ ],
  "files":        [ /* ALL file/SELECT entries — never per-chunk, always full */ ],
  "incoming_xref":[ /* ALL — file-level; copied verbatim from facts.json */ ],
  "siblings": [
    { "id": "...", "kind": "paragraph", "name": "..." }
    /* every immediate sibling of this chunk (same parent_id), for nav */
  ],
  "errors": []
}
```

Filtering rules (deterministic):

| collection      | filter |
|-----------------|--------|
| `paragraphs`    | entry `chunk_id` ∈ `{this.id} ∪ descendants` |
| `performs`, `go_tos`, `calls`, `copybooks`, `exec_sql`, `exec_cics`, `data_records`, `jcl_steps`, `bms_maps` | entry `chunk_id` ∈ `{this.id} ∪ descendants` |
| `files`         | always full list (file-level SELECT/FD is cross-cutting; small) |
| `incoming_xref` | always full list (file-level; small) |
| `siblings`      | every chunk in the manifest whose `parent_id` equals `this.parent_id`, sorted by `start_line`. Excludes self. |

Slices are **read-only inputs** for downstream subagents — they never round-trip back into `facts.json`.

## Procedure

1. **Resolve inputs.** Locate the source file (same rules as upstream skills: relative to repo root, then to `source_root` from `config/pipeline.yaml`). Default `facts.json` and `chunk-manifest.json` live at `docs/_shared/<basename-with-ext>/`. Reject if either is missing. Accept `--facts <path>` to point directly at a facts file when the source itself is not available.
2. **Run the slicer.** Invoke [scripts/slice-facts.py](./scripts/slice-facts.py):
   ```powershell
   python .github/skills/facts-slicing/scripts/slice-facts.py `
     --source repos/sample1/COBOL/DEMO100.CBL
   ```
   Flags:
   - `--chunk-id <id>` — slice ONLY that chunk (must exist in the manifest); default is `--all`.
   - `--all` — slice every chunk in the manifest (default).
   - `--output-dir <path>` — override `docs/_shared/<basename-with-ext>/facts-slices`.
   - `--source-root <root>` — override `pipeline.yaml::source_root`.
   - `--facts <path>` — override the default facts.json location.
   - `--manifest <path>` — override the default chunk-manifest.json location.
   - `--prune` — delete any pre-existing slice files in the output directory whose chunk id is NOT in the current manifest (default: keep stale files in place and warn).
3. **Stale-input check.** Before writing, the script confirms `facts.json::manifest_sha256` equals the sha256 of the manifest file actually on disk. On mismatch: exit code `4`, error on stderr, **no slice written**. Re-run `cobol-facts-extraction` first.
4. **Validate.** Each emitted slice is self-validated against [schemas/outputs.schema.json](./schemas/outputs.schema.json) when `jsonschema` is installed (`pip install jsonschema pyyaml`). On schema failure: exit code `3`, error on stderr, **no slice written** for that chunk (other chunks still emit).
5. **Spot-check.** Compare a sample slice against [samples/DEMO100__procedure-division__MAIN-PROCESSING__A000-MAIN.json](./samples/DEMO100__procedure-division__MAIN-PROCESSING__A000-MAIN.json) for the bundled fixture ([samples/DEMO100.expected.facts.json](./samples/DEMO100.expected.facts.json) + [samples/DEMO100.chunk-manifest.json](./samples/DEMO100.chunk-manifest.json)). Confirm:
   - `chunk.id` matches the slice filename (after `__` → `/` reversal).
   - Every entry in any filtered collection has `chunk_id` ∈ `{this.id} ∪ descendant_chunk_ids`.
   - `facts_sha256` matches the sha256 of the `facts.json` on disk.
   - `incoming_xref` and `files` are byte-identical to the full-file values.
6. **Report.** The script prints `OK: wrote N slices to <dir>`, total slices written / skipped (validation failure) / pruned, source/manifest/facts sha256 prefixes, and any entries from `errors[]`. Do not echo individual slice contents.

## Batch / Parallel Slicing

When the user asks to slice **more than one file**, do **not** loop the python script inline. Use [scripts/slice_facts_batch.ps1](./scripts/slice_facts_batch.ps1):

```powershell
pwsh -File .github/skills/facts-slicing/scripts/slice_facts_batch.ps1 `
     -Paths repos/sample1/COBOL/*.CBL
```

Parameters (mirrors `cobol-facts-extraction`'s batch runner):
- `-Files`, `-Paths`, `-Manifest <json|csv>` — input selection.
- `-SourceRoot`, `-OutputDir` — per-run overrides.
- `-Prune` — pass `--prune` to every child invocation.
- `-Throttle <int>` — defaults to `[Environment]::ProcessorCount`.
- `-ResultsXml <path>` — defaults to `slice_results.xml`.
- `-ExcludeExtensions <string[]>` — case-insensitive extensions skipped when expanding `-Paths`. Default: `.cob, .inp, .itt` (same rationale as upstream — copybooks and JCL inline-data are not chunked / sliced standalone).

The runner is deterministic (sorted inputs and results, no timestamps), captures per-file stdout/stderr/exit, persists results via `Export-Clixml`, and exits `1` if any child failed.

**Ad-hoc helpers go in `temp/`.** Same convention as `cobol-chunking` / `cobol-facts-extraction`.

Report only the summary line (`DONE total=… ok=… failed=…`) plus any failures, matching the single-file reporting contract in step 6.

## Determinism Rules

- No LLM calls.
- Re-running on an unchanged `facts.json` + `chunk-manifest.json` pair MUST yield byte-identical slice files (stable key order, no timestamps, sorted `siblings` / `descendant_chunk_ids`).
- Filename sanitization is a single rule: `chunk_id.replace("/", "__")`. No other transformations (no lowercasing, no truncation). Chunk ids that exceed the OS path limit fail loudly with `code=CHUNK_ID_TOO_LONG`.
- Stale `manifest_sha256` is a hard error, not a warning — slicing against a manifest that no longer matches the one used by phase B would silently mis-bind `chunk_id` references.
- `--prune` is opt-in. Default behavior is additive (write/overwrite per-chunk files; never delete) so that a partial run does not destroy a known-good directory.

## Resources

- [scripts/slice-facts.py](./scripts/slice-facts.py) — the slicer (entry point).
- [scripts/slice_facts_batch.ps1](./scripts/slice_facts_batch.ps1) — reusable parallel batch runner.
- [schemas/outputs.schema.json](./schemas/outputs.schema.json) — JSON Schema (Draft 2020-12), gate for the writer.
- [samples/DEMO100.expected.facts.json](./samples/DEMO100.expected.facts.json) — input fixture facts (mirrors `cobol-facts-extraction`).
- [samples/DEMO100.chunk-manifest.json](./samples/DEMO100.chunk-manifest.json) — input chunk manifest for the fixture.
- [samples/DEMO100__procedure-division__MAIN-PROCESSING__A000-MAIN.json](./samples/DEMO100__procedure-division__MAIN-PROCESSING__A000-MAIN.json) — expected slice for the `A000-MAIN` paragraph (sha256 fields left as placeholders).
- [prompts/slice-facts.prompt.md](./prompts/slice-facts.prompt.md) — `/slice-facts` slash-command wrapper.

## Pipeline Wiring

`config/pipeline-dag.yaml` phase C lists `skills/facts-slicing/scripts/slice-facts.py` as the prep step for every `section-doc-writer` subagent and declares the output at `docs/_shared/<file>/facts-slices/<chunk_id>.json` — exactly what this skill writes (with `/` → `__` filename sanitization).

## Common Pitfalls

- **Filename collisions.** Two chunks can never collide after `/` → `__` sanitization because chunk ids are unique in the manifest, but a third-party tool that produces non-unique ids will silently overwrite. The schema-level uniqueness check in the manifest (phase A) is the gate; this skill trusts it.
- **Descendant scope.** A `section` slice includes facts for every nested `paragraph` and `exec-sql` / `exec-cics` chunk underneath it — not just facts directly attributed to the section. This is intentional: section-level docs need their paragraphs' edges.
- **`files` and `incoming_xref` are NOT chunk-scoped.** They are always copied in full. Per-chunk filtering would force section-doc-writer subagents to reach back to the full `facts.json`, defeating the slice.
- **Re-running after a partial phase B.** If `cobol-facts-extraction` wrote a new `facts.json` but `chunk-manifest.json` was not regenerated, the slicer's stale-input check fires (`code=4`). Run phase A first, then phase B, then this skill.
- **Missing deps.** The script requires `pyyaml` (always) and `jsonschema` (optional but recommended): `pip install pyyaml jsonschema`.
