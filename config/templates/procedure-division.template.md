# {{SECTION_NUMBER}}. {{SECTION_NAME}}

> **Source file:** `{{SOURCE_PATH}}` · **Chunk kind:** {{CHUNK_KIND}} · **Parent:** {{PARENT_NAME}} · **Reachability:** {{REACHABILITY}}

<!-- Provenance (line range, section / paragraph counts, PERFORM / CALL / GO TO
     counts, dynamic CALL count, EXEC SQL / EXEC CICS counts, DECLARATIVES
     presence, ALTER count) is recorded in facts.json and in the source citation
     footnotes; do NOT surface it as a header banner or as narrative filler. The
     reader needs to understand HOW the division is structured, WHICH sections
     drive the mainline, WHICH external resources it touches, and WHICH risky
     constructs it uses — not how many lines or verbs it contains. The per-section
     behavioural narrative lives in `section-doc.template.md`, one document per
     section. See .github/instructions/no-generator-boilerplate.instructions.md —
     the "Self-contained document. Bundles… from facts.json…" banner that used to
     live here is FORBIDDEN and must NEVER be re-introduced. -->

## Summary
{{TLDR_ONE_LINER}}

> Authoring rules (binding):
> - Exactly **one sentence**, ≤ 30 words, written in business / operations
>   language.
> - Must answer: _"What does this program do end-to-end, and through which
>   high-level steps does it deliver that outcome?"_
> - **FORBIDDEN:** COBOL jargon (`PERFORM`, `EVALUATE`, `GO TO`, `SECTION`,
>   `PARAGRAPH`), line counts, section counts, or restating the division name.
>   No citations here — the Summary is a hook, not a claim; full evidence lives
>   in the sections below.

## Purpose
{{PURPOSE_PARAGRAPH}}

> Authoring rules (binding):
> - At least 4 full sentences (≈ 80–120 words) focused on **what the division
>   does as a whole** — i.e. the business outcome it produces, the high-level
>   processing stages (init → driver → cleanup), the external resources it
>   touches, the call contract it honours with its caller — not on what a
>   PROCEDURE DIVISION **is** in the abstract and not on the inner workings
>   of any one section.
> - **FORBIDDEN OPENERS:** "The `PROCEDURE DIVISION` is one of the four
>   canonical COBOL divisions…", "The PROCEDURE DIVISION is the part of a
>   COBOL program that contains the executable statements…", or any
>   equivalent textbook-style definition. Always pivot to the concrete
>   content: _"This division drives the nightly customer-master refresh: an
>   init stage opens the master and transaction files and primes the lookup
>   tables, a driver loop walks the transaction file applying each
>   operation through `PROCESS-TRANSACTION`, and a cleanup stage flushes the
>   accumulators, writes the audit footer and returns the step return code
>   to the calling JCL…"_.
> - Write **discursively**: describe the program as a pipeline of stages,
>   not as a list of sections. Do NOT walk the source section-after-section
>   — the per-section narrative lives in `section-doc.md` pages.
> - Identify the **operational role** of the division: which JCL step or
>   CICS transaction triggers it, which upstream feeds it consumes, which
>   downstream artefacts (datasets, DB2 rows, MQ messages, terminal maps)
>   it produces, which return-code contract it honours.
> - **FORBIDDEN:** sentences that report section counts, paragraph counts,
>   `PERFORM`/`CALL`/`GO TO` counts, or any other structural statistic.
>   Those facts live in `facts.json` and in citation footnotes — never in
>   prose.
> - Cite source ranges using the Pandoc-footnote form `[^src-N]` (see
>   `citations-and-confidence.instructions.md`); never inline `[FILE:Lx-Ly]`
>   tags.

