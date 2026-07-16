---
description: 'Generate facts.json for one or more mainframe sources (COBOL / JCL / PROC / copybook / BMS) using the cobol-facts-extraction skill. Optional --xref-pass triggers the workspace incoming-xref pass.'
---

# Extract mainframe facts → facts.json

Use the [`cobol-facts-extraction`](../SKILL.md) skill to produce a `facts.json` knowledge graph for each source the user specifies (or, if none specified, every file matched by `config/sources.yaml::include`). Requires the matching `chunk-manifest.json` from phase A; if missing, stop and tell the user to run [`/chunk-cobol`](../../cobol-chunking/prompts/chunk-cobol.prompt.md) first.

For each target file:

1. Default output path is `docs/_shared/<basename-with-ext>/facts.json` — let the script pick it unless the user overrides with `--output`.
2. Default manifest path is `docs/_shared/<basename-with-ext>/chunk-manifest.json` — let the script pick it unless the user overrides with `--manifest`.
3. Run:
   ```powershell
   python .github/skills/cobol-facts-extraction/scripts/extract-facts.py `
     --source <SOURCE> `
     [--source-root <root>] `
     [--manifest <chunk-manifest.json>] `
     [--output <facts.json>]
   ```
4. For batch / parallel runs use [`extract_facts_batch.ps1`](../scripts/extract_facts_batch.ps1) instead of looping — same arguments as the single-file runner plus `-Throttle`, `-Paths`, `-Manifest`, `-ResultsXml`.
5. Report per file: per-collection counts (`paragraphs=N performs=N calls=N copybooks=N exec_sql=N …`), detected source kind, source+manifest sha256 prefixes, output path, and any entries in `errors[]`.
6. After all per-file runs complete and the user wants the workspace incoming-xref populated, run ONCE:
   ```powershell
   pwsh -File .github/skills/cobol-facts-extraction/scripts/extract_facts_batch.ps1 -XrefPass
   ```
7. Do NOT proceed to section docs or diagrams — those are downstream phases (see `config/pipeline-dag.yaml`).
