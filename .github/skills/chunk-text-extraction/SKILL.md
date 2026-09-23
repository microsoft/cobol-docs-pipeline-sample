---
name: chunk-text-extraction
description: 'Deterministically slice a mainframe or IBM i (AS400) source file (COBOL, CBLLE, SQLCBLLE, CL, CLP, CLLE, JCL, PROC, copybook, BMS) into one raw-text file per chunk. USE FOR: extract CL or COBOL chunks as txt and prepare source text for section-doc-writer. DO NOT USE FOR: chunking, facts extraction, facts slicing, copybook expansion, or markdown generation.'
argument-hint: 'Path to a source file (e.g. repos/sample1/COBOL/DEMO100.CBL). Optional --chunk-id <id> for one chunk, --output-dir to override, --manifest to override, --prune to drop stale .txt files, --source-root override.'
---

# Chunk Text Extraction

Deterministic phase-B sibling. Reads a source file + its `chunk-manifest.json` and emits one raw-text file per chunk under `docs/_shared/<basename-with-ext>/chunks/<chunk_id_sanitized>.txt`. No LLM calls — pure byte/line slicing, sha-gated against stale manifests.

The `.txt` files are the **only** raw-source view a downstream per-section subagent (section-doc-writer, qa-reviewer) needs. They sit beside `facts-slices/` so a phase-C agent for chunk `X` reads exactly two files: its slice JSON and its `.txt`.

## When to Use

- The user asks to "extract chunks as txt", "save each chunk to a file", "dump chunk source", or "give me the source for chunk_id X".
- Phase A has just (re-)written a `chunk-manifest.json` and the matching `chunks/` directory is missing or stale (different source `sha256`).
- A single chunk needs to be re-extracted on demand (`--chunk-id <id>`).
- Preparing per-section inputs before launching phase-C subagents.

Do **not** use this skill for chunking ([`cobol-chunking`](../cobol-chunking/SKILL.md)), facts extraction ([`cobol-facts-extraction`](../cobol-facts-extraction/SKILL.md)), per-chunk facts slicing ([`facts-slicing`](../facts-slicing/SKILL.md)), markdown writing (phase C), or copybook *expansion*.

## Output Contract

One UTF-8 text file per chunk at `docs/_shared/<basename-with-ext>/chunks/<chunk_id_sanitized>.txt`.

- `<chunk_id_sanitized>` = `chunk_id.replace("/", "__")` — the default transformation. Same rule as `facts-slicing`.
- **Duplicate-chunk-id disambiguation.** Phase A *should* guarantee unique chunk ids; some real-world manifests violate that (e.g. two `data-division/FILLER` records at different line ranges). On collision, the second+ occurrence is suffixed with `__L<start_line>` (and `_<n>` if even that collides) and a `DUPLICATE_CHUNK_ID` entry is recorded in `errors[]`. The authoritative chunk-id → filename map is always `index.json::chunks[].file` — downstream agents MUST read that, not re-derive the filename from the chunk id.
- Body = the raw source bytes for the inclusive 1-based line range `[chunk.start_line .. chunk.end_line]` from the manifest, decoded with the manifest's `encoding_detected` (default `utf-8`).
- Line endings are normalized to `\n` to keep re-runs byte-identical across OSes; the original column content (including significant trailing spaces inside columns 8–72) is preserved verbatim.
- No header, no chunk-id banner, no line-number gutter. The companion slice JSON already carries `chunk.start_line` / `chunk.end_line`.
- Empty chunks (`start_line == end_line + 1` due to upstream parsing edge cases) produce a zero-byte file and a single `errors[]` entry on stdout, but still write the file.

Alongside the per-chunk files, a single index is emitted at `docs/_shared/<basename-with-ext>/chunks/index.json`:

```jsonc
{
  "index_version":   "1.0",
  "source_path":     "repos/sample1/COBOL/DEMO100.CBL",
  "source_sha256":   "<64-hex>",                    // copied from manifest
  "manifest_sha256": "<64-hex of the chunk-manifest.json bytes>",
  "encoding":        "utf-8",
  "chunks": [
    {
      "id":         "DEMO100/procedure-division/MAIN-PROCESSING/A000-MAIN",
      "file":       "DEMO100__procedure-division__MAIN-PROCESSING__A000-MAIN.txt",
      "start_line": 22,
      "end_line":   26,
      "line_count": 5,
      "byte_count": 187,
      "sha256":     "<64-hex of the emitted .txt bytes>"
    }
    /* one per chunk, sorted by start_line */
  ],
  "errors": []
}
```

`chunks[].sha256` is the integrity gate downstream consumers use to detect a stale `.txt` without re-reading every file.

## Procedure

