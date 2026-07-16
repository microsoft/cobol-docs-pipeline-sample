# {{SECTION_NUMBER}}. {{SECTION_NAME}}

> **Source file:** `{{SOURCE_PATH}}` · **Chunk kind:** {{CHUNK_KIND}} · **Parent section:** {{PARENT_NAME}} · **01-level:** `{{RECORD_NAME}}`

<!-- Per-chunk deliverable for ONE 01-level data record (a single chunk of
     kind `data-record`). Whole-division narrative belongs in
     `data-division.template.md`; do NOT restate it here. Provenance (line
     range, child-field count, byte length, OCCURS depth, REDEFINES overlay
     count) is recorded in facts.json and in the citation footnotes; do NOT
     surface it as a header banner or as narrative filler. The reader needs
     to understand WHAT this record represents in the business domain, WHICH
     callers / files / DB2 tables / CICS commareas bind to it, and WHICH
     fields constrain the modernization plan. See
     .github/instructions/no-generator-boilerplate.instructions.md — the
     "Self-contained document. Bundles… from facts.json…" banner is
     FORBIDDEN. -->

## Summary
{{TLDR_ONE_LINER}}

> Authoring rules (binding):
> - Exactly **one sentence**, ≤ 30 words, written in business-domain
>   language.
> - Must answer: _"What does this record represent, and where does it
>   bind?"_
> - **FORBIDDEN:** COBOL jargon (`PIC`, `COMP-3`, `OCCURS`, `REDEFINES`,
>   `01-level`), field counts, byte counts, or restating the record name.
>   No citations here — the Summary is a hook; evidence lives below.

## Purpose
{{PURPOSE_PARAGRAPH}}

> Authoring rules (binding):
> - At least 4 full sentences (≈ 80–120 words) focused on **what this
>   record represents** — i.e. the business entity, the message envelope,
>   the file row, the DB2 host-variable structure, the CICS commarea —
>   not on what a COBOL 01-level **is** in the abstract.
> - **FORBIDDEN OPENERS:** "This 01-level declares the following
>   fields…", "The record spans lines X to Y and contains N elementary
>   items…", "This record is composed of the following sub-fields…".
>   Always pivot to the concrete business intent: _"This record carries
>   the customer master row read from `CUST-MASTER` and updated by the
>   nightly maintenance job; it holds the regulated identifiers
>   (`CUST-ID`, `CUST-VAT`), the balance accumulators, and the
>   last-activity timestamp used by the dormancy rule…"_.
> - Identify the **business responsibility** of the record (which
>   entity it represents, which lifecycle stage it captures).
> - Identify every **binding**: the matching `FD` / `SD` (when it is a
>   file record), the calling `PROCEDURE DIVISION USING` position (when
>   it is a linkage item), the DB2 table (when it is a DCLGEN
>   host-variable area), the CICS commarea contract (when it is a
>   `DFHCOMMAREA`).
> - **FORBIDDEN:** sentences that report line counts, field counts, byte
>   counts, or any other structural statistic. Those facts live in
>   `facts.json` and in citation footnotes — never in prose.
> - Cite source ranges using the Pandoc-footnote form `[^src-N]`
>   (see `citations-and-confidence.instructions.md`); never inline
>   `[FILE:Lx-Ly]` tags.

## Business context
{{BUSINESS_CONTEXT}}

> At least 3 sentences. Explain which business entity the record models,
> which upstream system populates it, which downstream system consumes
> it, and which regulatory / contractual constraints it inherits (PII
> fields, financial amounts subject to rounding rules, retention class,
> audit-trail requirement, idempotency contract).

