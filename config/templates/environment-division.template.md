# {{SECTION_NUMBER}}. {{SECTION_NAME}}

> **Source file:** `{{SOURCE_PATH}}` · **Chunk kind:** {{CHUNK_KIND}} · **Parent:** {{PARENT_NAME}} · **Reachability:** {{REACHABILITY}}

<!-- Provenance (line range, SELECT counts, SPECIAL-NAMES counts) is recorded in
     facts.json and in the source citation footnotes; do NOT surface it as a
     header banner or as narrative filler. The reader needs to understand WHICH
     runtime environment the program assumes and HOW logical resources bind to
     physical datasets / devices — not how many lines or clauses the division
     contains. See .github/instructions/no-generator-boilerplate.instructions.md
     — the "Self-contained document. Bundles… from facts.json…" banner that used
     to live here is FORBIDDEN and must NEVER be re-introduced. -->

## Summary
{{TLDR_ONE_LINER}}

> Authoring rules (binding):
> - Exactly **one sentence**, ≤ 30 words, written in business / operations language.
> - Must answer: _"Which runtime environment does this program assume and which
>   logical resources does it bind to physical datasets / devices?"_
> - **FORBIDDEN:** COBOL jargon (`SELECT`, `ASSIGN`, `SPECIAL-NAMES`), clause
>   counts, line counts, or restating the division name. No citations here — the
>   Summary is a hook, not a claim; full evidence lives in the sections below.

## Purpose
{{PURPOSE_PARAGRAPH}}

> Authoring rules (binding):
> - At least 4 full sentences (≈ 80–120 words) focused on **what the division
>   declares** — i.e. the runtime assumptions (compiler / target machine, locale,
>   collating sequence, currency sign, decimal point, switch mapping) and the
>   logical-to-physical file bindings — not on what an ENVIRONMENT DIVISION
>   **is** in the abstract.
> - **FORBIDDEN OPENERS:** "The `ENVIRONMENT DIVISION` is one of the four
>   canonical COBOL divisions…", "The ENVIRONMENT DIVISION describes the
>   environment in which the program runs…", or any equivalent textbook-style
>   definition. Always pivot to the concrete content: _"This division pins the
>   program to an IBM z/OS / Enterprise COBOL target, redefines the currency
>   sign to `€` for reporting, and binds five logical files — `MASTER-IN`,
>   `TRANS-IN`, `REPORT-OUT`, `ERROR-OUT`, `VSAM-CUST` — to the JCL DDs declared
>   in `DEMO1S00.INP`…"_.
> - Write **discursively**: group related clauses (locale settings, switches,
>   sequential files, indexed files) into coherent paragraphs. Do NOT walk the
>   source clause-after-clause.
> - Identify the **operational responsibility** of the division: which job
>   streams it ties the program to, which devices / datasets / printers it
>   presumes, and which platform-specific assumptions (EBCDIC collation,
>   mainframe currency conventions, ASCII switches) it bakes in.
> - **FORBIDDEN:** sentences that report line counts, clause counts, or any
>   other structural statistic. Those facts live in `facts.json` and in citation
>   footnotes — never in prose.
> - Cite source ranges using the Pandoc-footnote form `[^src-N]` (see
>   `citations-and-confidence.instructions.md`); never inline `[FILE:Lx-Ly]`
>   tags.

## Configuration section
{{CONFIGURATION_NARRATIVE}}

