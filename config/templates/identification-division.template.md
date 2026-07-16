# {{SECTION_NUMBER}}. {{SECTION_NAME}}

> **Source file:** `{{SOURCE_PATH}}` · **Chunk kind:** {{CHUNK_KIND}} · **Parent:** {{PARENT_NAME}} · **Reachability:** {{REACHABILITY}}

<!-- Provenance (line range, PERFORM/CALL/GO TO counts) is recorded in facts.json and
     in the source citation footnotes; do NOT surface it as a header banner or as
     narrative filler. The reader needs to understand WHAT the section does and WHY,
     not how many lines or branches it contains. See
     .github/instructions/no-generator-boilerplate.instructions.md — the
     "Self-contained document. Bundles… from facts.json…" banner that used to live
     here is FORBIDDEN and must NEVER be re-introduced. -->

## Summary
{{TLDR_ONE_LINER}}

> Authoring rules (binding):
> - Exactly **one sentence**, ≤ 30 words, written in business-domain language.
> - Must answer: _"What does this section accomplish for the wider process?"_
> - **FORBIDDEN:** COBOL jargon (`PERFORM`, `EVALUATE`, `WORKING-STORAGE`), line
>   counts, verb counts, or restating the section name. No citations here — the
>   Summary is a hook, not a claim; full evidence lives in the sections below.

## Purpose
{{PURPOSE_PARAGRAPH}}

> Authoring rules (binding):
> - At least 4 full sentences (≈ 80–120 words) focused on **what the section is about**
>   — i.e. which business or technical concern it addresses — not on what a COBOL
>   division/section/paragraph **is** in the abstract.
> - **FORBIDDEN OPENERS:** "The `IDENTIFICATION DIVISION` is one of the four canonical
>   COBOL divisions…", "The PROCEDURE DIVISION is the part of a COBOL program that…",
>   or any equivalent textbook-style definition. Always pivot to the concrete content:
>   _"In the `IDENTIFICATION DIVISION` we find the program identifier, the author tag
>   and the release banner used by the change-management procedure…"_.
> - Write **discursively**: the goal is a deep technical reverse-engineering narrative,
>   not a line-by-line transcript. Do NOT walk the source statement after statement;
>   group related facts into coherent paragraphs.
> - Identify the **functional responsibility** of the section and its place in the wider process.
> - Identify the **business value** (what changes for the user / system after execution).
> - **FORBIDDEN:** sentences that report line counts, line ranges, percentage of source,
>   number of PERFORM / CALL / GO TO verbs, or any other structural statistic. Those facts
>   live in `facts.json` and in citation footnotes — never in prose.
> - Cite source ranges using the Pandoc-footnote form `[^src-N]` (see
>   `citations-and-confidence.instructions.md`); never inline `[FILE:Lx-Ly]` tags.

## Logic
{{LOGIC_DESCRIPTION}}

> Authoring rules (binding):
> - At least 6 sentences explaining **how the logic works**, not how big it is.
> - Describe the algorithmic structure (loops, decisions, error handling, transactions,
>   invariants, pre/post-conditions) **discursively**, grouping related verbs and
>   variables into coherent paragraphs. Do NOT narrate "line 120 does X, line 121 does
>   Y, line 122 does Z" — that is a transcript, not documentation.
> - Use business-domain vocabulary wherever possible.
> - Cite each important control construct with a `[^src-N]` footnote anchored to the
>   relevant source range.
> - **FORBIDDEN:** "the section spans N lines", "accounts for X% of the source",
>   "contains N PERFORM/CALL/GO TO", or any equivalent line-count / branch-count filler.

## Flow
{{FLOW_NARRATIVE}}

> Authoring rules (binding):
> - At least 6 sentences describing the end-to-end flow in plain language.
> - Make exit conditions, nominal cases, and error paths explicit.
> - **FORBIDDEN:** restating the section's line range or counting verbs; use the
>   diagram below for structure and the prose for meaning.