## Record role and binding
{{ROLE_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences identifying the role of the record. Pick one
>   of: **file record** (declared under an `FD` / `SD` and bound to a
>   `SELECT`), **working-storage record** (in-flight state owned by
>   this program), **linkage record** (call contract — name the caller
>   position and passing mode), **DCLGEN host-variable area** (name the
>   DB2 table), **CICS commarea** (`DFHCOMMAREA`), **BMS symbolic map**
>   (name the mapset and map), **lookup table** (loaded at start-up,
>   read-only thereafter).
> - When the record is bound to an external resource, name that
>   resource explicitly (logical file name, DB2 table, mapset/map,
>   commarea contract) and cite the binding site with `[^src-N]`.

### Binding sites
| Kind | Binding | Direction | Caller / file / table | Notes |
|------|---------|-----------|------------------------|-------|
{{#BINDING_TABLE}}
| {{BIND_KIND}} | `{{BIND_NAME}}` | {{BIND_DIRECTION}} | `{{BIND_PARTNER}}` | {{BIND_NOTES}} |
{{/BINDING_TABLE}}
{{^BINDING_TABLE}}
| _No external binding — this record is private working-storage state._ | — | — | — | — |
{{/BINDING_TABLE}}

> `Kind` is one of `FD`, `SD`, `SELECT`, `USING`, `RETURNING`,
> `COMMAREA`, `DCLGEN`, `BMS-MAP`, `EXTERNAL`, `GLOBAL`, `COPY`.
> `Direction` is `IN`, `OUT`, `IN/OUT` or `—` (not applicable).

## Field layout
{{FIELD_LAYOUT_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences. Group fields by **role** — identifiers, business
>   payload, control flags, accumulators, filler / reserved areas, audit
>   timestamps — not by source order. Call out every field that constrains
>   the modernization plan: `COMP-3` / `PACKED-DECIMAL` (base-10
>   semantics), `COMP` / `BINARY` (host endianness), `POINTER` (raw
>   address), `OCCURS` (table cardinality), `OCCURS … DEPENDING ON`
>   (variable-length record), `REDEFINES` (memory aliasing), `88`-level
>   condition names (domain constraints).
> - Cite every claim with `[^src-N]` markers anchored to the relevant
>   declaration.

### Field inventory
| Level | Field name | PIC / USAGE | Role | OCCURS | REDEFINES | 88-levels | Notes |
|-------|------------|-------------|------|--------|-----------|-----------|-------|
{{#FIELD_TABLE}}
| {{F_LEVEL}} | `{{F_NAME}}` | `{{F_PIC}}` | {{F_ROLE}} | {{F_OCCURS}} | {{F_REDEFINES}} | {{F_COND_NAMES}} | {{F_NOTES}} |
{{/FIELD_TABLE}}
{{^FIELD_TABLE}}
| _No elementary fields declared._ | — | — | — | — | — | — | — |
{{/FIELD_TABLE}}

> `Role` is one of `identifier`, `payload`, `flag`, `counter`,
> `accumulator`, `timestamp`, `filler`, `reserved`, `index`,
> `host-variable-indicator`, `other`.

### Condition names (88-levels)
{{#COND_NAMES_DETAIL}}
- `{{COND_NAME}}` on `{{PARENT_FIELD}}` = `{{VALUES}}` → {{MEANING}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/COND_NAMES_DETAIL}}
{{^COND_NAMES_DETAIL}}
- _No 88-level condition names declared on this record._
{{/COND_NAMES_DETAIL}}

### Overlays (REDEFINES)
{{#REDEFINES_GROUPS}}
- `{{ORIGINAL}}` redefined by `{{ALIAS}}` → {{INTERPRETATION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/REDEFINES_GROUPS}}
{{^REDEFINES_GROUPS}}
- _No `REDEFINES` overlay on this record._
{{/REDEFINES_GROUPS}}

### Variable cardinality (OCCURS DEPENDING ON)
{{#OCCURS_DEPENDING}}
- `{{FIELD}}` `OCCURS 1..{{MAX}} DEPENDING ON {{COUNTER}}` — {{INTERPRETATION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/OCCURS_DEPENDING}}
{{^OCCURS_DEPENDING}}
- _No `OCCURS … DEPENDING ON` clause on this record._
{{/OCCURS_DEPENDING}}

## Usage in the program
{{USAGE_NARRATIVE}}

> At least 3 sentences. Identify the PROCEDURE DIVISION sections /
> paragraphs that **read** the record, those that **write** to it,
> those that **initialise** it (`INITIALIZE` / `MOVE … TO`), and the
> I/O verbs that move it across the boundary (`READ`, `WRITE`,
> `REWRITE`, `EXEC SQL FETCH … INTO`, `EXEC CICS RECEIVE MAP`,
> `CALL … USING`). Cite each site with `[^src-N]`.

### Read / write sites
| Site | Mode | Section / paragraph | Verb | Notes |
|------|------|---------------------|------|-------|
{{#USAGE_TABLE}}
| `{{U_SITE}}` | {{U_MODE}} | `{{U_OWNER}}` | `{{U_VERB}}` | {{U_NOTES}} |
{{/USAGE_TABLE}}
{{^USAGE_TABLE}}
| _No read / write site detected — potential dead declaration (see Warnings)._ | — | — | — | — |
{{/USAGE_TABLE}}

> `Mode` is one of `R`, `W`, `R/W`, `INIT`.

## Invariants and domain constraints
{{#INVARIANTS}}
- {{INVARIANT}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/INVARIANTS}}
{{^INVARIANTS}}
- _No invariant identified on this record._
{{/INVARIANTS}}

> Conditions that hold on every consistent instance of the record:
> referential keys, sign of numeric fields, valid code values
> (captured by `88`-levels), ordering of repeated groups, mutual
> exclusion between overlay variants.

## Cross-references

### Producers (write the record)
{{#XREF_PRODUCERS}}
- {{TYPE}}: `{{SOURCE_REF}}`{{#SOURCE_LINK}} ([`{{SOURCE_FILE_REF}}`]({{SOURCE_LINK}})){{/SOURCE_LINK}}{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_PRODUCERS}}
{{^XREF_PRODUCERS}}
- _No producer detected in workspace._
{{/XREF_PRODUCERS}}

### Consumers (read the record)
{{#XREF_CONSUMERS}}
- {{TYPE}}: `{{SOURCE_REF}}`{{#SOURCE_LINK}} ([`{{SOURCE_FILE_REF}}`]({{SOURCE_LINK}})){{/SOURCE_LINK}}{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_CONSUMERS}}
{{^XREF_CONSUMERS}}
- _No consumer detected in workspace._
{{/XREF_CONSUMERS}}

### Shared layout (copybook / DCLGEN inclusion)
{{#XREF_SHARED}}
- {{KIND}}: `{{MEMBER}}` included by {{#PROGRAMS}}`{{PROGRAM}}`{{^LAST}}, {{/LAST}}{{/PROGRAMS}}{{#REPLACING}} — `REPLACING {{REPLACING}}`{{/REPLACING}}
{{/XREF_SHARED}}
{{^XREF_SHARED}}
- _Layout is not shared via copybook or DCLGEN — declared inline only in this program._
{{/XREF_SHARED}}

## Modernization implications
{{MODERNIZATION_NOTES}}

> At least 2 sentences. Indicate how this record maps to the target
> stack (Java POJO / record, .NET DTO, Postgres row, JSON envelope) and
> the specific risks the migration inherits: packed-decimal arithmetic
> for `COMP-3` fields, endianness for `COMP` fields, variable-length
> serialisation for `OCCURS … DEPENDING ON`, overlay disambiguation
> for `REDEFINES`, cross-program contract preservation when the layout
> is shared via copybook / DCLGEN.

## Complexity and migration risk
| Dimension | Value | Source |
|-----------|-------|--------|
| Elementary field count | {{FIELD_COUNT}} | `facts.json` |
| Record length (bytes) | {{RECORD_BYTES}} | `facts.json` |
| `OCCURS` tables | {{OCCURS_COUNT}} | `facts.json` |
| `OCCURS … DEPENDING ON` count | {{ODO_COUNT}} | `facts.json` |
| `REDEFINES` overlays | {{REDEFINES_COUNT}} | `facts.json` |
| `88`-level condition names | {{COND_COUNT}} | `facts.json` |
| Non-`DISPLAY` usages | {{NON_DISPLAY_COUNT}} | `facts.json` |
| Shared via copybook / DCLGEN? | {{SHARED_LAYOUT}} | `facts.json` |
| Migration risk | {{MIGRATION_RISK_LEVEL}} ({{MIGRATION_RISK_LEVEL_RATIONALE}}) | analyst |

> Numeric cells are mechanically lifted from `facts.json` — do NOT
> recompute or paraphrase them in the prose above. `Shared via
> copybook / DCLGEN?` is `yes` / `no`. `MIGRATION_RISK_LEVEL` is one
> of `low`, `medium`, `high`, `blocker`; the rationale is a short
> clause (e.g. _"`OCCURS DEPENDING ON` requires variable-length
> serialisation"_, _"`REDEFINES` overlay disambiguated only at
> runtime"_, _"cross-program copybook shared with 4 programs"_).

## Warnings
{{#WARNINGS}}
- ⚠️ {{WARNING}}
{{/WARNINGS}}
{{^WARNINGS}}
- _No warnings raised for this record._
{{/WARNINGS}}

> Unused declaration (no read / write site), `REDEFINES` overlay whose
> variant is selected only at runtime, `OCCURS … DEPENDING ON` whose
> counter is set by an external system, copybook shared with programs
> outside the current workspace, and DCLGEN whose underlying DB2 table
> is also accessed by ad-hoc `EXEC SQL` statements MUST each surface a
> warning bullet here.

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
     report. Do NOT delete this block. -->

### Authoring self-check
- [ ] Summary is a single business-language sentence, ≤ 30 words, no COBOL jargon.
- [ ] Purpose ≥ 4 sentences and avoids any forbidden transcript opener.
- [ ] `Record role and binding` identifies the record's role and names every
      binding (FD/SELECT, USING position, DCLGEN table, COMMAREA, BMS map).
- [ ] `Field layout` groups fields by role; every `COMP-3` / `COMP` / `OCCURS`
      / `REDEFINES` / `88`-level is called out.
- [ ] `Field inventory` lists every elementary field in `bundle.facts_slice`
      with its PIC, role and notable clauses.
- [ ] `Usage in the program` names every read / write site in
      `bundle.facts_slice`; unused records are flagged in _Warnings_.
- [ ] Every `[^src-N]` marker in the body has a matching definition under
      _Citations_; every definition is actually referenced.
- [ ] No `[FILE:Lx-Ly]` inline tags, no `app.diagrams.net` / Draw.io
      links, no "self-contained document / bundles facts.json" banner.
- [ ] `Complexity and migration risk` cells match `bundle.facts_slice`
      byte-for-byte (counts are sourced from the slice; the same values
      were emitted by the file-level `facts.json` extractor).