1. **Resolve inputs.** Locate the source file (same rules as upstream skills: relative to repo root first, then to `source_root` from `config/pipeline.yaml`). Default manifest is at `docs/_shared/<basename-with-ext>/chunk-manifest.json`. Reject if either is missing.
2. **Stale-input check.** Hash the source bytes on disk and compare with `chunk-manifest.json::sha256`. On mismatch: exit code `4`, error on stderr, **no `.txt` written**. Re-run `cobol-chunking` first.
3. **Run the extractor.** Invoke [scripts/extract-chunks.py](./scripts/extract-chunks.py):
   ```powershell
   python .github/skills/chunk-text-extraction/scripts/extract-chunks.py `
     --source repos/sample1/COBOL/DEMO100.CBL
   ```
   Flags:
   - `--chunk-id <id>` — extract ONLY that chunk (must exist in the manifest); default is all chunks.
   - `--output-dir <path>` — override `docs/_shared/<basename-with-ext>/chunks`.
   - `--source-root <root>` — override `pipeline.yaml::source_root`.
   - `--manifest <path>` — override the default chunk-manifest location.
   - `--prune` — delete any pre-existing `.txt` in the output directory whose chunk id is NOT in the current manifest (default: keep stale files and warn).
   - `--no-index` — skip writing `index.json` (useful when extracting a single chunk on demand).
4. **Report.** The script prints `OK: wrote N chunks to <dir>` plus total `.txt` written / skipped / pruned, the source/manifest sha256 prefixes, and any entries from `errors[]`. Do not echo the chunk bodies.

## Batch / Parallel Extraction

When the user asks to extract chunks for **more than one file**, do **not** loop the python script inline. Use [scripts/extract_chunks_batch.ps1](./scripts/extract_chunks_batch.ps1):

```powershell
pwsh -File .github/skills/chunk-text-extraction/scripts/extract_chunks_batch.ps1 `
     -Paths repos/sample1/COBOL/*.CBL
```

Parameters (mirrors `cobol-facts-extraction` / `facts-slicing`):
- `-Files`, `-Paths`, `-Manifest <json|csv>` — input selection.
- `-SourceRoot`, `-OutputDir` — per-run overrides.
- `-Prune` — pass `--prune` to every child invocation.
- `-Throttle <int>` — defaults to `[Environment]::ProcessorCount`.
- `-ResultsXml <path>` — defaults to `chunk_text_results.xml`.
- `-ExcludeExtensions <string[]>` — case-insensitive extensions skipped when expanding `-Paths`. Default: `.cob, .inp, .itt` (copybooks and JCL inline-data are consumed by reference upstream, not chunked standalone).

The runner is deterministic (sorted inputs/results, no timestamps), captures per-file stdout/stderr/exit, persists results via `Export-Clixml`, and exits `1` if any child failed.

**Ad-hoc helpers go in `temp/`.** Same convention as the other phase-B skills.

Report only the summary line (`DONE total=… ok=… failed=…`) plus any failures, matching the single-file reporting contract in step 4.

## Determinism Rules

- No LLM calls.
- Re-running on an unchanged source + manifest pair MUST yield byte-identical `.txt` files AND a byte-identical `index.json` (sorted `chunks[]`, stable key order, no timestamps).
- Line endings always normalized to `\n` in the output — the input may be CRLF, LF, or mixed; the emitted bytes are LF-only.
- Filename sanitization is `chunk_id.replace("/", "__")` by default. The only non-deterministic-looking case is duplicate chunk ids (a phase-A bug), where the second+ occurrence gets a `__L<start_line>` suffix — still deterministic given the same manifest. Chunk ids that exceed the OS path limit fail loudly with `code=CHUNK_ID_TOO_LONG`.
- Stale `source sha256` (manifest vs. on-disk source) is a hard error, not a warning. Extracting against a manifest whose line numbers no longer match the source would silently mis-bind every chunk.
- `--prune` is opt-in. Default behavior is additive (write/overwrite per-chunk files; never delete) so a partial run does not destroy a known-good directory.

## Resources

- [scripts/extract-chunks.py](./scripts/extract-chunks.py) — the extractor (entry point).
- [scripts/extract_chunks_batch.ps1](./scripts/extract_chunks_batch.ps1) — parallel batch runner.

## Pipeline Wiring

`config/pipeline-dag.yaml` phase B lists `skills/chunk-text-extraction/scripts/extract-chunks.py` as a sibling of `cobol-facts-extraction`'s `extract-facts.py`. Both run per source after phase A, both consume the same `chunk-manifest.json`, and neither depends on the other — they can be parallelized freely. Outputs land at `docs/_shared/<file>/chunks/<chunk_id>.txt` (with `/` → `__` filename sanitization).

## Common Pitfalls

- **Stale manifest.** If the source was edited after `cobol-chunking` ran, the line numbers in the manifest no longer point at the right ranges. Step 2 catches this. Always re-run phase A first.
- **Encoding mismatch.** If the manifest claims `utf-8` but the source is actually EBCDIC or CP1252, the extractor will still write bytes — they just may not be human-readable. Trust the manifest's `encoding_detected` and fix it in phase A if wrong.
- **CRLF on Windows checkouts.** The extractor reads via universal-newline mode and writes LF, so the output is stable regardless of git's `core.autocrlf` setting. Do not introduce a `--preserve-eol` flag unless a downstream agent explicitly needs it.
- **Filename collisions.** Phase A is *supposed* to guarantee unique chunk ids, but some legacy manifests have duplicates. This skill disambiguates by suffixing `__L<start_line>` and emits a `DUPLICATE_CHUNK_ID` error entry. Always look up filenames via `index.json::chunks[].file`, never by re-sanitizing the chunk id, or you will mis-bind to the wrong .txt for duplicated ids.
- **`--chunk-id` without `--no-index`.** Extracting one chunk without `--no-index` will overwrite `index.json` with a single-entry file. Pass `--no-index` for surgical single-chunk re-extraction.
