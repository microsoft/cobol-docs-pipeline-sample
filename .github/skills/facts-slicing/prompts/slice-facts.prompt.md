---
description: 'Fan a per-file facts.json into per-chunk slice files using the facts-slicing skill. Outputs land at docs/_shared/<file>/facts-slices/<chunk_id_sanitized>.json.'
---

# Slice facts.json → per-chunk facts-slices/

Use the [`facts-slicing`](../SKILL.md) skill to fan each source's `facts.json` into per-chunk slices. Requires the matching `chunk-manifest.json` (phase A) and `facts.json` (phase B). If either is missing or stale, stop and tell the user to run [`/chunk-cobol`](../../cobol-chunking/prompts/chunk-cobol.prompt.md) and/or [`/extract-facts`](../../cobol-facts-extraction/prompts/extract-facts.prompt.md) first.

For each target file:

1. Default output directory is `docs/_shared/<basename-with-ext>/facts-slices/` — let the script pick it unless the user overrides with `--output-dir`.
2. Filename convention is `<chunk_id>.json` with `/` replaced by `__`.
3. Run:
   ```powershell
   python .github/skills/facts-slicing/scripts/slice-facts.py `
     --source <SOURCE> `
     [--source-root <root>] `
     [--facts <facts.json>] `
     [--manifest <chunk-manifest.json>] `
     [--output-dir <facts-slices>] `
     [--chunk-id <ID>] `
     [--prune]
   ```
4. For batch / parallel runs use [`slice_facts_batch.ps1`](../scripts/slice_facts_batch.ps1) — same arguments as the single-file runner plus `-Throttle`, `-Paths`, `-Manifest`, `-Prune`, `-ResultsXml`.
5. Report per file: slices written, slices skipped (schema/path failure), slices pruned, source/manifest/facts sha256 prefixes, output directory, and any entries in `errors[]`.
6. Do NOT proceed to section docs or diagrams — those are downstream phase C agents (see `config/pipeline-dag.yaml`).
