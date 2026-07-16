---
name: qa-reviewer
description: 'Review a phase-C section markdown for ONE chunk against the binding authoring rules from `config/templates/*.template.md` and the active `profile.yaml`. Runs deterministic mechanical checks (forbidden tokens, minimum sentence/word counts, citation footnote presence, identifier styling, no line-count prose, no `[FILE:Lx-Ly]` inline tags) and emits a `findings[]` JSON sidecar at `docs/_reviews/section-doc/<file>__<chunk_id>__<lang>.json`. USE FOR: review section doc, check section markdown, qa pass on phase-C output, validate citations, validate identifier styling, lint forbidden tokens in Summary / Purpose, audit forbidden openers, verify diagram presence, gate before phase-D rendering. DO NOT USE FOR: chunking (phase A — use cobol-chunking), facts extraction (phase B — use cobol-facts-extraction), per-chunk text/facts prep (use chunk-text-extraction / facts-slicing), authoring the section markdown itself (use section-doc-writer), file-level / diagram-renderer reviews (different scope in pipeline-dag.yaml phase C).'
argument-hint: 'Mechanical checker (`check-section-doc.py`): --bundle <docs/_shared/<file>/_bundles/<chunk_id>.bundle.json> [--language en]. LLM semantic review: read the rendered `.bundle.md` sibling instead. The markdown path is read from bundle output_paths.<language>. Optional --section-doc to override, --profile, --json-out.'
---

# QA Reviewer (per-section, phase C)

Deterministic + LLM-assisted gate that fires immediately after [`section-doc-writer`](../section-doc-writer/SKILL.md) writes a per-section markdown. This skill owns the **mechanical** half — a Python checker that enforces the binding authoring rules from the templates and profile. The semantic prose review (does the Purpose paragraph actually describe the business intent? do the citations point at the right lines?) is the LLM `qa-reviewer` agent's job and consumes the same `findings[]` sidecar as its starting point.

## When to Use

- Immediately after every `section-doc-writer` per-section invocation (the pipeline-DAG order).
- Re-validating an existing `docs/<lang>/<file>/sections/*.md` after manual edits.
- Pre-commit / CI gate before phase-D diagram rendering or phase-N portal build.
- The user asks to "review", "lint", "qa-check", "audit citations" on a section doc.

Do **not** use this skill for:
- chunking ([`cobol-chunking`](../cobol-chunking/SKILL.md)),
- facts extraction ([`cobol-facts-extraction`](../cobol-facts-extraction/SKILL.md)),
- per-chunk text / facts prep ([`chunk-text-extraction`](../chunk-text-extraction/SKILL.md), [`facts-slicing`](../facts-slicing/SKILL.md)),
- writing the section markdown ([`section-doc-writer`](../section-doc-writer/SKILL.md)),
- per-file `index.md` / `complete.md` review or diagram-renderer review — those are different `qa-reviewer` scopes in `pipeline-dag.yaml` phase C.

## Output Contract

For section markdown `docs/<lang>/<basename-with-ext>/sections/<chunk_id_sanitized>.md` reviewed at language `<lang>`:

```
docs/_reviews/section-doc/<basename-with-ext>__<chunk_id_sanitized>__<lang>.json
```

Shape:

```jsonc
{
  "review_version":    "1.0",
  "section_doc":       "docs/en/DEMO100.CBL/sections/…__B200-EX.md",
  "section_doc_sha":   "<64-hex>",                  // hash of reviewed bytes
  "source_path":       "repos/sample1/COBOL/DEMO100.CBL",
  "chunk_id":          "DEMO100/procedure-division/B200-CONTROLLO-PARAMETRO/B200-EX",
  "language":          "en",
  "profile_path":      "config/templates/docs/functional-analysis/default/profile.yaml",
  "thresholds": {
    "min_total_words":              1500,
    "min_purpose_sentences":        4,
    "min_purpose_words":            80,
    "max_tldr_words":               30,
    "identifier_lock_regex":        "[A-Z][A-Z0-9-]*(\\.[A-Z0-9-]+)?",
    "require_citations":            true
  },
  "ok": false,
  "findings": [
    {
      "code":     "TLDR_FORBIDDEN_TOKEN",
      "severity": "error",
      "section":  "Summary",
      "line":     12,
      "message":  "Summary contains forbidden COBOL jargon: 'PERFORM'."
    }
    /* zero or more; sorted (severity desc, line asc) */
  ],
  "counters": {
    "total_words":         842,
    "tldr_words":          22,
    "purpose_sentences":   5,
    "purpose_words":       112,
    "src_footnotes":       7,
    "inline_file_tags":    0
  }
}
```

