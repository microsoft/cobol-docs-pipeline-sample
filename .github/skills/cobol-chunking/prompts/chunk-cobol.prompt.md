---
description: 'Generate chunk-manifest.json for one or more mainframe sources (COBOL / JCL / PROC / copybook / BMS) using the cobol-chunking skill.'
---

# Chunk mainframe source → chunk-manifest.json

Use the [`cobol-chunking`](../SKILL.md) skill to produce a `chunk-manifest.json` for each source the user specifies (or, if none specified, every file matched by `config/pipeline.yaml::include`).

For each target file:

1. Default output path is `docs/_shared/<basename-with-ext>/chunk-manifest.json` — let the script pick it unless the user overrides with `--output`.
2. Source kind is auto-detected. Override with `--kind-hint cobol|cl|jcl|copybook|bms|proc` only when needed.
3. Run:
   ```powershell
   python .github/skills/cobol-chunking/scripts/chunk.py `
     --source <SOURCE> `
     [--source-root <root>] `
     [--output <out>] `
     [--kind-hint auto]
   ```
   Path resolution: `--source` is tried first relative to repo root, then relative to `source_root` from `config/pipeline.yaml`.
4. Report per file: total chunk count, breakdown by kind, detected encoding, sha256 prefix, output path, and any entries in `errors[]`.
5. Do NOT proceed to facts extraction or doc generation — those are downstream phases (see `config/pipeline-dag.yaml`).
