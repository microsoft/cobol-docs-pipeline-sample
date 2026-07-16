# {{SECTION_NUMBER}}. {{SECTION_NAME}}

> **Source file:** `{{SOURCE_PATH}}` · **Chunk kind:** {{CHUNK_KIND}} · **Parent:** {{PARENT_NAME}} · **Reachability:** {{REACHABILITY}}

<!-- Provenance (line range, PERFORM / CALL / GO TO counts, EXEC SQL / EXEC CICS
     counts, exit-verb inventory) is recorded in facts.json and in the source
     citation footnotes; do NOT surface it as a header banner or as narrative
     filler. The reader needs to understand WHAT this one section does, HOW it
     is entered and exited, and WHICH external resources it touches — not how
     many lines or verbs it contains. The division-level overview lives in the
     PROCEDURE DIVISION template, not here. See
     .github/instructions/no-generator-boilerplate.instructions.md — the
     "Self-contained document. Bundles… from facts.json…" banner that used to
     live here is FORBIDDEN and must NEVER be re-introduced. -->

## Summary
{{TLDR_ONE_LINER}}

> Authoring rules (binding):
> - Exactly **one sentence**, ≤ 30 words, written in business-domain language.
> - Must answer: _"What does this section accomplish for the wider process?"_
> - **FORBIDDEN:** COBOL jargon (`PERFORM`, `EVALUATE`, `WORKING-STORAGE`),
>   line counts, verb counts, or restating the section name. No citations
>   here — the Summary is a hook, not a claim; full evidence lives in the
>   sections below.

## Purpose
{{PURPOSE_PARAGRAPH}}

> Authoring rules (binding):
> - At least 4 full sentences (≈ 80–120 words) focused on **what this
>   section is about** — i.e. the business or technical concern it
>   addresses — not on what a COBOL section **is** in the abstract and
>   not on the wider division.
> - **FORBIDDEN OPENERS:** "This section contains the following
>   statements…", "The section spans lines X to Y and performs…", "This
>   `PROCEDURE DIVISION` section implements the following logic…", or
>   any equivalent transcript-style preface. Always pivot to the concrete
>   business intent: _"This section applies an incoming transaction to
>   the customer master record, updating balances, refreshing the
>   last-activity timestamp and queueing an audit event when the
>   operation changes a regulated field…"_.
> - Write **discursively**: group related verbs and variables into
>   coherent paragraphs. Do NOT walk the source statement after
>   statement — that is a transcript, not documentation.
> - Identify the **functional responsibility** of the section and its
>   place in the wider process (which mainline stage it belongs to,
>   which sibling sections it cooperates with).
> - Identify the **business value** (what changes for the user / system
>   after execution).
> - **FORBIDDEN:** sentences that report line counts, line ranges,
>   percentage of source, number of `PERFORM` / `CALL` / `GO TO` verbs,
>   or any other structural statistic. Those facts live in `facts.json`
>   and in citation footnotes — never in prose.
> - Cite source ranges using the Pandoc-footnote form `[^src-N]` (see
>   `citations-and-confidence.instructions.md`); never inline
>   `[FILE:Lx-Ly]` tags.

## Business context
{{BUSINESS_CONTEXT}}

> At least 3 sentences. Explain which business process the section
> implements, which actors it involves, which domain entity it mutates
> and which regulatory / contractual constraints it inherits (audit
> trail, idempotency, atomicity, retention).