> Authoring rules (binding):
> - At least 4 sentences (or the explicit sentence _"This program declares no
>   `CONFIGURATION SECTION`."_ when the section is genuinely absent).
> - Describe — when present — the `SOURCE-COMPUTER` and `OBJECT-COMPUTER`
>   entries (target machine, `WITH DEBUGGING MODE`, segment-limit), and the
>   `SPECIAL-NAMES` paragraph (currency sign, decimal point, alphabet /
>   collating sequence, class definitions, symbolic characters, mnemonic names
>   for `SYSIN` / `SYSOUT` / `C01`–`C12`, console / printer, switch mappings
>   `UPSI-0…UPSI-7`, `CURSOR IS` / `CRT STATUS IS` for screen handling).
> - Call out every assumption that **constrains modernization**: EBCDIC
>   collation that changes sort order vs. ASCII, currency sign that affects
>   edited PIC strings, `DECIMAL-POINT IS COMMA` that flips the role of `.`
>   and `,`, switches whose runtime value is set by the JCL `PARM` / `EXEC`
>   step.
> - Cite every claim with `[^src-N]` markers anchored to the relevant clause.

### Configuration clauses
| Clause | Value | Effect on runtime / migration |
|--------|-------|-------------------------------|
{{#CONFIG_TABLE}}
| `{{CONFIG_CLAUSE}}` | `{{CONFIG_VALUE}}` | {{CONFIG_EFFECT}} |
{{/CONFIG_TABLE}}
{{^CONFIG_TABLE}}
| _No `CONFIGURATION SECTION` declared._ | — | — |
{{/CONFIG_TABLE}}

## Input-Output section
{{INPUT_OUTPUT_NARRATIVE}}

> Authoring rules (binding):
> - At least 4 sentences (or the explicit sentence _"This program declares no
>   `INPUT-OUTPUT SECTION`."_ when absent — typical for sub-programs invoked
>   via `CALL` that do not own any file).
> - Group files by **role in the business process** (master, transaction,
>   output, report, audit, VSAM lookup) rather than by clause order.
> - For each logical file describe its purpose, its physical binding (JCL DD or
>   environment variable referenced by `ASSIGN TO`), its organization
>   (sequential, indexed, relative), its access mode (sequential, random,
>   dynamic), and any declared `FILE STATUS` / `RECORD KEY` /
>   `ALTERNATE RECORD KEY` / `PASSWORD` / `LOCK MODE`.
> - Highlight **opaque bindings**: `ASSIGN TO WS-DD-NAME` style dynamic
>   assignments, `ASSIGN TO UT-S-…` mainframe device classes, two-stage
>   bindings that go through `SPECIAL-NAMES`. These are migration risks.

### File-Control (`SELECT` clauses)
| Logical file | `ASSIGN TO` | Organization | Access | Record key / Alt keys | `FILE STATUS` | Notes |
|--------------|-------------|--------------|--------|-----------------------|---------------|-------|
{{#FILE_CONTROL_TABLE}}
| `{{FC_LOGICAL_NAME}}` | `{{FC_ASSIGN}}` | {{FC_ORG}} | {{FC_ACCESS}} | {{FC_KEYS}} | `{{FC_STATUS}}` | {{FC_NOTES}} |
{{/FILE_CONTROL_TABLE}}
{{^FILE_CONTROL_TABLE}}
| _No `SELECT` clauses declared._ | — | — | — | — | — | — |
{{/FILE_CONTROL_TABLE}}

> `Organization` is one of `SEQUENTIAL`, `LINE SEQUENTIAL`, `INDEXED`,
> `RELATIVE`, `SORT`; `Access` is one of `SEQUENTIAL`, `RANDOM`, `DYNAMIC`.
> When `ASSIGN TO` resolves dynamically (e.g. `ASSIGN TO WS-DDNAME`), the cell
> MUST flag it with `(dynamic)` and the `Notes` column MUST point to the
> variable's definition.

### I-O-Control clauses
{{#IO_CONTROL_LIST}}
- **{{IOC_CLAUSE}}** — {{IOC_DESCRIPTION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/IO_CONTROL_LIST}}
{{^IO_CONTROL_LIST}}
- _No `I-O-CONTROL` paragraph declared._
{{/IO_CONTROL_LIST}}

> Capture `RERUN ON …`, `SAME [RECORD] AREA FOR …`, `MULTIPLE FILE TAPE …`,
> `APPLY WRITE-ONLY ON …`, `APPLY CORE-INDEX ON …` and any vendor-specific
> directive. Each entry has direct operational implications (checkpoint
> datasets, memory sharing between files, tape positioning) that the migration
> plan must replicate explicitly in the target stack.

## Division documentation

### Business / operational context
{{BUSINESS_CONTEXT}}

> At least 3 sentences. Explain the operational role of the resources declared
> here: which job stream / step opens the datasets, which downstream systems
> consume the outputs, which upstream feeds populate the inputs, which printer
> or terminal the program assumes.

### Runtime assumptions
{{RUNTIME_ASSUMPTIONS}}

> At least 4 sentences. List the assumptions baked into the division that a
> portable / re-platformed program would have to honour explicitly: target
> machine endianness and code page (EBCDIC vs. ASCII), collating sequence,
> currency and decimal conventions, switch-driven branches, console / printer
> availability, and any vendor extension (IBM `WITH DEBUGGING MODE`,
> `MEMORY SIZE`, `SEGMENT-LIMIT`, Micro Focus `ENVIRONMENT-NAME`, etc.).

### Logical-to-physical binding catalogue
{{BINDING_NARRATIVE}}

> Describe how each `SELECT … ASSIGN TO` resolves at run-time: static DD name,
> dynamic DD via working-storage, environment variable (`-ENV` / `EXTERNAL`),
> catalogued dataset, VSAM cluster, GDG generation, MQ queue exposed as a
> file, CICS-managed file. Cross-reference the JCL files in `repos/**/JCL/`
> that supply the DD statements; cite the matching `DD` cards with `[^src-N]`.

### Dataset / device inventory
| Logical name | Physical name (DD / dataset / device) | Provided by | Sensitivity | Modernization target |
|--------------|----------------------------------------|-------------|-------------|----------------------|
{{#DATASET_INVENTORY}}
| `{{DS_LOGICAL}}` | `{{DS_PHYSICAL}}` | {{DS_PROVIDER}} | {{DS_SENSITIVITY}} | {{DS_TARGET}} |
{{/DATASET_INVENTORY}}
{{^DATASET_INVENTORY}}
- _No datasets / devices declared in this division._
{{/DATASET_INVENTORY}}

> `Provided by` names the JCL step, catalogue entry, or operator action that
> materialises the dataset. `Sensitivity` is one of `public`, `internal`,
> `confidential`, `regulated` and feeds the security review. `Modernization
> target` proposes the equivalent resource in the destination stack (e.g.
> _"Azure Blob container `master-in`"_, _"Postgres table `customer_master`"_,
> _"Kafka topic `tx.in`"_).

### Preconditions on the runtime environment
{{#PRECONDITIONS}}
- {{PRECONDITION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/PRECONDITIONS}}
{{^PRECONDITIONS}}
- _None — the division makes no runtime assumption beyond the compiler defaults._
{{/PRECONDITIONS}}

> Every state the host platform, the JCL, or the operator MUST guarantee before
> the program runs: DDs allocated, VSAM clusters defined, printer mounted,
> switches set, code page configured, locale honoured. Each item is a single
> declarative sentence with a `[^src-N]` citation when evidence exists.

### Modernization implications
{{MODERNIZATION_NOTES}}

> At least 3 sentences. Map each declaration to its replacement in the target
> stack: sequential files → blob storage / object storage / mounted volumes;
> indexed files → relational tables or key-value stores; printer / console →
> structured logger; switches → feature flags / configuration; EBCDIC
> collation → explicit `Collator` configuration; currency / decimal locale →
> CLDR / ICU settings. Flag every binding that cannot be expressed
> declaratively in the target stack and therefore requires code in the adapter
> layer.

### Migration risks
| Dimension | Value | Source |
|-----------|-------|--------|
| `SELECT` clause count | {{SELECT_COUNT}} | `facts.json` |
| Dynamic `ASSIGN TO` clauses | {{DYNAMIC_ASSIGN_COUNT}} | `facts.json` |
| Indexed / VSAM files | {{VSAM_COUNT}} | `facts.json` |
| Locale-sensitive `SPECIAL-NAMES` clauses | {{LOCALE_CLAUSE_COUNT}} | `facts.json` |
| `I-O-CONTROL` directives | {{IOC_COUNT}} | `facts.json` |
| Migration risk | {{MIGRATION_RISK_LEVEL}} ({{MIGRATION_RISK_LEVEL_RATIONALE}}) | analyst |

> The numeric cells are mechanically lifted from `facts.json` — do NOT
> recompute or paraphrase them in the prose above. `MIGRATION_RISK_LEVEL` is
> one of `low`, `medium`, `high`, `blocker`; the rationale is a short clause
> (e.g. _"dynamic ASSIGN resolved at runtime through `WS-DDNAME`"_, _"VSAM
> alternate key with duplicates"_, _"`DECIMAL-POINT IS COMMA` flips edited
> PICs"_).

## Cross-references

### JCL / job streams that supply the DDs
{{#XREF_JCL}}
- {{TYPE}}: `{{TARGET}}` — `{{TARGET_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_JCL}}
{{^XREF_JCL}}
- _No JCL cross-reference detected in workspace._
{{/XREF_JCL}}

### Sections / paragraphs that consume the declared files
{{#XREF_CONSUMERS}}
- {{TYPE}}: `{{TARGET}}` — `{{TARGET_FILE}}`
{{/XREF_CONSUMERS}}
{{^XREF_CONSUMERS}}
- _None — declared files are not opened anywhere in this program (potential dead declaration)._
{{/XREF_CONSUMERS}}

### External dependencies (datasets / VSAM clusters / printers / queues)
{{#XREF_EXTERNAL}}
- {{KIND}}: `{{NAME}}` {{#NOTES}}— {{NOTES}}{{/NOTES}}
{{/XREF_EXTERNAL}}

## Dead / unused declarations
{{#DEAD_DECLARATIONS}}
- ⚠️ **{{DEAD_KIND}}** `{{DEAD_NAME}}` (L{{DEAD_START}}–L{{DEAD_END}}) — {{DEAD_REASON}}
{{/DEAD_DECLARATIONS}}
{{^DEAD_DECLARATIONS}}
- No unused `SELECT` or `SPECIAL-NAMES` entries detected.
{{/DEAD_DECLARATIONS}}

> A `SELECT` is dead when no `FD` references it; a `SPECIAL-NAMES` mnemonic is
> dead when no `DISPLAY UPON` / `WRITE … ADVANCING` / switch test references
> it. Flag them so the modernization plan can drop the corresponding adapters.

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
- [ ] `Configuration section` narrative is present (or explicitly states the
      section is absent) and every `SPECIAL-NAMES` clause from
      `bundle.facts_slice` appears in the `Configuration clauses` table.
- [ ] `Input-Output section` narrative is present (or explicitly states the
      section is absent) and every `SELECT` from `bundle.facts_slice` appears
      in the `File-Control` table with `ASSIGN TO`, organization, access mode
      and `FILE STATUS`.
- [ ] Every dynamic `ASSIGN TO` is flagged `(dynamic)` and cross-referenced to
      the working-storage variable that supplies the DD name.
- [ ] `Dataset / device inventory` is populated when at least one `SELECT`
      exists, with `Provided by` linking to the JCL step that allocates the
      DD.
- [ ] Every `[^src-N]` marker in the body has a matching definition under
      _Citations_; every definition is actually referenced.
- [ ] No `[FILE:Lx-Ly]` inline tags, no `app.diagrams.net` / Draw.io links, no
      "self-contained document / bundles facts.json" banner, no procedural
      `Flow diagram` / `Variables read/written` / `Side effects` sections
      (those belong to the PROCEDURE DIVISION template, not here).
- [ ] `Migration risks` cells match `bundle.facts_slice` byte-for-byte
      (counts are sourced from the slice; the same values were emitted by
      the file-level `facts.json` extractor).
