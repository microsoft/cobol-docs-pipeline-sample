---
name: section-doc-finalizer
description: 'Author phase-C FILE-LEVEL `index.md` and `complete.md` for ONE mainframe or IBM i (AS400) source from its per-section markdown set. LLM-driven. USE FOR: write IBM i or mainframe index.md, complete.md, file overview, program TOC, and phase-C per-file finalization. DO NOT USE FOR: per-section authoring, file-level diagrams, QA review, or portal build.'
argument-hint: 'Source file path + optional --languages en,it. Writes docs/<lang>/<file>/index.md and docs/<lang>/<file>/complete.md per language. Default --languages en.'
---

# Section Doc Finalizer (per-file, phase C)

LLM-driven phase-C authoring skill. For ONE source file, produces the file-level `index.md` (navigable TOC + executive summary) and `complete.md` (single-file concatenation of every section) per requested language. EN is the source-of-truth; non-EN siblings are co-authored in the same LLM call.

This is the **per-file finalizer scope** of the section-doc-writer family. The per-section [`section-doc-writer`](../section-doc-writer/SKILL.md) skill explicitly **forbids** authoring `index.md` / `complete.md`; that scope lives here.

## When to Use

- Every per-section `.md` for the file has been authored and passed [`qa-reviewer`](../qa-reviewer/SKILL.md).
- The user asks to "build the index", "produce complete.md", "finalize the program docs", "co-author IT index.md + complete.md", "write the landing page for DEMO100".

Do **not** use this skill for:
- Per-section markdown (`docs/<lang>/<file>/sections/*.md`) — owned by [`section-doc-writer`](../section-doc-writer/SKILL.md) per-section.
- File-level overview `.mmd` diagrams — owned by [`diagram-renderer`](../diagram-renderer/SKILL.md).
- Per-file QA review — owned by [`qa-reviewer`](../qa-reviewer/SKILL.md) per-file scope.
- Portal aggregation across files — owned by phase N.

## Output Contract

For file `<basename-with-ext>` and each language `<lang>` in `--languages`:

```
docs/<lang>/<basename-with-ext>/index.md
docs/<lang>/<basename-with-ext>/complete.md
```

`index.md` MUST:
- Open with `# <program_id or basename> — Functional Overview`.
- Provide a `## Summary` (1–2 short paragraphs) and a `## Executive Summary` (3–6 paragraphs).
- Provide a `## Sections` block listing every per-section file, grouped by division/section, with markdown links: `[A000-MAIN](sections/<sanitized>.md)`.
- Provide a `## Call relationships` block with two evidence-backed tables:
  - `### Calls inside this program` from `facts_toc.internal_calls` (`PERFORM`
    and `GO TO` edges).
  - `### Calls between programs` from `facts_toc.inter_program_calls`
    (outbound and inbound COBOL, CICS, CL, and JCL execution edges).
- Follow each non-empty table with an inline Mermaid `flowchart LR` generated
  from exactly the same normalized rows, so Markdown and portal consumers can
  see the graph without opening a separate artifact.
- Show an explicit empty-state table row when either call collection is empty.
- Embed the file-level overview diagrams as relative links to the `.mmd` files under `docs/_shared/<file>/diagrams/`.
- Carry a `## Sources` block with `[^src-N]` footnotes pointing back to source line ranges (same citation style as per-section docs).

`complete.md` MUST:
- Be a deterministic concatenation of `index.md` followed by every `sections/*.md` in chunk-manifest order.
- Inject a single `# Sections` H1 separator between the index body and the section bodies.
- Re-base every per-section heading **down by one level** (H1 → H2, H2 → H3, …) so the document has exactly one top-level title.
- Preserve the original `[^src-N]` footnote ids by namespacing them per section (e.g. `[^A000-MAIN-src-1]`) to avoid collisions.
- Append a deterministic **`# Record types (TRK)`** catalog when the source emits SISBA tracciato records. A TRK record is a level-01 `facts.json` `data_records` entry named `REC-<3-digit code>-<file>` whose `<file>` suffix is a declared output file (this excludes working-storage flags such as `REC-103-CES-FLAG`). The catalog groups records by output file and links each to the embedded section anchor carrying its byte-level layout. This is the single point at which the tracciato catalog enters the pipeline so the phase-L technical-analysis writer — which reads `complete.md` only, never `functional-analysis.md` — can author its `trk-gestiti` section instead of stamping the not-applicable marker. The catalog is built by [scripts/assemble-complete.py](./scripts/assemble-complete.py), not the LLM.

A companion JSON sidecar is emitted **only on EN** at `docs/_reviews/section-doc/<file>__index__inputs.json` capturing the bundle the LLM received (sections list, manifest hash, languages).

## Procedure