## Entry contract
{{ENTRY_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences describing **how control reaches this section**.
>   Distinguish:
>   - `PERFORM <section>` — independently callable, isolated control flow.
>   - `PERFORM <section> THRU <other-section>` — section is part of a
>     range; flag it as **not independently callable** without the rest
>     of the range.
>   - `GO TO <section>` — non-returning jump; flag the originating
>     paragraph(s).
>   - **Fall-through from preceding section** — implicit entry that
>     disappears under naive refactoring.
>   - `DECLARATIVES` `USE` procedure — implicit invocation on an error /
>     reporting event.
>   - CICS entry-point / `EXEC CICS RETURN TRANSID` reactivation.
> - Make the **PERFORM loop semantics** explicit when applicable:
>   `TIMES`, `UNTIL`, `VARYING`, `WITH TEST BEFORE/AFTER` — these
>   determine whether the section runs zero, one, or many times per
>   invocation.

### Entry sites
| Kind | Caller | Loop semantics | Notes |
|------|--------|----------------|-------|
{{#ENTRY_TABLE}}
| {{ENTRY_KIND}} | `{{ENTRY_CALLER}}` | {{ENTRY_LOOP}} | {{ENTRY_NOTES}} |
{{/ENTRY_TABLE}}
{{^ENTRY_TABLE}}
| _No call site detected (potential unreachable section — see Warnings)._ | — | — | — |
{{/ENTRY_TABLE}}

> `Kind` is one of `PERFORM`, `PERFORM THRU`, `PERFORM VARYING`,
> `PERFORM UNTIL`, `PERFORM TIMES`, `GO TO`, `FALL-THROUGH`,
> `DECLARATIVES`, `CICS-ENTRY`. `Loop semantics` is the verbatim
> phrase that controls iteration (e.g. `UNTIL WS-EOF-FLAG = 'Y'`) or
> `—` for one-shot entries.

## Detailed behaviour
{{DETAILED_BEHAVIOR}}

> Authoring rules (binding):
> - At least 6 sentences. Walk through the algorithm **discursively** with
>   explicit references to named variables, records and business rules,
>   grouping related verbs into coherent paragraphs.
> - Cover the algorithmic structure (loops, decisions, error handling,
>   transactions) and the in-flight state mutations.
> - Every claim MUST carry a Pandoc footnote `[^src-N]` resolving to the
>   relevant source range; confidence is recorded in the footnote
>   definition, not inline.
> - **FORBIDDEN:** "line 120 does X, line 121 does Y" transcripts;
>   "the section spans N lines / contains N PERFORMs" filler.

## Flow
{{FLOW_NARRATIVE}}
> Important: the flow narrative is NOT a transcript of the source. It is a high-level walkthrough of the algorithmic structure, focused on control flow and business logic, NOT on COBOL syntax or line-by-line action. The flow diagram MUST be understandable to a reader who cannot read COBOL — it is a business-domain artifact, not a code map.
> Authoring rules (binding):
> - At least 6 sentences describing the end-to-end flow in plain language.
> - It is important to make exit conditions, nominal cases, and error paths explicit.
> - **FORBIDDEN:** restating the section's line range or counting verbs; use the
>   diagram below for structure and the prose for meaning.

Steps in execution order:
{{#FLOW_STEPS}}
{{STEP_NUMBER}}. {{STEP_DESCRIPTION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/FLOW_STEPS}}

### Flow diagram
```mermaid
{{FLOW_MERMAID}}
```
*Figure {{SECTION_NUMBER}}.1 — describe in business terms what this diagram shows (≤ 25 words). Replace this italicised line with the real caption; do NOT leave the placeholder.*

> **Diagram authoring rules (binding) — read `mermaid-authoring/SKILL.md`:**
> - The flow diagram MUST be **useful**: a reader who cannot read COBOL
>   must be able to understand what the section does from the diagram
>   alone.
> - At minimum show: entry point, every decision (`IF` / `EVALUATE`)
>   with branch labels, every loop with its termination condition,
>   every external I/O verb (`READ` / `WRITE` / `REWRITE` / `DELETE` /
>   `OPEN` / `CLOSE` / `CALL` / `EXEC SQL` / `EXEC CICS`) annotated
>   with the target dataset / table / program, and the nominal vs.
>   error exits.
> - Use Mermaid `flowchart TD` for procedural sections,
>   `sequenceDiagram` for CICS conversations, `stateDiagram-v2` for
>   cursor / pseudo-conversational lifecycles.
> - Trivial 3-node placeholders (`Enter → Body → Exit`) are FORBIDDEN
>   unless the section is genuinely empty. When there is even one
>   decision or one I/O verb in `bundle.facts_slice`, it MUST appear
>   in the diagram.
> - Node labels use business-domain language where possible (e.g.
>   `Load T22 reference table`, not `MOVE WS-IDX TO WS-T22-IDX`).
> - **Every diagram MUST be followed by exactly one italicised caption
>   line of the form `*Figure N — <business-language description>.*`.**
>   The caption is a single full sentence (≤ 25 words) in the
>   document's target language that explains what the diagram shows in
>   domain terms; never a restatement of the section name. Figures are
>   numbered sequentially within the document, starting at 1. The
>   caption is required for EVERY mermaid block (flow, extra, sequence,
>   state, ER).
> - **Forbidden:** `[Open in Draw.io](...)` / `app.diagrams.net` links.

{{#EXTRA_DIAGRAMS}}
### {{EXTRA_DIAGRAM_TITLE}}

```mermaid
{{EXTRA_DIAGRAM_MERMAID}}
```
*Figure {{SECTION_NUMBER}}.N — replace with the real sequential figure number and a business-language caption (≤ 25 words).*
{{/EXTRA_DIAGRAMS}}

## Exit contract
{{EXIT_NARRATIVE}}

> Authoring rules (binding):
> - At least 2 sentences describing **how control leaves this section**.
>   Identify every exit verb in source order: `EXIT.`,
>   `EXIT SECTION.`, `EXIT PARAGRAPH.`, `EXIT PERFORM`, `GOBACK`,
>   `STOP RUN`, `EXIT PROGRAM`, `EXEC CICS RETURN`, `EXEC CICS XCTL`,
>   `GO TO <other section>`, **fall-through into the next section**.
> - **Fall-through is a critical fact:** flag it explicitly in the
>   table below and in _Warnings_ — the section is then not safely
>   refactorable in isolation, and the next section becomes part of
>   its implicit body.

### Exit sites
| Exit | Location | Effect | Notes |
|------|----------|--------|-------|
{{#EXIT_TABLE}}
| `{{EXIT_VERB}}` | `{{EXIT_LOCATION}}` | {{EXIT_EFFECT}} | {{EXIT_NOTES}} |
{{/EXIT_TABLE}}
{{^EXIT_TABLE}}
| _No explicit exit verb — section falls through into the next section in source order._ | — | implicit | ⚠️ list in Warnings |
{{/EXIT_TABLE}}

## Preconditions
{{#PRECONDITIONS}}
- {{PRECONDITION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/PRECONDITIONS}}
{{^PRECONDITIONS}}
- _None — the section makes no assumption about caller state._
{{/PRECONDITIONS}}

> Every state the caller, the environment, or upstream sections MUST
> guarantee before entry (files opened, cursors positioned,
> working-storage flags initialised, DB2 transaction open, CICS
> commarea populated, host-variables filled, etc.). One declarative
> sentence per item, with a `[^src-N]` citation when evidence exists.

## Postconditions
{{#POSTCONDITIONS}}
- {{POSTCONDITION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/POSTCONDITIONS}}
{{^POSTCONDITIONS}}
- _None — the section leaves observable state unchanged._
{{/POSTCONDITIONS}}

> Mirror image of preconditions: what is **guaranteed to be true** on
> every nominal exit. Error exits belong to _Edge cases and errors_.

## Invariants
{{#INVARIANTS}}
- {{INVARIANT}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/INVARIANTS}}
{{^INVARIANTS}}
- _No loop or transactional invariant identified._
{{/INVARIANTS}}

> Conditions that hold **throughout** execution — loop invariants,
> accumulator identities (`WS-TOT-IN = WS-TOT-OUT + WS-TOT-REJ`),
> referential integrity rules, ordering assumptions on input files,
> transactional atomicity boundaries.

## Nominal cases and examples
{{#EXAMPLES}}
- **{{EXAMPLE_TITLE}}** — Input: `{{EXAMPLE_INPUT}}` → Expected output: `{{EXAMPLE_OUTPUT}}` — {{EXAMPLE_NOTES}}
{{/EXAMPLES}}
{{^EXAMPLES}}
- _Populate with at least one representative example._
{{/EXAMPLES}}

## Edge cases and errors
{{#EDGE_CASES}}
- **{{EDGE_TITLE}}** — Trigger: {{EDGE_TRIGGER}} → Behaviour: {{EDGE_BEHAVIOR}}
{{/EDGE_CASES}}
{{^EDGE_CASES}}
- _No edge cases identified; still document what happens with empty / out-of-range inputs._
{{/EDGE_CASES}}

## Design decisions and rationale
{{#DECISIONS}}
- **{{DECISION_TITLE}}** — {{DECISION_RATIONALE}}
{{/DECISIONS}}
{{^DECISIONS}}
- _No design decision worth highlighting in this section._
{{/DECISIONS}}

## Data and contracts touched

### Variables read / written
| Variable | Mode | Type / PIC | Origin (copybook / section) | Notes |
|----------|------|------------|------------------------------|-------|
{{#IO_TABLE}}
| `{{VAR}}` | {{MODE}} | `{{PIC}}` | {{ORIGIN}} | {{NOTES}} |
{{/IO_TABLE}}
{{^IO_TABLE}}
| _No working-storage / linkage variables touched._ | — | — | — | — |
{{/IO_TABLE}}

> `Mode` is one of `R` (read), `W` (write), `R/W` (read-modify-write),
> `INIT` (one-shot initialisation). When a variable belongs to a
> copybook, the `Origin` cell MUST name the copybook **and** the parent
> 01-level (e.g. `AXAE001C / WS-CUSTOMER-REC.WS-CUST-BAL`) so the
> reader can navigate to the structure.

### EXEC SQL statements
| Verb | Target | Host variables | Cursor | Notes |
|------|--------|----------------|--------|-------|
{{#EXEC_SQL_TABLE}}
| `{{SQL_VERB}}` | `{{SQL_TARGET}}` | `{{SQL_HOSTVARS}}` | `{{SQL_CURSOR}}` | {{SQL_NOTES}} |
{{/EXEC_SQL_TABLE}}
{{^EXEC_SQL_TABLE}}
| _No `EXEC SQL` statements in this section._ | — | — | — | — |
{{/EXEC_SQL_TABLE}}

> `Verb` is one of `SELECT`, `INSERT`, `UPDATE`, `DELETE`,
> `OPEN CURSOR`, `FETCH`, `CLOSE CURSOR`, `DECLARE CURSOR`, `COMMIT`,
> `ROLLBACK`, `WHENEVER`. `Target` is the table / view name (or the
> cursor name for `OPEN` / `FETCH` / `CLOSE`).

### EXEC CICS statements
| Command | Resource | COMMAREA / parameters | Handler | Notes |
|---------|----------|------------------------|---------|-------|
{{#EXEC_CICS_TABLE}}
| `{{CICS_COMMAND}}` | `{{CICS_RESOURCE}}` | `{{CICS_PARAMS}}` | {{CICS_HANDLER}} | {{CICS_NOTES}} |
{{/EXEC_CICS_TABLE}}
{{^EXEC_CICS_TABLE}}
| _No `EXEC CICS` statements in this section._ | — | — | — | — |
{{/EXEC_CICS_TABLE}}

> `Command` is the CICS verb (`READ`, `WRITE`, `LINK`, `XCTL`,
> `SEND MAP`, `RECEIVE MAP`, `READQ TS`, `WRITEQ TS`, `START`,
> `RETURN`, …). `Handler` lists the `RESP` / `NOHANDLE` / `HANDLE
> CONDITION` strategy in force; flag `HANDLE CONDITION` paths as
> implicit control transfers.

## Side effects

| Kind | Target | Trigger / condition | Idempotent? | Notes |
|------|--------|---------------------|-------------|-------|
{{#SIDE_EFFECTS_TABLE}}
| {{SE_KIND}} | `{{SE_TARGET}}` | {{SE_TRIGGER}} | {{SE_IDEMPOTENT}} | {{SE_NOTES}} |
{{/SIDE_EFFECTS_TABLE}}
{{^SIDE_EFFECTS_TABLE}}
| _None — the section is pure with respect to external state._ | — | — | — | — |
{{/SIDE_EFFECTS_TABLE}}

> _Observable changes this section causes **outside its own local
> working storage** — i.e. anything a caller or downstream step can
> see after control returns._ `Kind` is one of `FILE-WRITE`,
> `FILE-DELETE`, `DB2-INSERT`, `DB2-UPDATE`, `DB2-DELETE`,
> `DB2-COMMIT`, `DB2-ROLLBACK`, `MQ-PUT`, `CICS-SEND`,
> `CICS-WRITEQ-TS`, `CICS-WRITEQ-TD`, `CICS-LINK`, `CICS-XCTL`,
> `CICS-START`, `RETURN-CODE-SET`, `ABEND`, `CALL-WITH-SIDE-EFFECT`.
> Read-only access and updates confined to local variables are NOT
> side effects.

## Modernization implications
{{MODERNIZATION_NOTES}}

> At least 2 sentences. Indicate how this section's logic will map to
> the target stack (Java / Spring Batch, .NET / Functions, Postgres,
> etc.) and which specific risks the migration inherits (fall-through
> entry, `PERFORM THRU` range membership, dynamic `CALL`, `GO TO`
> mesh, implicit `EXEC CICS HANDLE` transfers).

## Complexity and migration risk
| Dimension | Value | Source |
|-----------|-------|--------|
| Cyclomatic complexity | {{COMPLEXITY_CYCLOMATIC}} | `facts.json` |
| Fan-in (entry sites) | {{FANIN_COUNT}} | `facts.json` |
| Fan-out (calls / GO TO) | {{FANOUT_COUNT}} | `facts.json` |
| External I/O verbs | {{EXTIO_COUNT}} | `facts.json` |
| `EXEC SQL` statements | {{EXEC_SQL_COUNT}} | `facts.json` |
| `EXEC CICS` statements | {{EXEC_CICS_COUNT}} | `facts.json` |
| `PERFORM THRU` range member? | {{PERFORM_THRU_MEMBER}} | `facts.json` |
| Fall-through exit? | {{FALL_THROUGH}} | `facts.json` |
| Migration risk | {{MIGRATION_RISK_LEVEL}} ({{MIGRATION_RISK_LEVEL_RATIONALE}}) | analyst |

> Numeric cells are mechanically lifted from `facts.json` — do NOT
> recompute or paraphrase them in the prose above. `PERFORM THRU range
> member?` and `Fall-through exit?` are `yes` / `no`.
> `MIGRATION_RISK_LEVEL` is one of `low`, `medium`, `high`,
> `blocker`; the rationale is a short clause (e.g. _"dynamic `CALL`
> resolved at runtime"_, _"`GO TO` out of `PERFORM` range"_,
> _"`ALTER` verb in use"_, _"fall-through into next section"_).

## Dead / unreachable code
{{#DEAD_CODE}}
- ⚠️ **{{DEAD_KIND}}** `{{DEAD_NAME}}` (L{{DEAD_START}}–L{{DEAD_END}}) — {{DEAD_REASON}}
{{/DEAD_CODE}}
{{^DEAD_CODE}}
- No dead code detected in this section.
{{/DEAD_CODE}}

## Cross-references

### Calls / uses (outgoing)
{{#XREF_OUT}}
- {{TYPE}}: `{{TARGET}}` — `{{TARGET_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_OUT}}
{{^XREF_OUT}}
- _None._
{{/XREF_OUT}}

### Called / used by (incoming)
{{#XREF_IN}}
- {{TYPE}}: `{{SOURCE_REF}}` — `{{SOURCE_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_IN}}
{{^XREF_IN}}
- _None detected in workspace._
{{/XREF_IN}}

### Data touched (records read / written by this section)
| 01-level / field | Mode | Verb | Owning record's source | Other workspace consumers |
|------------------|------|------|------------------------|---------------------------|
{{#XREF_DATA_TOUCHED}}
| `{{DATA_NAME}}` | {{DATA_MODE}} | `{{DATA_VERB}}` | `{{DATA_OWNER_FILE}}` | {{DATA_OTHER_CONSUMERS}} |
{{/XREF_DATA_TOUCHED}}
{{^XREF_DATA_TOUCHED}}
| _This section reads / writes no `01`-level record beyond local working-storage scratch fields._ | — | — | — | — |
{{/XREF_DATA_TOUCHED}}

> `Mode` ∈ `R`, `W`, `R/W`, `INIT`. `Owning record's source` is the
> source file that DECLARES the record (typically a copybook / DCLGEN
> shared with other programs, or this program's own
> `WORKING-STORAGE`). `Other workspace consumers` lists every other
> source file that also reads / writes the same `01`-level (or its
> shared layout via copybook) — drawn from the bundle's
> `data_records[].consumers[]` and the workspace incoming-xref of any
> shared copybook. Use `_None._` when the record is private to this
> program. NEVER omit this table on a section that issues `MOVE`,
> `READ`, `WRITE`, `REWRITE`, `EXEC SQL FETCH … INTO`,
> `EXEC CICS RECEIVE MAP` or `CALL … USING`.

### File / dataset bindings (`DDNAME` ↔ `FD` / `SELECT` ↔ `DSN`)
| Logical file (`SELECT` / `FD`) | DDNAME | DSN (when known) | Direction | Bound by JCL step | Notes |
|--------------------------------|--------|------------------|-----------|--------------------|-------|
{{#XREF_FILE_BINDINGS}}
| `{{FB_LOGICAL}}` | `{{FB_DDNAME}}` | `{{FB_DSN}}` | {{FB_DIRECTION}} | `{{FB_JCL_STEP}}` | {{FB_NOTES}} |
{{/XREF_FILE_BINDINGS}}
{{^XREF_FILE_BINDINGS}}
| _This section opens / reads / writes no external file._ | — | — | — | — | — |
{{/XREF_FILE_BINDINGS}}

> Resolve each row by joining the program's `files[]` slice
> (logical-name ↔ external-name) with every JCL step in the
> workspace whose invoked program matches this source file: the
> JCL `DDNAME` is the external name; the `DSN` and `Direction`
> (`IN` / `OUT` / `MOD`) come from the JCL step's `dds[]`.
> `Bound by JCL step` MUST cite the step's qualified id
> (`<JCL>.<JOB>.<STEP>`). NEVER guess a `DSN` that is not
> declared in any JCL step in the workspace; leave it as `—`.

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

> Fall-through exit, `PERFORM THRU` range membership, `GO TO` out of
> range, dynamic `CALL`, recursive `PERFORM`, `ALTER`,
> `EXEC CICS HANDLE CONDITION` implicit transfers and `ENTRY`
> statements MUST each surface a warning bullet here in addition to
> the relevant tables above.

## Citations

<!-- Pandoc footnote definitions for every `[^src-N]` marker used above.
     Generated from facts.json; never hand-edit. Each entry pins the claim to
     an exact source range and records the analyst's confidence (high / medium
     / low) plus the evidence kind (verbatim / paraphrase / inference). See
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

<!-- Authoring self-check. MUST be evaluated by the generator before emitting
     the document; any unchecked box is a hard failure surfaced in the lint
     report. Do NOT delete this block — it is the contract that keeps the
     narrative honest. -->

### Authoring self-check
- [ ] Summary is a single business-language sentence, ≤ 30 words, no COBOL jargon.
- [ ] Purpose ≥ 4 sentences and avoids any forbidden transcript opener.
- [ ] `Entry contract` lists every entry site from `bundle.facts_slice`
      (e.g. `performs`, `incoming_xref`) with its kind and (when
      applicable) loop semantics. `PERFORM THRU` range membership is
      flagged.
- [ ] `Detailed behaviour` ≥ 6 sentences, discursive, citation-backed, no
      line-count / verb-count filler.
- [ ] `Flow` numbered steps and the Mermaid diagram cover every decision
      and every external I/O verb in `bundle.facts_slice`; no
      `Enter → Body → Exit` placeholder.
- [ ] Every Mermaid diagram in the document is immediately followed by an
      italicised caption line `*Figure N — <description>.*` with a
      sequential figure number starting at 1.
- [ ] `Exit contract` lists every exit verb in `bundle.facts_slice`. If
      the section falls through into the next section, the fall-through
      is flagged here AND in _Warnings_.
- [ ] Preconditions, Postconditions and Invariants are populated or
      explicitly marked as _None_ — never left blank.
- [ ] `EXEC SQL` and `EXEC CICS` tables list every statement in
      `bundle.facts_slice.exec_sql` / `bundle.facts_slice.exec_cics`
      with target, host variables / parameters and (for CICS) the
      handler strategy.
- [ ] `Cross-references` block is populated from `bundle.facts_slice`:
      outgoing (`performs`, `calls`, `go_tos`, `copybooks`, `exec_sql`,
      `exec_cics`), incoming (`incoming_xref`), external dependencies
      (`files`, `jcl_steps`, `bms_maps`); empty subsections are
      explicitly marked `_None._`.
- [ ] `Side effects` table is populated; every entry has a `Kind`,
      `Target` and `Idempotent?` value.
- [ ] Every `[^src-N]` marker in the body has a matching definition under
      _Citations_; every definition is actually referenced.
- [ ] No `[FILE:Lx-Ly]` inline tags, no `app.diagrams.net` / Draw.io
      links, no "self-contained document / bundles facts.json" banner,
      no separate `Logic` + `Flow explanation` duplicating
      `Detailed behaviour`.
- [ ] `Complexity and migration risk` cells match `bundle.facts_slice`
      byte-for-byte (counts are sourced from the slice; the same values
      were emitted by the file-level `facts.json` extractor).
