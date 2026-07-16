# {{SECTION_NUMBER}}. {{SECTION_NAME}}

> **Source file:** `{{SOURCE_PATH}}` · **Chunk kind:** {{CHUNK_KIND}} · **Parent:** {{PARENT_NAME}} · **Reachability:** {{REACHABILITY}}

<!-- Provenance (line range, FD counts, 01-level counts, COPY/REPLACING counts,
     REDEFINES / OCCURS DEPENDING ON counts, EXTERNAL / GLOBAL items, DCLGEN
     includes) is recorded in facts.json and in the source citation footnotes;
     do NOT surface it as a header banner or as narrative filler. The reader
     needs to understand WHICH data structures the program manipulates and HOW
     they bind to files, callers, copybooks and DCLGENs — not how many lines or
     declarations the division contains. See
     .github/instructions/no-generator-boilerplate.instructions.md — the
     "Self-contained document. Bundles… from facts.json…" banner that used to
     live here is FORBIDDEN and must NEVER be re-introduced. -->

## Summary
{{TLDR_ONE_LINER}}

> Authoring rules (binding):
> - Exactly **one sentence**, ≤ 30 words, written in business / operations
>   language.
> - Must answer: _"Which data structures does this program declare and how do
>   they bind to files, callers, copybooks and DCLGENs?"_
> - **FORBIDDEN:** COBOL jargon (`WORKING-STORAGE`, `PIC`, `COMP-3`,
>   `REDEFINES`, `OCCURS`), record counts, byte counts, or restating the
>   division name. No citations here — the Summary is a hook, not a claim; full
>   evidence lives in the sections below.

## Purpose
{{PURPOSE_PARAGRAPH}}

> Authoring rules (binding):
> - At least 4 full sentences (≈ 80–120 words) focused on **what the division
>   declares** — i.e. the file record layouts, the working-storage state
>   machine, the linkage contract with callers, the copybooks and DCLGENs that
>   carry shared definitions — not on what a DATA DIVISION **is** in the
>   abstract.
> - **FORBIDDEN OPENERS:** "The `DATA DIVISION` describes the data used by the
>   program…", "The DATA DIVISION is one of the four canonical COBOL
>   divisions…", or any equivalent textbook-style definition. Always pivot to
>   the concrete content: _"This division lays out the customer master record
>   `WS-CUST-REC` shared with copybook `AXAE001C`, the transaction record
>   `TRN-IN-REC` consumed from `TRANS-IN`, and the linkage area
>   `LK-COMMAREA` through which the CICS caller passes the operation code and
>   the customer key…"_.
> - Write **discursively**: group related declarations (file records,
>   accumulators, flags, lookup tables, linkage parameters) into coherent
>   paragraphs. Do NOT walk the source 01-level after 01-level.
> - Identify the **data responsibility** of the division: which records carry
>   the business payload, which working-storage areas hold the in-flight
>   state, which structures are shared via `EXTERNAL` / `GLOBAL`, which
>   linkage items form the call contract.
> - **FORBIDDEN:** sentences that report line counts, record counts, byte
>   counts, or any other structural statistic. Those facts live in
>   `facts.json` and in citation footnotes — never in prose.
> - Cite source ranges using the Pandoc-footnote form `[^src-N]` (see
>   `citations-and-confidence.instructions.md`); never inline `[FILE:Lx-Ly]`
>   tags.

## File section
{{FILE_SECTION_NARRATIVE}}

> Authoring rules (binding):
> - At least 4 sentences (or the explicit sentence _"This program declares no
>   `FILE SECTION`."_ when the section is genuinely absent — typical for
>   sub-programs invoked via `CALL` that own no file).
> - For each `FD` / `SD` describe the role of the file in the business
>   process, the matching `SELECT` from the ENVIRONMENT DIVISION, the
>   `BLOCK CONTAINS` / `RECORD CONTAINS` / `LABEL RECORDS` /
>   `DATA RECORD IS` / `RECORDING MODE` clauses, and the record layouts
>   declared underneath.
> - Highlight **variable-length records** (`OCCURS … DEPENDING ON` inside an
>   FD record), `REDEFINES` over an FD record (multi-format files), and
>   record areas shared between several files via `SAME RECORD AREA` —
>   these are migration risks.

