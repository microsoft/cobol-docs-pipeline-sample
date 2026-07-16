---
name: diagram-renderer
description: 'Author FILE-LEVEL Mermaid overviews for ONE mainframe or IBM i (AS400) source from `facts.json`. Emits call graph, COBOL control flow, IBM i CL command flow, JCL steps, CICS calls, SQL cursor lifecycle, and ER fragments when facts exist. USE FOR: IBM i CL/COBOL or mainframe diagrams. DO NOT USE FOR: per-section diagrams, SVG rendering, or index/complete authoring.'
argument-hint: 'Source file path. Writes one .mmd per non-empty facts collection under docs/_shared/<file>/diagrams/.'
---

# Diagram Renderer (per-file, phase C)

LLM-driven phase-C authoring skill. Produces FILE-LEVEL overview `.mmd` Mermaid sources, one per non-empty collection in `docs/_shared/<basename-with-ext>/facts.json`. The skill **packages** the inputs deterministically and **defines** the kind-to-syntax mapping; the LLM call that fills the templates is invoked by the `diagram-renderer` agent.

## When to Use

- The user asks to "render the overview diagrams", "generate the call graph", "draw the JCL step flow", "author cics-calls.mmd", "produce the ER fragment for DEMO100".
- Phase B has completed: `docs/_shared/<file>/facts.json` exists and its `manifest_sha256` matches the current chunk-manifest.

Do **not** use this skill for:
- Per-section `.mmd` files — those are produced by [`section-doc-writer`](../section-doc-writer/SKILL.md) at per-section scope.
- `.svg` rendering — owned by phase D.
- File-level prose (`index.md` / `complete.md`) — use [`section-doc-finalizer`](../section-doc-finalizer/SKILL.md).

## Output Contract

For file `<basename-with-ext>` and each non-empty source collection, emit:

| Collection (in facts.json)   | Output file                                                  | Mermaid kind        |
|------------------------------|--------------------------------------------------------------|---------------------|
| `performs`                   | `docs/_shared/<file>/diagrams/call-graph.mmd`                | `flowchart LR`      |
| `calls` + `incoming_xref`   | `docs/_shared/<file>/diagrams/inter-program-call-graph.mmd`  | `flowchart LR`      |
| `go_tos`                     | `docs/_shared/<file>/diagrams/control-flow.mmd`              | `flowchart TD`      |
| `jcl_steps`                  | `docs/_shared/<file>/diagrams/jcl-steps.mmd`                 | `flowchart TD`      |
| `cl_commands`                | `docs/_shared/<file>/diagrams/cl-command-flow.mmd`           | `flowchart TD`      |
| `exec_cics`                  | `docs/_shared/<file>/diagrams/cics-calls.mmd`                | `sequenceDiagram`   |
| `exec_sql` (cursor stanzas)  | `docs/_shared/<file>/diagrams/cursor-lifecycle.mmd`          | `stateDiagram-v2`   |
| `data_records`               | `docs/_shared/<file>/diagrams/er-fragment.mmd`               | `erDiagram`         |

Empty collections produce NO file. Stale `.mmd` files for collections that emptied between runs are deleted when `--prune` is passed.

Each `.mmd` MUST:
- Begin with a Mermaid `%% generated-from: <facts_sha8> %%` comment so consumers can detect drift.
- Use identifiers that match `profile.yaml::identifier_lock_regex` (default `[A-Z][A-Z0-9-]*(\.[A-Z0-9-]+)?`).
- Reference only chunks/identifiers present in `facts.json` — no invented nodes.
- Render `inter-program-call-graph` from the bundle's derived
  `inter_program_calls` collection. Each edge label is its call kind; inbound
  and outbound directions must be preserved. Exclude copybook edges.

## Procedure

1. **Resolve inputs.** Required artifact (under `docs/_shared/<basename-with-ext>/`):
   - `facts.json` (whole file — this is the per-file step, slicing does not apply).
   On any miss: exit `4` and tell the user to re-run phase B.
2. **Stale-input check.** Re-compute `sha256(facts.json bytes)` and compare to the value embedded in any existing `.mmd` header. On mismatch, re-author (or delete with `--prune`).
3. **Assemble the prompt bundle.** Invoke [scripts/assemble-inputs.py](./scripts/assemble-inputs.py) — pure-deterministic packager. It loads `facts.json`, derives the non-empty collection set, and prints (or writes via `--out`) a single JSON object the LLM consumes:
   ```powershell
   python .github/skills/diagram-renderer/scripts/assemble-inputs.py `
     --source repos/sample1/COBOL/DEMO100.CBL `
     --out  prompt-bundle.json
   ```
   Flags:
   - `--source <path>` (required).
   - `--out <path>` — write to file (default: stdout).
   - `--profile <path>` — override profile.yaml.
4. **Author.** The `diagram-renderer` agent reads the bundle and writes one `.mmd` per non-empty collection.
5. **Validate mechanically.** Invoke [`qa-reviewer`](../qa-reviewer/SKILL.md) `--kind diagrams` on the produced `.mmd` set.

## Bundle Schema

```jsonc
{
  "bundle_version":   "1.0",
  "source_path":      "repos/sample1/COBOL/DEMO100.CBL",
  "source_kind":      "cobol|cl|jcl|proc|copybook|bms",
  "program_id":       "DEMO100",
  "facts_sha":        "<64-hex>",
  "manifest_sha":     "<64-hex>",
  "diagrams": [
    {
      "kind":        "call-graph",
      "mermaid":     "flowchart LR",
      "output_path": "docs/_shared/DEMO100.CBL/diagrams/call-graph.mmd",
      "facts_subset": { "performs": [ /* … */ ], "paragraphs": [ /* … */ ] }
    },
    /* one entry per non-empty collection, in stable order */
  ],
  "profile":          { /* loaded profile.yaml */ }
}
```

## Determinism Rules

- Bundle packager is fully deterministic: stable iteration order, sha256 over canonical-JSON of every `facts_subset`.
- LLM authoring is non-deterministic but the **shape** is fixed: same kind → same Mermaid header, same identifier styling.
- Pruning is opt-in via `--prune` to avoid silently deleting hand-edited `.mmd` files.

## Resources

- [scripts/assemble-inputs.py](./scripts/assemble-inputs.py) — deterministic prompt-bundle packager.

## Common Pitfalls

- **Authoring per-section `.mmd` here.** Those belong to `section-doc-writer` per-section scope; mixing breaks the per-section/per-file boundary the DAG enforces.
- **Re-deriving collections.** Always use `facts.json` collections as-is; do not re-parse the COBOL/JCL source.
- **Invented nodes.** Every Mermaid node MUST trace back to an identifier present in the corresponding `facts.json` collection.