Exit codes mirror the verdict:
- `0` — `ok=true`, zero `severity=error` findings.
- `1` — at least one `severity=error` finding (review file still written).
- `4` — required input missing (markdown not found or bundle unavailable).
- `5` — stale bundle (`bundle.chunk_text_sha` mismatch vs. on-disk chunk text).

`severity` is one of `error` (blocks pipeline), `warn` (logged, non-blocking), `info` (advisory).

## Mechanical Findings (enforced by the checker)

| Code                                | What triggers it                                                                                                            | Severity |
|-------------------------------------|-----------------------------------------------------------------------------------------------------------------------------|----------|
| `TLDR_MISSING`                      | No `## Summary` block (or legacy `## TL;DR`), or block has zero non-whitespace content.                                       | error    |
| `TLDR_TOO_LONG`                     | Summary exceeds `thresholds.max_tldr_words` (default 30).                                                                   | error    |
| `TLDR_MULTI_SENTENCE`               | Summary contains more than one sentence (split on `.`, `!`, `?`).                                                           | error    |
| `TLDR_FORBIDDEN_TOKEN`              | Summary contains any of: `PERFORM`, `EVALUATE`, `WORKING-STORAGE`, `GO TO`, `DECLARATIVES`, or a line/verb count phrase.    | error    |
| `PURPOSE_MISSING`                   | No `## Purpose` block.                                                                                                       | error    |
| `PURPOSE_TOO_SHORT_SENTENCES`       | Purpose has fewer than `min_purpose_sentences` (default 4) sentences.                                                       | error    |
| `PURPOSE_TOO_SHORT_WORDS`           | Purpose has fewer than `min_purpose_words` (default 80) words.                                                              | error    |
| `PURPOSE_FORBIDDEN_OPENER`          | Purpose starts with one of: `"This section contains the following…"`, `"The section spans lines"`, `"This PROCEDURE DIVISION section implements the following logic…"`, or equivalent transcript-style preface. | error    |
| `PURPOSE_LINE_COUNT_PROSE`          | Purpose mentions a line count, line range, or verb count (`PERFORM`, `CALL`, `GO TO` counts).                               | error    |
| `INLINE_FILE_TAG`                   | Any occurrence of `[FILE:Lx-Ly]` style citation in body (must use `[^src-N]` footnotes).                                    | error    |
| `MISSING_SOURCES_BLOCK`             | `require_citations=true` and document has no `## Sources` heading.                                                          | error    |
| `MISSING_SRC_FOOTNOTES`             | `require_citations=true` and document has zero `[^src-N]` footnote references.                                              | error    |
| `IDENTIFIER_NOT_BACKTICKED`         | A token matching `identifier_lock_regex` appears in prose but is not wrapped in backticks.                                  | warn     |
| `BANNED_BANNER`                     | The reviewed doc contains the forbidden "Self-contained document. Bundles… from facts.json…" banner.                       | error    |
| `MIN_TOTAL_WORDS`                   | Total word count below `thresholds.min_total_words` (default 1500). At per-section scope this is `warn` (the threshold is a per-document aggregate); at per-file scope it is `error`. | warn |
| `MISSING_DIAGRAM`                   | Companion `docs/_shared/<file>/diagrams/section-<chunk_id>.mmd` is missing.                                                 | warn     |
| `COPYBOOK_INCLUSION_SIDECAR_DRIFT`  | Copybook chunk: inline ` ```mermaid ` block under `## Inclusion sites → Inclusion graph` is not byte-identical to `bundle.output_paths.diagram`. Sidecar must equal the inline source per `copybook.template.md` "DIAGRAM OWNERSHIP". | error |
| `COPYBOOK_INCLUSION_SIDECAR_UNEXPECTED` | Copybook chunk: sidecar `.mmd` exists but the inclusion-graph gate is not met (< 2 includers in `incoming_xref[via=copy]` AND no `REPLACING` divergence). Sidecar must be pruned. | warn |
| `COPYBOOK_STRUCTURE_IN_SIDECAR`     | Copybook chunk: sidecar `.mmd` begins with `classDiagram`, `erDiagram`, or otherwise matches the structure-diagram contract instead of `flowchart LR`. The structure diagram is NEVER written to the sidecar (owned by `diagram-renderer`'s `er-fragment.mmd`). | error |

All checks are pure regex / counting — no LLM call. The LLM `qa-reviewer` agent reads this JSON and produces additional `severity` entries with codes prefixed `SEMANTIC_…` (e.g. `SEMANTIC_PURPOSE_OFF_TOPIC`).

## Procedure

1. **Resolve inputs.** Either pass the markdown path directly, or pass `--bundle <path>` (preferred) and read the markdown path from `bundle.output_paths`. Two sibling artifacts:
   - `docs/_shared/<basename-with-ext>/_bundles/<chunk_id_sanitized>.bundle.json` — **authoritative**; consumed by the mechanical checker `check-section-doc.py` (needs structured access to `chunk_text_sha`, `facts_slice`, `output_paths`, `profile`).
   - `docs/_shared/<basename-with-ext>/_bundles/<chunk_id_sanitized>.bundle.md` — **LLM input**; deterministic Markdown projection used by the LLM semantic review pass for intent alignment. Never pass this to `--bundle`.
2. **Stale-input check.** Compare `bundle.chunk_text_sha` with a re-hash of the on-disk chunk text in the bundle. Mismatch → exit `5`, re-run the bundle prep step.
3. **Run the checker.** Invoke [scripts/check-section-doc.py](./scripts/check-section-doc.py):
   ```powershell
   python .github/skills/qa-reviewer/scripts/check-section-doc.py `
     --bundle docs/_shared/DEMO100.CBL/_bundles/DEMO100__procedure-division__B200-CONTROLLO-PARAMETRO__B200-EX.bundle.json `
     --language en
   ```
   Flags (preferred → legacy):
   - `--bundle <path>` — **preferred.** Read `source_path`, `chunk`, `chunk_text`, `chunk_text_sha`, `profile`, and `output_paths.<language>` from the bundle. Markdown path = `bundle.output_paths.<language>`.
   - `--language <en|it|…>` — language key into `bundle.output_paths`; default `en`.
   - `--section-doc <path>` — override the bundle's resolved markdown path (rarely needed; skips the staleness check).
   - `--source <path> --chunk-id <id> --language <en|it|…>` — *legacy* derivation path retained for ad-hoc runs without a bundle; does NOT perform the `chunk_text_sha` staleness check.
   - `--profile <path>` — override profile.yaml (default `config/templates/docs/functional-analysis/default/profile.yaml`).
   - `--json-out <path>` — override review sidecar path (default `docs/_reviews/section-doc/<file>__<chunk_id>__<lang>.json`).
   - `--no-write` — print review JSON to stdout, do not persist the sidecar.
4. **Report.** Print one summary line: `OK  …` or `FAIL: N error(s), M warn(s)  →  <sidecar path>`. On failure, print one line per `error` finding (`[CODE] line=…  <message>`).

## Determinism Rules

- Mechanical checks are 100% deterministic: byte-identical inputs → byte-identical sidecar.
- The sidecar JSON sorts `findings[]` by `(severity desc, line asc, code asc)` and uses stable key order so re-runs are diff-clean.
- The semantic LLM review run is **separate** from this skill and produces a sibling sidecar (or appends to the same JSON under a distinct `semantic_findings[]` key). Do not mix the two in the same write — the LLM half is non-deterministic and should be re-runnable independently.
- Profile thresholds are read once at the top of the run and copied verbatim into `thresholds` so the sidecar is self-describing without re-loading the profile.

## Resources

- [scripts/check-section-doc.py](./scripts/check-section-doc.py) — deterministic mechanical checker (entry point).

## Pipeline Wiring

`config/pipeline-dag.yaml` phase C lists `qa-reviewer` immediately after every per-section `section-doc-writer` step, with the per-chunk bundle JSON as the primary input alongside the section markdown and `.mmd`. This skill formalizes the deterministic mechanical-checker half of that step; the LLM semantic-review half is owned by `.github/agents/section-reviewer.agent.md` and is invoked by `.github/agents/section-agent.agent.md` after the mechanical checker passes.

## Common Pitfalls

- **Running QA before authoring.** The checker fails with `4` if the markdown does not exist — that is a `section-doc-writer` ordering bug, not a reviewer bug.
- **Stale profile.** Editing `profile.yaml` changes thresholds for every subsequent review. The sidecar copies the thresholds inline so old reviews keep their original verdict context, but new reviews will diverge — re-run the full phase-C QA after a profile bump.
- **`identifier_lock_regex` false positives.** The regex matches any `[A-Z][A-Z0-9-]*` token, including common English acronyms (`SQL`, `CICS`, `DB2`). The checker uses `warn` severity (not `error`) for `IDENTIFIER_NOT_BACKTICKED` for exactly this reason — escalate to `error` only at the per-file finalizer.
- **Missing diagram.** A missing per-section `.mmd` is `warn` here because the diagram renderer phase may not have run yet. The per-file `qa-reviewer` finalizer escalates it to `error`.