1. **Resolve inputs.** Required artifacts under `docs/_shared/<basename-with-ext>/`:
   - `chunk-manifest.json` — section ordering and division/section grouping.
   - `facts.json` — `program_id`, top-level paragraph/section list, `incoming_xref` summary for the executive summary.
   And under `docs/<lang>/<basename-with-ext>/sections/`:
   - At least one `*.md` per requested language.
   On any miss: exit `4` and tell the user to re-run the per-section step.
2. **Stale-input check.** Compare `chunk-manifest.json::sha256` with the on-disk source sha. If they differ, re-run phase A first.
3. **Assemble the prompt bundle.** Invoke [scripts/assemble-inputs.py](./scripts/assemble-inputs.py) — pure-deterministic packager. It loads the manifest, the facts TOC fields, and every per-section MD path + first-paragraph summary, and prints (or writes via `--out`) a single JSON object the LLM consumes:
   ```powershell
   python .github/skills/section-doc-finalizer/scripts/assemble-inputs.py `
     --source repos/sample1/COBOL/DEMO100.CBL `
     --languages en,it `
     --out  prompt-bundle.json
   ```
   Flags:
   - `--source <path>` (required).
   - `--languages <comma-list>` — default `en`. EN is always first.
   - `--out <path>` — write to file (default: stdout).
   - `--profile <path>` — override profile.yaml.
4. **Author.** The `section-doc-finalizer` agent reads the bundle and writes `index.md` + `complete.md` per language.
5. **Validate mechanically.** Invoke [`qa-reviewer`](../qa-reviewer/SKILL.md) per-file scope on the produced documents.

## Bundle Schema

```jsonc
{
  "bundle_version":  "1.0",
  "source_path":     "repos/sample1/COBOL/DEMO100.CBL",
  "source_kind":     "cobol|cl|jcl|proc|copybook|bms",
  "program_id":      "DEMO100",
  "manifest_sha":    "<64-hex>",
  "languages":       ["en", "it"],
  "toc": [
    {
      "chunk_id":   "DEMO100/procedure-division/MAIN-PROCESSING",
      "kind":       "section",
      "name":       "MAIN-PROCESSING",
      "parent_id":  null,
      "start_line": 1547,
      "end_line":   1908,
      "section_md": {
        "en": "docs/en/DEMO100.CBL/sections/DEMO100__procedure-division__MAIN-PROCESSING.md",
        "it": "docs/it/DEMO100.CBL/sections/DEMO100__procedure-division__MAIN-PROCESSING.md"
      },
      "summary_en": "First non-empty paragraph or Summary of the EN section MD (deterministic excerpt)."
    }
    /* one entry per chunk-manifest chunk, in manifest order */
  ],
  "facts_toc": {
    "paragraphs":   [/* facts.json top-level paragraphs list */],
    "incoming_xref":[/* facts.json incoming xref summary */],
    "calls":        [/* facts.json outbound calls */],
    "internal_calls":[/* normalized PERFORM and GO TO rows */],
    "inter_program_calls":[/* normalized outbound and inbound program rows */]
  },
  "diagrams_present": [
    "docs/_shared/DEMO100.CBL/diagrams/call-graph.mmd",
    "docs/_shared/DEMO100.CBL/diagrams/inter-program-call-graph.mmd",
    "docs/_shared/DEMO100.CBL/diagrams/control-flow.mmd"
  ],
  "output_paths": {
    "en":       { "index": "docs/en/DEMO100.CBL/index.md",
                  "complete": "docs/en/DEMO100.CBL/complete.md" },
    "it":       { "index": "docs/it/DEMO100.CBL/index.md",
                  "complete": "docs/it/DEMO100.CBL/complete.md" }
  },
  "profile":     { /* loaded profile.yaml */ }
}
```

`summary_en` is a deterministic excerpt: the first non-heading, non-blank paragraph after the `## Summary` (or legacy `## TL;DR`) block of the EN section MD, truncated to 320 characters with a trailing ellipsis on overflow.

## Determinism Rules

- Bundle packager is fully deterministic: toc iteration follows manifest order, language list is sorted with EN first, sha256 over canonical-JSON of the toc subset.
- LLM authoring is non-deterministic; the **shape** (headings, ordering, Sources block, complete.md heading shift, footnote namespacing) is fixed.
- Forbidden re-derivations:
  - Never re-sanitize chunk ids; always look up `chunks/index.json::chunks[].file`.
  - Never re-author per-section MDs from this skill.
  - Never load the full `facts.json` into the LLM bundle — only the `facts_toc` subset.

## Resources

- [scripts/assemble-inputs.py](./scripts/assemble-inputs.py) — deterministic prompt-bundle packager.

## Common Pitfalls

- **Authoring per-section content here.** This skill assembles + summarizes; it does NOT replace `section-doc-writer`. If a section MD is missing, fix it upstream first.
- **Footnote collisions in complete.md.** Per-section footnote ids overlap by design (`[^src-1]` appears in every section). The complete.md MUST namespace them by section to keep Pandoc happy.
- **Heading-level drift.** Forgetting to shift every per-section heading down by one in `complete.md` produces multiple H1s and breaks the portal TOC.