Steps (in execution order):
{{#FLOW_STEPS}}
{{STEP_NUMBER}}. {{STEP_DESCRIPTION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/FLOW_STEPS}}

### Flow diagram
```mermaid
{{FLOW_MERMAID}}
```
*Figure 1 — replace with a business-language description of the flow (≤ 25 words).*

> **Diagram authoring rules (binding) — read `mermaid-authoring/SKILL.md`:**
> - The flow diagram MUST be **useful**: a reader who cannot read COBOL must be able to
>   understand what the section does from the diagram alone.
> - At minimum show: entry point, every decision (IF / EVALUATE) with branch labels,
>   every loop with its termination condition, every external I/O verb (READ / WRITE /
>   REWRITE / DELETE / OPEN / CLOSE / CALL / EXEC SQL / EXEC CICS) annotated with the
>   target dataset / table / program, and the nominal vs. error exits.
> - Use Mermaid `flowchart TD` for procedural sections, `sequenceDiagram` for CICS
>   conversations, `stateDiagram-v2` for cursor / pseudo-conversational lifecycles.
> - Trivial 3-node placeholders (`Enter → Body → Exit`) are FORBIDDEN unless the chunk
>   is genuinely empty (data-only section). When there is even one decision or one I/O
>   verb in `bundle.facts_slice`, it MUST appear in the diagram.
> - Node labels use business-domain language where possible (e.g. `Load T22 reference
>   table`, not `MOVE WS-IDX TO WS-T22-IDX`).
> - **Every diagram MUST be followed by exactly one italicised caption line
>   `*Figure N — <business-language description>.*`** (single sentence, ≤ 25 words,
>   target language of the document, sequential numbering starting at 1).
> - **Forbidden:** `[Open in Draw.io](...)` / `app.diagrams.net` links.

{{#EXTRA_DIAGRAMS}}
### {{EXTRA_DIAGRAM_TITLE}}

```mermaid
{{EXTRA_DIAGRAM_MERMAID}}
```
*Figure N — replace with the real sequential figure number and a business-language caption (≤ 25 words).*
{{/EXTRA_DIAGRAMS}}

## Section documentation

<!-- The previous "Mandatory section — never leave empty. Provides the full
     documentary narrative… for readers without source-code access" banner is
     FORBIDDEN per .github/instructions/no-generator-boilerplate.instructions.md
     and must NEVER be re-introduced. The body of this section already proves the
     authoring rule — a meta callout adds nothing. -->

### Business context
{{BUSINESS_CONTEXT}}

> At least 3 sentences. Explain which business process the section implements, which
> actors it involves, which domain entity it mutates.

### Detailed behaviour
{{DETAILED_BEHAVIOR}}

> At least 5 sentences. Walk through the logic step by step with explicit references
> to variables, records, and business rules — never to raw line counts. Include
> invariants, pre-conditions, and post-conditions. Every claim MUST carry a Pandoc
> footnote `[^src-N]` resolving to the relevant source range; confidence is recorded
> in the footnote definition, not inline.

### Data and contracts touched
{{DATA_CONTRACTS_NARRATIVE}}

> Describe the records, fields, and formats touched by the section (COBOL records,
> DB2 tables, BMS maps, TS/TD queues, VSAM datasets). Reference copybooks and DCLGENs
> where applicable.

### Preconditions
{{#PRECONDITIONS}}
- {{PRECONDITION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/PRECONDITIONS}}
{{^PRECONDITIONS}}
- _None — the section makes no assumptions about caller state._
{{/PRECONDITIONS}}

> List every state the caller, the environment, or upstream sections **must**
> guarantee before entry (files opened, cursors positioned, working-storage flags
> initialised, DB2 transaction open, CICS commarea populated, etc.). Each item is a
> single declarative sentence with a `[^src-N]` citation when evidence exists in the
> source. If the section is genuinely unconditional, use the default bullet — do not
> invent placeholders.

### Postconditions
{{#POSTCONDITIONS}}
- {{POSTCONDITION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/POSTCONDITIONS}}
{{^POSTCONDITIONS}}
- _None — the section leaves observable state unchanged._
{{/POSTCONDITIONS}}

> Mirror image of preconditions: what is **guaranteed to be true** on every nominal
> exit (records written, return-code set, commit issued, cursor closed, output
> commarea populated). Error exits belong to _Edge cases and errors_, not here.

### Invariants
{{#INVARIANTS}}
- {{INVARIANT}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/INVARIANTS}}
{{^INVARIANTS}}
- _No loop or transactional invariant identified._
{{/INVARIANTS}}

> Conditions that hold **throughout** execution — loop invariants, accumulator
> identities (`WS-TOT-IN = WS-TOT-OUT + WS-TOT-REJ`), referential integrity rules
> between records, ordering assumptions on input files, transactional atomicity
> boundaries. Critical for the modernization step that will replace COBOL semantics
> with the target language's constructs.

### Nominal cases and examples
{{#EXAMPLES}}
- **{{EXAMPLE_TITLE}}** — Input: `{{EXAMPLE_INPUT}}` → Expected output: `{{EXAMPLE_OUTPUT}}` — {{EXAMPLE_NOTES}}
{{/EXAMPLES}}
{{^EXAMPLES}}
- _Populate with at least one representative example._
{{/EXAMPLES}}

### Edge cases and errors
{{#EDGE_CASES}}
- **{{EDGE_TITLE}}** — Trigger: {{EDGE_TRIGGER}} → Behaviour: {{EDGE_BEHAVIOR}}
{{/EDGE_CASES}}
{{^EDGE_CASES}}
- _No edge cases identified; still document what happens with empty / out-of-range inputs._
{{/EDGE_CASES}}

### Design decisions and rationale
{{#DECISIONS}}
- **{{DECISION_TITLE}}** — {{DECISION_RATIONALE}}
{{/DECISIONS}}
{{^DECISIONS}}
- _No design decision worth highlighting in this section._
{{/DECISIONS}}

### Modernization implications
{{MODERNIZATION_NOTES}}

> At least 2 sentences. Indicate how the logic will map to the target stack
> (Java/Spring Batch, .NET/Functions, Postgres, etc.) and which specific risks the
> migration inherits from this section.

### Complexity and migration risk
| Dimension | Value | Source |
|-----------|-------|--------|
| Cyclomatic complexity | {{COMPLEXITY_CYCLOMATIC}} | `facts.json` |
| Fan-in (called by) | {{FANIN_COUNT}} | `facts.json` |
| Fan-out (calls) | {{FANOUT_COUNT}} | `facts.json` |
| External I/O verbs | {{EXTIO_COUNT}} | `facts.json` |
| EXEC SQL / CICS statements | {{EXEC_COUNT}} | `facts.json` |
| Migration risk | {{MIGRATION_RISK_LEVEL}} ({{MIGRATION_RISK_LEVEL_RATIONALE}}) | analyst |

> The numeric cells are mechanically lifted from `facts.json` — do NOT recompute or
> paraphrase them in the prose above. `MIGRATION_RISK_LEVEL` is one of `low`,
> `medium`, `high`, `blocker`; the rationale is a short clause (e.g. _"dynamic CALL
> resolved at runtime"_, _"GO TO out of perform range"_, _"ALTER verb in use"_).

## Dead / unreachable code
{{#DEAD_CODE}}
- ⚠️ **{{DEAD_KIND}}** `{{DEAD_NAME}}` (L{{DEAD_START}}–L{{DEAD_END}}) — {{DEAD_REASON}}
{{/DEAD_CODE}}
{{^DEAD_CODE}}
- No dead code detected in this section.
{{/DEAD_CODE}}

## Variables read / written
| Variable | Mode | Type / PIC | Source / Destination | Notes |
|----------|------|------------|----------------------|-------|
{{#IO_TABLE}}
| `{{VAR}}` | {{MODE}} | `{{PIC}}` | {{SRC_OR_DST}} | {{NOTES}} |
{{/IO_TABLE}}

> `MODE` is one of `R` (read), `W` (write), `R/W` (read-modify-write), `INIT`
> (one-shot initialisation). When a variable belongs to a copybook, the
> `Source / Destination` cell MUST reference the copybook name (e.g.
> `AXAE001C / WS-CUSTOMER-REC`) so the reader can navigate to the structure.

## Side effects

_Observable changes this section causes **outside its own local working
storage** — i.e. anything a caller or downstream step can see after
control returns. Examples: records written to a file or VSAM dataset,
rows inserted/updated/deleted in DB2, messages enqueued (MQ/CICS TD/TS
queues), maps sent to a terminal, return-codes set for the JCL step,
abends raised, programs invoked via CALL/LINK/XCTL that themselves
mutate state. Read-only access and updates confined to the section's
own local variables are NOT side effects._

{{#SIDE_EFFECTS}}
- {{EFFECT}}
{{/SIDE_EFFECTS}}
{{^SIDE_EFFECTS}}
- _None — the section is pure with respect to external state._
{{/SIDE_EFFECTS}}

## Cross-references

### Calls / uses (outgoing)
{{#XREF_OUT}}
- {{TYPE}}: `{{TARGET}}` — `{{TARGET_FILE}}`
{{/XREF_OUT}}
{{^XREF_OUT}}
- _None._
{{/XREF_OUT}}

### Called / used by (incoming)
{{#XREF_IN}}
- {{TYPE}}: `{{SOURCE_REF}}` — `{{SOURCE_FILE}}`
{{/XREF_IN}}
{{^XREF_IN}}
- _None detected in workspace._
{{/XREF_IN}}

### External dependencies (datasets / tables / queues / maps / programs)
{{#XREF_EXTERNAL}}
- {{KIND}}: `{{NAME}}` {{#NOTES}}— {{NOTES}}{{/NOTES}}
{{/XREF_EXTERNAL}}

## Warnings
{{#WARNINGS}}
- ⚠️ {{WARNING}}
{{/WARNINGS}}
{{^WARNINGS}}
- _No warnings raised for this section._
{{/WARNINGS}}

## Citations

<!-- Pandoc footnote definitions for every `[^src-N]` marker used above. Generated
     from facts.json; never hand-edit. Each entry pins the claim to an exact source
     range and records the analyst's confidence (high / medium / low) plus the
     evidence kind (verbatim / paraphrase / inference). See
     .github/instructions/citations-and-confidence.instructions.md.
     **BINDING:** every `CITATION_FILE` MUST be an original source listing
     (COBOL / JCL / PROC / copybook / BMS member under `repos/`). NEVER cite
     `facts.json`, `chunk-manifest.json`, any `*.bundle.md` / `*.bundle.json`,
     a facts-slice, or any other generated artefact — those are derived from
     the source and add no evidence beyond it. If the only available
     provenance is a generated artefact, the claim does not belong in the
     section narrative; surface it as a `_Warnings_` bullet instead. -->

{{#CITATIONS}}
[^src-{{CITATION_ID}}]: `{{CITATION_FILE}}` L{{CITATION_START}}–L{{CITATION_END}} — confidence: **{{CITATION_CONFIDENCE}}**, evidence: {{CITATION_EVIDENCE_KIND}}.{{#CITATION_NOTE}} {{CITATION_NOTE}}{{/CITATION_NOTE}}
{{/CITATIONS}}
{{^CITATIONS}}
_No citations emitted — the section narrative above must therefore contain no `[^src-N]` markers._
{{/CITATIONS}}

---

<!-- Authoring self-check. MUST be evaluated by the generator before emitting the
     document; any unchecked box is a hard failure surfaced in the lint report. Do
     NOT delete this block — it is the contract that keeps the narrative honest. -->

### Authoring self-check
- [ ] Summary is a single business-language sentence, ≤ 30 words, no COBOL jargon.
- [ ] Purpose ≥ 4 sentences and avoids any forbidden textbook opener.
- [ ] Logic ≥ 6 sentences, discursive, no line-count / verb-count filler.
- [ ] Flow narrative ≥ 6 sentences; every decision and external I/O verb in
      `bundle.facts_slice` is reflected in the Mermaid diagram.
- [ ] Every Mermaid diagram is immediately followed by an italicised caption
      line `*Figure N — <description>.*` with sequential figure numbering
      starting at 1.
- [ ] Preconditions, Postconditions and Invariants are populated or explicitly
      marked as _None_ — never left blank.
- [ ] Every `[^src-N]` marker in the body has a matching definition under
      _Citations_; every definition is actually referenced.
- [ ] No `[FILE:Lx-Ly]` inline tags, no `app.diagrams.net` / Draw.io links, no
      "self-contained document / bundles facts.json" banner.
- [ ] `Complexity and migration risk` cells match `bundle.facts_slice`
      byte-for-byte (counts are sourced from the slice; the same values were
      emitted by the file-level `facts.json` extractor).