## Header and linkage contract
{{HEADER_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences (or the explicit sentence _"This program declares
>   `PROCEDURE DIVISION` with no `USING` clause."_ when absent — typical for
>   top-of-stack batch programs invoked directly by `EXEC PGM=`).
> - Describe the **call contract** declared on the `PROCEDURE DIVISION`
>   header: every parameter listed in `USING`, its passing mode
>   (`BY REFERENCE` default, `BY CONTENT`, `BY VALUE`), the `RETURNING`
>   item when present, and the mapping to the matching 01-level item in
>   the `LINKAGE SECTION`. For CICS programs, identify the implicit
>   `DFHCOMMAREA` parameter and any `EXEC CICS ADDRESS` / `EXEC CICS
>   HANDLE` setup that the caller relies on.

### `PROCEDURE DIVISION USING` parameters
| Position | Linkage item | Passing mode | Caller(s) | Notes |
|----------|--------------|--------------|-----------|-------|
{{#USING_TABLE}}
| {{USING_POSITION}} | `{{USING_NAME}}` | {{USING_MODE}} | {{USING_CALLERS}} | {{USING_NOTES}} |
{{/USING_TABLE}}
{{^USING_TABLE}}
| _No `USING` clause on the `PROCEDURE DIVISION` header._ | — | — | — | — |
{{/USING_TABLE}}

> `Passing mode` is one of `BY REFERENCE`, `BY CONTENT`, `BY VALUE`,
> `RETURNING`, `COMMAREA`. `Caller(s)` lists every call site discovered in
> the workspace (`CALL 'PGM' USING …`, `EXEC CICS LINK COMMAREA(…)`,
> `EXEC CICS XCTL …`); flag dynamic call sites separately.

## Section and paragraph inventory
{{INVENTORY_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences summarising the **shape** of the division: how
>   many top-level sections, how the mainline composes them, which
>   sections are pure utilities (called only via `PERFORM`), which are
>   error handlers (entered via `GO TO` or invoked from
>   `DECLARATIVES`), which are unreachable.
> - Do NOT describe the inner behaviour of any one section here — that is
>   the job of the per-section `section-doc.md` page linked in the table
>   below.

### Sections and top-level paragraphs
| Name | Kind | Role | Reachability | Fan-in | Fan-out | Section doc |
|------|------|------|--------------|--------|---------|-------------|
{{#PROC_INVENTORY_TABLE}}
| `{{PROC_NAME}}` | {{PROC_KIND}} | {{PROC_ROLE}} | {{PROC_REACHABILITY}} | {{PROC_FANIN}} | {{PROC_FANOUT}} | [{{PROC_DOC_LABEL}}]({{PROC_DOC_LINK}}) |
{{/PROC_INVENTORY_TABLE}}
{{^PROC_INVENTORY_TABLE}}
| _No sections or paragraphs declared (empty `PROCEDURE DIVISION`)._ | — | — | — | — | — | — |
{{/PROC_INVENTORY_TABLE}}

> `Kind` is one of `SECTION`, `PARAGRAPH`, `DECLARATIVES`. `Role` is one
> of `mainline`, `init`, `process`, `cleanup`, `error-handler`,
> `utility`, `dead`. `Reachability` is one of `reachable`,
> `entry-point`, `declaratives`, `unreachable`. Numeric columns are
> mechanically lifted from `facts.json` and MUST NOT be paraphrased in
> prose above.

## Mainline control flow
{{MAINLINE_NARRATIVE}}

> Authoring rules (binding):
> - At least 4 sentences describing the **top-level orchestration** — the
>   chain of `PERFORM` calls the entry section issues to drive the program
>   from start to termination. Stay at the section level: _"the mainline
>   opens the resources via `0000-INIT`, then loops on `1000-PROCESS`
>   until end-of-file, then flushes through `9000-CLEANUP` before
>   `GOBACK`"_. Do NOT drop into the inner verbs of any one section.
> - Make the **driver loop** explicit: which section / paragraph is the
>   loop body, which `UNTIL` / `VARYING` condition terminates it, which
>   `PERFORM THRU` ranges are used. Flag `PERFORM THRU` over disjoint
>   paragraphs and any recursive `PERFORM` (a section that ends up
>   calling itself indirectly).

### Mainline diagram
```mermaid
{{MAINLINE_MERMAID}}
```
*Figure 1 — replace with a business-language description of the mainline (≤ 25 words).*

> **Diagram authoring rules (binding) — read `mermaid-authoring/SKILL.md`:**
> - The mainline diagram MUST show **structure**, not inner behaviour:
>   one node per section / top-level paragraph the mainline `PERFORM`s,
>   labelled with the section's `Role` (`init`, `process`, `cleanup`,
>   `error-handler`).
> - The driver loop MUST be visible as a Mermaid loop with its `UNTIL` /
>   `VARYING` condition on the loopback edge. Error exits and abend paths
>   MUST be drawn explicitly.
> - Use Mermaid `flowchart TD` for batch programs, `sequenceDiagram` for
>   CICS conversations with the terminal user, `stateDiagram-v2` for
>   pseudo-conversational lifecycles.
> - Inner-section flow diagrams (per-paragraph `IF` / `EVALUATE` /
>   loop / I/O verbs) belong to the matching `section-doc.md` pages, NOT
>   here. Do not duplicate them.
> - **Every diagram MUST be followed by exactly one italicised caption
>   line `*Figure N — <business-language description>.*`** (single
>   sentence, ≤ 25 words, target language of the document, sequential
>   numbering starting at 1).
> - **Forbidden:** `[Open in Draw.io](...)` / `app.diagrams.net` links,
>   trivial `Enter → Body → Exit` placeholders.

## Declaratives
{{DECLARATIVES_NARRATIVE}}

> Authoring rules (binding):
> - Use the explicit sentence _"This program declares no `DECLARATIVES`
>   section."_ when absent (common in batch programs).
> - When present, describe each `USE` procedure: the event that triggers
>   it (`USE AFTER STANDARD ERROR PROCEDURE ON FILE-1`, `USE BEFORE
>   REPORTING REPORT-1`, `USE FOR DEBUGGING ON ALL PROCEDURES`), the
>   resource it covers, and the recovery / logging action it performs.
>   `DECLARATIVES` fire **implicitly** — they are a frequent source of
>   surprise during modernization because they have no explicit call
>   site in the mainline.

### `USE` procedures
| Procedure | Trigger | Covered resource | Action | Notes |
|-----------|---------|------------------|--------|-------|
{{#DECLARATIVES_TABLE}}
| `{{DECL_NAME}}` | {{DECL_TRIGGER}} | `{{DECL_RESOURCE}}` | {{DECL_ACTION}} | {{DECL_NOTES}} |
{{/DECLARATIVES_TABLE}}
{{^DECLARATIVES_TABLE}}
| _No `DECLARATIVES` section declared._ | — | — | — | — |
{{/DECLARATIVES_TABLE}}

## Call graph (outbound)
{{CALL_GRAPH_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences (or the explicit sentence _"This program issues
>   no external `CALL`, `EXEC CICS LINK` or `EXEC CICS XCTL`."_ when
>   absent).
> - Distinguish **static** calls (`CALL 'PGMNAME'`, resolvable at link
>   time) from **dynamic** calls (`CALL WS-PGM-NAME`, resolved at run
>   time from a working-storage variable) — the latter are major
>   migration risks because the target program cannot be discovered by
>   static analysis.
> - For CICS programs, separate `LINK` (caller resumes after callee
>   returns, COMMAREA shared) from `XCTL` (control passes irrevocably,
>   no return) — they have different process-state implications.

### Outbound calls
| Kind | Target | Resolution | Parameters / COMMAREA | Call sites | Notes |
|------|--------|------------|------------------------|------------|-------|
{{#CALL_TABLE}}
| {{CALL_KIND}} | `{{CALL_TARGET}}` | {{CALL_RESOLUTION}} | `{{CALL_PARAMS}}` | {{CALL_SITES}} | {{CALL_NOTES}} |
{{/CALL_TABLE}}
{{^CALL_TABLE}}
| _No outbound calls detected._ | — | — | — | — | — |
{{/CALL_TABLE}}

> `Kind` is one of `CALL`, `CALL …  ON EXCEPTION`, `EXEC CICS LINK`,
> `EXEC CICS XCTL`, `EXEC CICS START`, `ENTRY` (when the program
> exposes a secondary entry-point). `Resolution` is one of `static`
> (literal program name), `dynamic` (working-storage variable —
> source the variable name and any known values), `unresolved`
> (cannot be determined).

## External I/O surface
{{EXTERNAL_IO_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences summarising every external resource the
>   division touches at run-time: sequential / VSAM files
>   (`OPEN` / `READ` / `WRITE` / `REWRITE` / `DELETE` / `START` /
>   `CLOSE`), DB2 tables (`EXEC SQL SELECT / INSERT / UPDATE / DELETE /
>   FETCH / OPEN CURSOR / CLOSE CURSOR / COMMIT / ROLLBACK`), CICS
>   resources (TS / TD queues, BMS maps, journals, files,
>   `START TRANSID`), MQ queues, screens.
> - Group by **resource**, not by verb: _"`MASTER-IN` is opened
>   `INPUT` in `0000-INIT`, read sequentially in `1000-PROCESS` until
>   end-of-file, and closed in `9000-CLEANUP`"_ is more useful than a
>   raw verb tally.

### I/O verbs by resource
| Resource | Kind | Verbs used | Sections that use it | Notes |
|----------|------|------------|----------------------|-------|
{{#IO_VERBS_TABLE}}
| `{{IO_RESOURCE}}` | {{IO_KIND}} | {{IO_VERBS}} | {{IO_SECTIONS}} | {{IO_NOTES}} |
{{/IO_VERBS_TABLE}}
{{^IO_VERBS_TABLE}}
| _Division performs no external I/O._ | — | — | — | — |
{{/IO_VERBS_TABLE}}

> `Kind` is one of `FILE` (sequential / VSAM / SORT), `DB2-TABLE`,
> `DB2-CURSOR`, `CICS-TS-QUEUE`, `CICS-TD-QUEUE`, `CICS-FILE`,
> `CICS-MAP`, `MQ-QUEUE`, `PRINTER`, `CONSOLE`. `Verbs used` is the
> set of distinct verbs in source order (e.g. `OPEN, READ, CLOSE`).

## Risky and forbidden constructs
{{RISKY_CONSTRUCTS_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences (or the explicit sentence _"No risky constructs
>   detected across the division."_ when none are present).
> - Enumerate every occurrence of a construct that materially harms
>   migration: `ALTER`, `GO TO DEPENDING ON`, `GO TO` jumping out of a
>   `PERFORM` range, dynamic `CALL identifier`, recursive `PERFORM`
>   (direct or indirect), `EXEC CICS HANDLE CONDITION` / `HANDLE AID`
>   (implicit control transfer), `ENTRY` statements (multiple
>   entry-points), `NOT ON EXCEPTION` blocks larger than three verbs,
>   `EXEC CICS RETURN` from outside the mainline.
> - Each occurrence MUST cite the source range with `[^src-N]` and link
>   to the section-doc that contains it.

### Inventory
| Construct | Location | Risk | Notes |
|-----------|----------|------|-------|
{{#RISKY_TABLE}}
| `{{RISKY_KIND}}` | `{{RISKY_LOCATION}}` | {{RISKY_LEVEL}} | {{RISKY_NOTES}} |
{{/RISKY_TABLE}}
{{^RISKY_TABLE}}
| _None detected._ | — | — | — |
{{/RISKY_TABLE}}

> `Risk` is one of `low`, `medium`, `high`, `blocker`. `Location` is the
> section or paragraph name followed by the source citation; the
> `section-doc.md` page for that section MUST also list the same item in
> its own _Warnings_ block.

## Termination contract
{{TERMINATION_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences. Describe how the program exits in nominal and
>   abnormal cases: `STOP RUN` (terminates the run unit), `GOBACK`
>   (returns to the caller, preserving the run unit), `EXIT PROGRAM`
>   (sub-program return), `EXEC CICS RETURN` (CICS task end, with or
>   without `TRANSID` for pseudo-conversational handoff), `MOVE … TO
>   RETURN-CODE` (JCL step return code), explicit `ABEND` /
>   `EXEC CICS ABEND`.
> - Map each exit path to the calling environment that observes it: JCL
>   step (return code drives `COND=` on downstream steps), CICS task
>   (transaction end), invoking program (return point after `CALL`).

### Exit points
| Exit verb | Location | Return code / commarea | Caller-visible effect | Notes |
|-----------|----------|------------------------|------------------------|-------|
{{#EXIT_TABLE}}
| `{{EXIT_VERB}}` | `{{EXIT_LOCATION}}` | `{{EXIT_VALUE}}` | {{EXIT_EFFECT}} | {{EXIT_NOTES}} |
{{/EXIT_TABLE}}
{{^EXIT_TABLE}}
| _No explicit exit verb detected (program falls off the end of the `PROCEDURE DIVISION`)._ | — | — | — | — |
{{/EXIT_TABLE}}

## Division documentation

### Business / operational context
{{BUSINESS_CONTEXT}}

> At least 3 sentences. Explain the business process the division
> implements, the actors it serves (batch scheduler, CICS terminal user,
> upstream / downstream programs), and the regulatory / contractual
> constraints it inherits (audit trail, idempotency, transactional
> atomicity, retention).

### Operational role in the wider system
{{OPERATIONAL_ROLE_NARRATIVE}}

> At least 3 sentences. Identify which job stream / transaction triggers
> this program, which programs it hands off to (via `XCTL`, `CALL`,
> downstream JCL steps), which datasets / tables / queues it produces
> for downstream consumers, and which failure modes propagate to the
> rest of the system (return code conventions, abend codes, MQ poison
> messages).

### Modernization implications
{{MODERNIZATION_NOTES}}

> At least 3 sentences. Map the division's shape to the target stack:
> mainline driver → `main()` / orchestrator class / Spring Batch job /
> Azure Function entry; `PERFORM` chains → method calls; `DECLARATIVES`
> → exception handlers / aspect interceptors; CICS pseudo-conversational
> state → session storage; dynamic `CALL` → reflection / strategy
> pattern with explicit registry; `GO TO` mesh → refactor into
> structured control flow. Flag every construct that has no
> declarative equivalent and therefore requires bespoke adapter code.

### Migration risks
| Dimension | Value | Source |
|-----------|-------|--------|
| Sections | {{SECTION_COUNT}} | `facts.json` |
| Top-level paragraphs | {{PARAGRAPH_COUNT}} | `facts.json` |
| `PERFORM` statements | {{PERFORM_COUNT}} | `facts.json` |
| `PERFORM THRU` statements | {{PERFORM_THRU_COUNT}} | `facts.json` |
| `GO TO` statements | {{GOTO_COUNT}} | `facts.json` |
| `GO TO` out of `PERFORM` range | {{GOTO_OUT_OF_RANGE_COUNT}} | `facts.json` |
| `GO TO DEPENDING ON` statements | {{GOTO_DEPENDING_COUNT}} | `facts.json` |
| `ALTER` statements | {{ALTER_COUNT}} | `facts.json` |
| Static `CALL` sites | {{STATIC_CALL_COUNT}} | `facts.json` |
| Dynamic `CALL` sites | {{DYNAMIC_CALL_COUNT}} | `facts.json` |
| `EXEC CICS LINK` / `XCTL` sites | {{CICS_LINK_XCTL_COUNT}} | `facts.json` |
| `EXEC SQL` statements | {{EXEC_SQL_COUNT}} | `facts.json` |
| `EXEC CICS` statements | {{EXEC_CICS_COUNT}} | `facts.json` |
| `DECLARATIVES` `USE` procedures | {{DECLARATIVES_COUNT}} | `facts.json` |
| `ENTRY` statements | {{ENTRY_COUNT}} | `facts.json` |
| Max paragraph cyclomatic complexity | {{MAX_COMPLEXITY}} | `facts.json` |
| Unreachable sections / paragraphs | {{UNREACHABLE_COUNT}} | `facts.json` |
| Migration risk | {{MIGRATION_RISK_LEVEL}} ({{MIGRATION_RISK_LEVEL_RATIONALE}}) | analyst |

> The numeric cells are mechanically lifted from `facts.json` — do NOT
> recompute or paraphrase them in the prose above. `MIGRATION_RISK_LEVEL`
> is one of `low`, `medium`, `high`, `blocker`; the rationale is a short
> clause (e.g. _"two dynamic `CALL` sites with no known target inventory"_,
> _"`ALTER` plus `GO TO DEPENDING ON` drive the dispatcher in
> `2000-DISPATCH`"_, _"recursive `PERFORM` between `3000-A` and `3000-B`"_).

## Cross-references

### Incoming callers (programs that invoke this one)
{{#XREF_CALLERS}}
- {{TYPE}}: `{{SOURCE_REF}}` — `{{SOURCE_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_CALLERS}}
{{^XREF_CALLERS}}
- _No caller detected in workspace (program is top-of-stack or callers live outside the analysed scope)._
{{/XREF_CALLERS}}

### Outgoing callees (programs this one invokes)
{{#XREF_CALLEES}}
- {{TYPE}}: `{{TARGET}}` — `{{TARGET_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_CALLEES}}
{{^XREF_CALLEES}}
- _None._
{{/XREF_CALLEES}}

### JCL / triggers that schedule this program
{{#XREF_JCL}}
- {{TYPE}}: `{{TARGET}}` — `{{TARGET_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_JCL}}
{{^XREF_JCL}}
- _No JCL or CICS trigger detected in workspace._
{{/XREF_JCL}}

### External dependencies (datasets / tables / queues / maps / programs)
{{#XREF_EXTERNAL}}
- {{KIND}}: `{{NAME}}` {{#NOTES}}— {{NOTES}}{{/NOTES}}
{{/XREF_EXTERNAL}}

## Dead / unreachable paragraphs
{{#DEAD_PARAGRAPHS}}
- ⚠️ **{{DEAD_KIND}}** `{{DEAD_NAME}}` (L{{DEAD_START}}–L{{DEAD_END}}) — {{DEAD_REASON}}
{{/DEAD_PARAGRAPHS}}
{{^DEAD_PARAGRAPHS}}
- No unreachable sections or paragraphs detected.
{{/DEAD_PARAGRAPHS}}

> A section / paragraph is unreachable when no `PERFORM`, `GO TO`,
> `DECLARATIVES` binding, `ENTRY` declaration or program entry-point
> can transfer control to it. Detail on **what** the unreachable code
> contains lives in the matching `section-doc.md` page — this listing
> is the division-level inventory.

## Warnings
{{#WARNINGS}}
- ⚠️ {{WARNING}}
{{/WARNINGS}}
{{^WARNINGS}}
- _No warnings raised for this division._
{{/WARNINGS}}

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
_No citations emitted — the narrative above must therefore contain no `[^src-N]` markers._
{{/CITATIONS}}

---

<!-- Authoring self-check. MUST be evaluated by the generator before emitting
     the document; any unchecked box is a hard failure surfaced in the lint
     report. Do NOT delete this block — it is the contract that keeps the
     narrative honest. -->

### Authoring self-check
- [ ] Summary is a single operations-language sentence, ≤ 30 words, no COBOL jargon.
- [ ] Purpose ≥ 4 sentences and avoids any forbidden textbook opener.
- [ ] `Header and linkage contract` is present and every `PROCEDURE DIVISION
      USING` item from `bundle.facts_slice` appears in the `USING` table with
      its passing mode and at least one caller (or explicitly marked as having
      no caller in the analysed scope).
- [ ] `Section and paragraph inventory` table lists every top-level
      section / paragraph from `bundle.facts_slice`, with a working link to
      the matching `section-doc.md` page.
- [ ] `Mainline control flow` narrative stays at the section level (no
      per-paragraph verb walks) and the Mermaid diagram shows the driver
      loop with its termination condition and the nominal vs. error exits.
- [ ] Every Mermaid diagram is immediately followed by an italicised caption
      line `*Figure N — <description>.*` with sequential figure numbering
      starting at 1.
- [ ] `Declaratives`, `Call graph`, `External I/O surface`, `Risky and
      forbidden constructs` and `Termination contract` sections each carry
      a narrative — present-and-described or explicitly marked absent — and
      their tables match `bundle.facts_slice`.
- [ ] Every dynamic `CALL`, every `GO TO` out of `PERFORM` range, every
      `ALTER` and every `ENTRY` statement in `bundle.facts_slice` appears in
      the `Risky and forbidden constructs` inventory with a `[^src-N]`
      citation.
- [ ] Every `[^src-N]` marker in the body has a matching definition under
      _Citations_; every definition is actually referenced.
- [ ] No `[FILE:Lx-Ly]` inline tags, no `app.diagrams.net` / Draw.io links,
      no "self-contained document / bundles facts.json" banner, no
      per-section behavioural narrative (`Detailed behaviour`, `Examples`,
      `Edge cases`, `Variables read/written`, `Side effects` — those
      belong to `section-doc.md`, not here).
- [ ] `Migration risks` cells match `bundle.facts_slice` byte-for-byte
      (counts are sourced from the slice; the same values were emitted by
      the file-level `facts.json` extractor).