### FD / SD entries
| Logical file | `SELECT` binding | Record name(s) | Record length | Format | Notes |
|--------------|------------------|----------------|---------------|--------|-------|
{{#FD_TABLE}}
| `{{FD_LOGICAL_NAME}}` | `{{FD_SELECT}}` | `{{FD_RECORDS}}` | {{FD_LENGTH}} | {{FD_FORMAT}} | {{FD_NOTES}} |
{{/FD_TABLE}}
{{^FD_TABLE}}
| _No `FD` / `SD` entries declared._ | — | — | — | — | — |
{{/FD_TABLE}}

> `Format` is one of `FIXED`, `VARIABLE` (driven by `OCCURS … DEPENDING ON`),
> `MULTI-FORMAT` (driven by `REDEFINES` on the record), `SORT` (for `SD`).
> The `SELECT binding` column MUST point to the matching `SELECT` clause from
> the ENVIRONMENT DIVISION; flag _orphan_ FDs (no matching `SELECT`) and
> _orphan_ `SELECT`s (no matching `FD`) in the _Dead / unused declarations_
> section below.

## Working-Storage section
{{WORKING_STORAGE_NARRATIVE}}

> Authoring rules (binding):
> - At least 4 sentences (or the explicit sentence _"This program declares no
>   `WORKING-STORAGE SECTION`."_ when absent).
> - Group 01-level items by **role** — control flags (`WS-EOF-FLAG`,
>   `WS-RETURN-CODE`), counters and accumulators (`WS-TOT-IN`,
>   `WS-TOT-OUT`), in-memory lookup tables (`WS-T22-TABLE` with `OCCURS`),
>   work records mirroring file records, host-variable structures for DB2 —
>   rather than walking the source top-to-bottom.
> - Call out every structure that **constrains modernization**:
>   `COMP-3` / `PACKED-DECIMAL` fields (numeric base-10 semantics),
>   `COMP` / `BINARY` fields (host endianness), `POINTER` / `PROCEDURE-POINTER`
>   usage, `EXTERNAL` items (process-wide shared state), `GLOBAL` items
>   (nested-program visibility), `OCCURS … DEPENDING ON` (variable layout),
>   `REDEFINES` (memory aliasing), `66` / `77` / `88` levels.
> - Cite every claim with `[^src-N]` markers anchored to the relevant
>   declaration.

### 01-level inventory (Working-Storage)
| 01-level name | Role | Origin | Size (bytes) | Notable clauses | Notes |
|---------------|------|--------|--------------|-----------------|-------|
{{#WS_RECORD_TABLE}}
| `{{WS_NAME}}` | {{WS_ROLE}} | {{WS_ORIGIN}} | {{WS_BYTES}} | {{WS_CLAUSES}} | {{WS_NOTES}} |
{{/WS_RECORD_TABLE}}
{{^WS_RECORD_TABLE}}
| _No 01-level items declared in `WORKING-STORAGE`._ | — | — | — | — | — |
{{/WS_RECORD_TABLE}}

> `Role` is one of `flag`, `counter`, `accumulator`, `lookup-table`,
> `work-record`, `host-variables`, `commarea`, `constants`, `other`.
> `Origin` is `inline` when declared in this source, or the copybook /
> DCLGEN name (e.g. `COPY AXAE001C` / `EXEC SQL INCLUDE DCLCUST`) when
> pulled in. `Notable clauses` lists `REDEFINES`, `OCCURS`,
> `OCCURS … DEPENDING ON`, `EXTERNAL`, `GLOBAL`, `VALUE`, `USAGE` (only
> when non-`DISPLAY`).

## Local-Storage section
{{LOCAL_STORAGE_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences (or the explicit sentence _"This program declares no
>   `LOCAL-STORAGE SECTION`."_ when absent — this is the common case for
>   batch programs).
> - When present, explain why per-invocation lifetime matters here:
>   recursive `CALL`, re-entrant CICS programs, multi-threaded callers, or
>   nested programs that must not leak state between activations. List the
>   structures declared and the initial `VALUE` each one assumes on every
>   entry.

### 01-level inventory (Local-Storage)
| 01-level name | Role | Origin | Size (bytes) | Initial value | Notes |
|---------------|------|--------|--------------|---------------|-------|
{{#LS_RECORD_TABLE}}
| `{{LS_NAME}}` | {{LS_ROLE}} | {{LS_ORIGIN}} | {{LS_BYTES}} | {{LS_VALUE}} | {{LS_NOTES}} |
{{/LS_RECORD_TABLE}}
{{^LS_RECORD_TABLE}}
| _No `LOCAL-STORAGE SECTION` declared._ | — | — | — | — | — |
{{/LS_RECORD_TABLE}}

## Linkage section
{{LINKAGE_NARRATIVE}}

> Authoring rules (binding):
> - At least 4 sentences (or the explicit sentence _"This program declares no
>   `LINKAGE SECTION`."_ when absent — typical for top-of-stack batch
>   programs invoked directly by the JCL `EXEC PGM=`).
> - Describe the **call contract**: which 01-level items are passed by the
>   caller, in which order they appear in `PROCEDURE DIVISION USING`,
>   whether each is `BY REFERENCE` (default), `BY CONTENT` or `BY VALUE`,
>   which item carries the CICS `COMMAREA` / `DFHCOMMAREA`, which is
>   `RETURNING` for function-style calls. Flag every implicit assumption
>   the caller MUST honour (record length, code page, alignment).
> - Map each linkage item to the **calling programs** discovered in the
>   workspace and to the matching `EXEC CICS LINK COMMAREA(…)` /
>   `CALL 'X' USING …` sites; cite them with `[^src-N]`.

### Linkage items
| 01-level name | Position in `USING` | Passing mode | Size (bytes) | Caller(s) | Notes |
|---------------|---------------------|--------------|--------------|-----------|-------|
{{#LK_TABLE}}
| `{{LK_NAME}}` | {{LK_POSITION}} | {{LK_MODE}} | {{LK_BYTES}} | {{LK_CALLERS}} | {{LK_NOTES}} |
{{/LK_TABLE}}
{{^LK_TABLE}}
| _No `LINKAGE SECTION` declared._ | — | — | — | — | — |
{{/LK_TABLE}}

> `Passing mode` is one of `BY REFERENCE`, `BY CONTENT`, `BY VALUE`,
> `RETURNING`, `COMMAREA` (when the item is the CICS `DFHCOMMAREA`).
> `Position` is the 1-based index in the `PROCEDURE DIVISION USING` list, or
> `commarea` for the implicit CICS area.

## Report section
{{REPORT_SECTION_NARRATIVE}}

> Authoring rules (binding):
> - Use the explicit sentence _"This program declares no `REPORT SECTION`."_
>   when absent (the common case).
> - When present, describe the `RD` entries, the `CONTROL IS …` hierarchy,
>   the `PAGE LIMIT` layout, and the report groups (`TYPE IS REPORT HEADING`,
>   `PAGE HEADING`, `CONTROL HEADING`, `DETAIL`, `CONTROL FOOTING`,
>   `PAGE FOOTING`, `REPORT FOOTING`). Map each `RD` to the file declared in
>   the `FILE SECTION` via `REPORT IS`.

## Screen section
{{SCREEN_SECTION_NARRATIVE}}

> Authoring rules (binding):
> - Use the explicit sentence _"This program declares no `SCREEN SECTION`."_
>   when absent (the common case — batch programs and CICS programs that
>   rely on BMS / MFS maps do not use `SCREEN SECTION`).
> - When present, describe the screen groups (`AUTO`, `SECURE`, `REQUIRED`,
>   `FULL`, `LINE`, `COLUMN`, `FOREGROUND-COLOR`, `BACKGROUND-COLOR`,
>   `HIGHLIGHT`, `REVERSE-VIDEO`) and the `ACCEPT` / `DISPLAY` verbs that
>   render them.

## Copybooks and DCLGENs
{{COPYBOOK_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences (or the explicit sentence _"This program includes
>   no `COPY` or `EXEC SQL INCLUDE` statements."_ when absent).
> - Describe **what each copybook / DCLGEN contributes**: a shared record
>   layout, a host-variable structure for a DB2 table, a CICS commarea
>   contract, a BMS map symbolic, a set of `88`-level codes. Call out
>   `COPY … REPLACING …` substitutions — they change identifier names and
>   are a frequent source of cross-program inconsistency.
> - Flag DCLGENs whose underlying DB2 table is also touched by `EXEC SQL`
>   statements in the PROCEDURE DIVISION; flag copybooks shared with
>   programs outside this source (cross-program contracts).

### Inclusion inventory
| Member | Kind | Section | `REPLACING` | Provides | Notes |
|--------|------|---------|-------------|----------|-------|
{{#COPYBOOK_TABLE}}
| `{{CB_MEMBER}}` | {{CB_KIND}} | {{CB_SECTION}} | {{CB_REPLACING}} | {{CB_PROVIDES}} | {{CB_NOTES}} |
{{/COPYBOOK_TABLE}}
{{^COPYBOOK_TABLE}}
| _No `COPY` or `EXEC SQL INCLUDE` statements detected._ | — | — | — | — | — |
{{/COPYBOOK_TABLE}}

> `Kind` is one of `COPY`, `COPY REPLACING`, `EXEC SQL INCLUDE` (DCLGEN),
> `EXEC CICS … COPY` (BMS symbolic). `Section` is the DATA DIVISION section
> that owns the inclusion (`FILE`, `WORKING-STORAGE`, `LOCAL-STORAGE`,
> `LINKAGE`, `REPORT`, `SCREEN`). `Provides` is a short business-language
> description of the structure pulled in (e.g. _"Customer master record
> shared with DEMO200, DEMO300"_, _"Host-variables for table `TCUSTOMER`"_).

## Division documentation

### Business / operational context
{{BUSINESS_CONTEXT}}

> At least 3 sentences. Explain which business entities the declared records
> represent (customer master, transaction log, accounting line, audit
> trail, …), which upstream systems populate them, which downstream systems
> consume them, and which regulatory / contractual constraints they inherit
> (PII fields, financial amounts subject to rounding rules, retention
> classes).

### Data ownership and sharing
{{DATA_OWNERSHIP_NARRATIVE}}

> At least 3 sentences. Identify which records this program **owns**
> (creates / updates), which it merely **reads**, and which it **shares**
> with other programs via `EXTERNAL` items, copybooks, DCLGEN-backed DB2
> tables, or CICS commareas. Highlight every cross-program contract — these
> are the boundaries the modernization plan must preserve.

### Memory and storage layout
{{MEMORY_LAYOUT_NARRATIVE}}

> At least 3 sentences. Summarise the total declared footprint per section
> (`FILE`, `WORKING-STORAGE`, `LOCAL-STORAGE`, `LINKAGE`), call out the
> largest records, the deepest `OCCURS` tables (and any
> `OCCURS … DEPENDING ON` whose maximum allocates a substantial buffer),
> and flag every `USAGE` other than `DISPLAY` (`COMP`, `COMP-3`, `COMP-4`,
> `COMP-5`, `POINTER`, `INDEX`) because each one carries a host-platform
> assumption (endianness, packed-decimal arithmetic, native word size).

### Preconditions on declared data
{{#PRECONDITIONS}}
- {{PRECONDITION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/PRECONDITIONS}}
{{^PRECONDITIONS}}
- _None — the division makes no assumption beyond the compiler defaults._
{{/PRECONDITIONS}}

> Every state the caller, the JCL, or the runtime MUST guarantee for the
> declared structures to be meaningful: linkage items populated to the
> documented length and code page, `EXTERNAL` items initialised by another
> program in the run unit, copybook versions matching the producer's
> contract, DCLGEN aligned with the live DB2 catalogue. Each item is a
> single declarative sentence with a `[^src-N]` citation when evidence
> exists.

### Modernization implications
{{MODERNIZATION_NOTES}}

> At least 3 sentences. Map each declaration class to its replacement in the
> target stack: fixed-length file records → typed DTO / Avro / Protobuf
> schema; `COMP-3` decimals → `BigDecimal` / `decimal` with explicit scale;
> `OCCURS` tables → `List<>` / arrays with bounds; `REDEFINES` → tagged
> unions or explicit deserialization branches; `EXTERNAL` items → shared
> singleton service / cache; CICS commarea → request DTO; DCLGEN host
> variables → JPA / Entity Framework / Dapper row types. Flag every
> declaration that cannot be expressed declaratively in the target stack
> and therefore needs custom adapter code.

### Migration risks
| Dimension | Value | Source |
|-----------|-------|--------|
| `FD` / `SD` count | {{FD_COUNT}} | `facts.json` |
| 01-level records (all sections) | {{RECORD_COUNT}} | `facts.json` |
| `REDEFINES` clauses | {{REDEFINES_COUNT}} | `facts.json` |
| `OCCURS … DEPENDING ON` clauses | {{ODO_COUNT}} | `facts.json` |
| `EXTERNAL` / `GLOBAL` items | {{EXTERNAL_COUNT}} | `facts.json` |
| `COMP-3` / `PACKED-DECIMAL` items | {{COMP3_COUNT}} | `facts.json` |
| `COMP` / `BINARY` items | {{COMP_COUNT}} | `facts.json` |
| `POINTER` / `PROCEDURE-POINTER` items | {{POINTER_COUNT}} | `facts.json` |
| `COPY` / DCLGEN inclusions | {{COPY_COUNT}} | `facts.json` |
| Migration risk | {{MIGRATION_RISK_LEVEL}} ({{MIGRATION_RISK_LEVEL_RATIONALE}}) | analyst |

> The numeric cells are mechanically lifted from `facts.json` — do NOT
> recompute or paraphrase them in the prose above. `MIGRATION_RISK_LEVEL`
> is one of `low`, `medium`, `high`, `blocker`; the rationale is a short
> clause (e.g. _"`OCCURS DEPENDING ON` on linkage record drives 64 KB
> commarea"_, _"`EXTERNAL` accumulator shared with DEMO300 has no obvious
> owner"_, _"`REDEFINES` over FD record with conflicting `PIC`"_).

## Cross-references

### File-Control bindings (`SELECT` ↔ `FD`)
{{#XREF_FD_SELECT}}
- `FD {{FD_NAME}}` ↔ `SELECT {{SELECT_NAME}}` — `{{ENV_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_FD_SELECT}}
{{^XREF_FD_SELECT}}
- _No `FD` ↔ `SELECT` bindings detected (program owns no file)._
{{/XREF_FD_SELECT}}

### Procedure paragraphs that read / write the declared records
{{#XREF_CONSUMERS}}
- {{TYPE}}: `{{TARGET}}` — `{{TARGET_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_CONSUMERS}}
{{^XREF_CONSUMERS}}
- _None — declared records are not referenced anywhere in this program (potential dead declaration)._
{{/XREF_CONSUMERS}}

### Calling programs (consumers of the `LINKAGE SECTION`)
{{#XREF_CALLERS}}
- {{TYPE}}: `{{SOURCE_REF}}` — `{{SOURCE_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_CALLERS}}
{{^XREF_CALLERS}}
- _No caller detected in workspace (program is top-of-stack or callers live outside the analysed scope)._
{{/XREF_CALLERS}}

### External dependencies (copybooks / DCLGENs / DB2 tables / BMS maps / commareas)
{{#XREF_EXTERNAL}}
- {{KIND}}: `{{NAME}}` {{#NOTES}}— {{NOTES}}{{/NOTES}}
{{/XREF_EXTERNAL}}

### Workspace data lineage (other programs / JCL that share or bind these records)
| Record / layout | Sharing kind | Other source | Role at the other site | Notes |
|------------------|--------------|--------------|-------------------------|-------|
{{#XREF_DATA_LINEAGE}}
| `{{DL_RECORD}}` | {{DL_KIND}} | `{{DL_SOURCE}}` | {{DL_ROLE}} | {{DL_NOTES}} |
{{/XREF_DATA_LINEAGE}}
{{^XREF_DATA_LINEAGE}}
| _No record declared here is shared with another source in the workspace._ | — | — | — | — |
{{/XREF_DATA_LINEAGE}}

> `Sharing kind` ∈ `COPY` (same copybook included by another
> program), `DCLGEN` (same DB2 table host-variable area),
> `COMMAREA` (cross-program CICS contract), `FD-DSN` (same external
> dataset bound to an FD here and another `FD` / JCL `DD` elsewhere),
> `LINKAGE-USING` (the record is passed by a `CALL … USING`).
> `Role at the other site` ∈ `producer`, `consumer`, `shared-layout`,
> `caller`. Populate from the bundle's `incoming_xref[]` filtered by
> `via in {copy, jcl-step}`, plus the `data_records[].consumers[]`
> projection.

## Dead / unused declarations
{{#DEAD_DECLARATIONS}}
- ⚠️ **{{DEAD_KIND}}** `{{DEAD_NAME}}` (L{{DEAD_START}}–L{{DEAD_END}}) — {{DEAD_REASON}}
{{/DEAD_DECLARATIONS}}
{{^DEAD_DECLARATIONS}}
- No unused records, fields, `FD`s or copybook items detected.
{{/DEAD_DECLARATIONS}}

> A record / field is dead when no PROCEDURE DIVISION verb (`MOVE`, `READ`,
> `WRITE`, `COMPUTE`, `IF`, `CALL … USING`, `EXEC SQL`, `EXEC CICS`)
> references it. An `FD` is dead when no `SELECT` binds it (orphan FD) or
> when no `OPEN` / `READ` / `WRITE` / `CLOSE` ever touches its file (dead
> file). An `88`-level is dead when no condition test references it.
> Flag them so the modernization plan can drop the corresponding fields
> from the target schema.

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
- [ ] `File section` narrative is present (or explicitly states the section
      is absent) and every `FD` / `SD` from `bundle.facts_slice` appears in
      the `FD / SD entries` table with its matching `SELECT` binding.
- [ ] `Working-Storage`, `Local-Storage`, `Linkage`, `Report` and `Screen`
      sections each carry a narrative — present-and-described or explicitly
      marked absent — and every declared 01-level appears in the relevant
      inventory table.
- [ ] Every linkage item is mapped to at least one caller (or explicitly
      marked as having no caller in the analysed scope), with passing mode
      and position recorded.
- [ ] Every `COPY` / `EXEC SQL INCLUDE` / `COPY REPLACING` from
      `bundle.facts_slice` appears in the `Inclusion inventory` table with
      its target section and a business-language `Provides` description.
- [ ] Every `[^src-N]` marker in the body has a matching definition under
      _Citations_; every definition is actually referenced.
- [ ] No `[FILE:Lx-Ly]` inline tags, no `app.diagrams.net` / Draw.io links,
      no "self-contained document / bundles facts.json" banner, no
      procedural `Flow diagram` / `Variables read/written` / `Side effects`
      sections (those belong to the PROCEDURE DIVISION template, not here).
- [ ] `Migration risks` cells match `bundle.facts_slice` byte-for-byte
      (counts are sourced from the slice; the same values were emitted by
      the file-level `facts.json` extractor).
