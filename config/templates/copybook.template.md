# Copybook — `{{COPYBOOK_NAME}}`

> **Source file:** `{{SOURCE_PATH}}` · **Top-level (01) records:** {{RECORD_COUNT}} · **Included by:** {{USED_BY_COUNT}} program(s) · **Kind:** {{COPYBOOK_KIND}}

<!-- File-level deliverable for ONE copybook member. A copybook has NO
     independent runtime existence — it is textually inlined by every
     including program at compile time, optionally rewritten by a
     `REPLACING` clause. The reader needs to understand WHAT shared
     contract this member carries, WHICH programs depend on it, WHETHER
     every including site sees the same inlined layout (or divergence
     introduced by `REPLACING`), and WHICH risks a change here would
     propagate.

     INPUT BINDINGS (from the per-chunk bundle JSON):
     - `bundle.facts_slice.records[]`                → 01-level inventory
       and per-record fields, 88-levels, REDEFINES, OCCURS / ODO.
     - `bundle.facts_slice.copybooks[]`              → nested `COPY`
       statements emitted from inside this copybook.
     - `bundle.facts_slice.incoming_xref[]`          → workspace-wide
      inverted edges (see `scripts/tools/xref-incoming-pass.py`). For this
       copybook only entries with `via == "copy"` are relevant; they
       drive the **Incoming xref** subsection below. The richer
       `Inclusion matrix` (with `REPLACING` clause and including-section)
       is authored from the caller-side `copybooks[]` arrays of each
       including program — the `incoming_xref` slice is the source of
       truth for *which* programs include this member; the matrix adds
       the per-call-site context.
     - `bundle.facts_slice.dclgen_table` (when set)  → DCLGEN binding to
       a DB2 table.
     - `bundle.facts_slice.bms_mapset` / `bms_map`   → BMS pairing.

     DIAGRAM OWNERSHIP (binding — do NOT duplicate diagram sources):
     - **Structure diagram** below embeds the file-level
       `docs/_shared/<copybook>/diagrams/er-fragment.mmd` produced by
       the `diagram-renderer` skill (for DCLGEN / business-entity
       copybooks). When that file does not exist AND the copybook has
       ≥ 1 `REDEFINES` overlay OR ≥ 1 `OCCURS … DEPENDING ON`,
       `section-doc-writer` MAY author the Mermaid inline (overlay /
       variable-length diagrams have no `diagram-renderer` kind).
       Otherwise leave the empty-state in place. The structure diagram
       is NEVER written to the per-chunk `bundle.output_paths.diagram`
       sidecar.
     - **Inclusion graph** below is authored inline by
       `section-doc-writer` and — because no `diagram-renderer` kind
       covers fan-in — is ALSO written verbatim to
       `bundle.output_paths.diagram` (the per-chunk `.mmd` sidecar) so
       phase D can render it to SVG. For copybook chunks the bundle
       MUST therefore set `diagram_kind = "flowchart LR"` and
       `output_paths.diagram = docs/_shared/<copybook>/diagrams/section-<chunk_id>.mmd`.
     - When the inclusion-graph gate is not met (< 2 includers and no
       `REPLACING` divergence), the sidecar `.mmd` is NOT emitted;
       `section-doc-writer` skips the diagram write for this chunk.

     Provenance (line range, field counts, byte length, OCCURS /
     REDEFINES counts, copybook search-path resolution) is recorded in
     `facts.json` and in the citation footnotes; do NOT surface it as a
     header banner or as narrative filler. See
     .github/instructions/no-generator-boilerplate.instructions.md —
     the "Self-contained document. Bundles… from facts.json…" banner
     is FORBIDDEN. Per-record (01-level) deep-dives belong in
     `data-record.template.md`; do NOT restate them here. -->

## Summary
{{TLDR_ONE_LINER}}

> Authoring rules (binding):
> - Exactly **one sentence**, ≤ 30 words, written in business-domain
>   language.
> - Must answer: _"What shared contract does this copybook carry, and
>   which programs bind to it?"_
> - **FORBIDDEN:** COBOL jargon (`COPY`, `REPLACING`, `PIC`, `COMP-3`,
>   `01-level`), field counts, byte counts, or restating the copybook
>   name. No citations here — the Summary is a hook; evidence lives below.

## Purpose
{{PURPOSE_PARAGRAPH}}

> Authoring rules (binding):
> - At least 4 full sentences (≈ 80–120 words) focused on **what this
>   copybook represents** — i.e. the shared record contract, the
>   DB2 host-variable area (DCLGEN), the CICS commarea contract, the
>   BMS symbolic map, the constants / return-code catalogue, the
>   procedure fragment — not on what a COBOL copybook **is** in the
>   abstract.
> - **FORBIDDEN OPENERS:** "This copybook declares the following
>   fields…", "The copybook spans lines X to Y and contains N
>   elementary items…", "This copybook is included by the following
>   programs…", "This member is a COBOL copybook that…". Always pivot
>   to the concrete contract: _"This copybook carries the customer
>   master row shared between the nightly batch loader `DEMO100`, the
>   online maintenance transaction `DEMO170`, and the regulatory
>   extract `DEMO500`; it pins the regulated identifiers (`CUST-ID`,
>   `CUST-VAT`), the balance accumulators, and the dormancy flags
>   evaluated by every consumer…"_.
> - Identify the **shared responsibility** of the member (which
>   contract it freezes, which entity / message / table it models).
> - Identify the **inclusion contract**: which sections of the
>   including program (`FILE SECTION`, `WORKING-STORAGE`,
>   `LOCAL-STORAGE`, `LINKAGE`, `PROCEDURE DIVISION`) consume it, and
>   the canonical `REPLACING` pattern (when one exists).
> - **FORBIDDEN:** sentences that report line counts, field counts,
>   byte counts, or any other structural statistic. Those facts live
>   in `facts.json` and in citation footnotes — never in prose.
> - Cite source ranges using the Pandoc-footnote form `[^src-N]`
>   (see `citations-and-confidence.instructions.md`); never inline
>   `[FILE:Lx-Ly]` tags.

## Business context
{{BUSINESS_CONTEXT}}

> At least 3 sentences. Explain which business entity / interface
> contract the copybook models, which upstream system populates the
> data, which downstream system consumes it, and which regulatory /
> contractual constraints it freezes for every including program (PII
> fields, financial amounts subject to rounding rules, retention
> class, audit-trail requirement, idempotency contract, multi-tenant
> partitioning key).

## Copybook kind and inclusion contract
{{KIND_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences. Classify the copybook as one of:
>   **data-layout** (one or more 01-level records — the common case),
>   **DCLGEN host-variable area** (generated from a DB2 table; name
>   the table), **CICS commarea contract** (`DFHCOMMAREA`-shaped),
>   **BMS symbolic map** (paired with a physical map), **constants /
>   return-code catalogue** (78-levels or `VALUE`-only items),
>   **procedure fragment** (rare — body of COBOL statements
>   `COPY`-ed inside `PROCEDURE DIVISION`), **mixed** (flag in
>   _Warnings_).
> - Name the **canonical inclusion section** (`FILE SECTION`,
>   `WORKING-STORAGE`, `LOCAL-STORAGE`, `LINKAGE`, `PROCEDURE`)
>   expected by the contract. Inclusion in the **wrong** section
>   (e.g. a DCLGEN inlined in `LINKAGE`) is a finding for _Warnings_.
> - State whether the copybook is **self-contained** or transitively
>   pulls other copybooks via nested `COPY`; list the nested members.

## Records and structure
{{RECORDS_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences. Group 01-level records by **role** —
>   business payload, control flags, accumulators, lookup tables,
>   commarea, host-variable area — not by source order.
> - Call out every clause that constrains modernization:
>   `COMP-3` / `PACKED-DECIMAL` (base-10 semantics), `COMP` /
>   `BINARY` (host endianness), `POINTER` (raw address), `OCCURS`
>   (table cardinality), `OCCURS … DEPENDING ON` (variable-length
>   record), `REDEFINES` (memory aliasing), `88`-level condition
>   names (domain constraints), `EXTERNAL` / `GLOBAL` (cross-program
>   visibility).
> - Per-record deep-dives live in the linked `data-record` documents;
>   keep the prose here at the **shape and intent** level.

### 01-level inventory
| Record name | Role | Length (bytes) | Notable clauses | Per-record doc |
|-------------|------|----------------|-----------------|----------------|
{{#RECORDS}}
| `{{RECORD_NAME}}` | {{RECORD_ROLE}} | {{RECORD_BYTES}} | {{RECORD_CLAUSES}} | {{#RECORD_DOC_LINK}}[`{{RECORD_DOC_FILE}}`]({{RECORD_DOC_LINK}}){{/RECORD_DOC_LINK}}{{^RECORD_DOC_LINK}}—{{/RECORD_DOC_LINK}} |
{{/RECORDS}}
{{^RECORDS}}
| _No 01-level record declared (constants-only or procedure-fragment copybook)._ | — | — | — | — |
{{/RECORDS}}

> `Role` is one of `payload`, `flag`, `counter`, `accumulator`,
> `lookup-table`, `commarea`, `host-variables`, `constants`,
> `procedure-fragment`, `other`. `Notable clauses` lists `REDEFINES`,
> `OCCURS`, `OCCURS … DEPENDING ON`, `EXTERNAL`, `GLOBAL`, `VALUE`,
> `USAGE` (only when non-`DISPLAY`).

### Fields (per record)
{{#RECORDS_FIELDS}}
#### `{{RECORD_NAME}}` (level 01)

| Level | Field name | PIC / USAGE | Role | OCCURS | REDEFINES | 88-levels | Notes |
|-------|------------|-------------|------|--------|-----------|-----------|-------|
{{#FIELDS}}
| {{LEVEL}} | `{{NAME}}` | `{{PIC}}` | {{ROLE}} | {{OCCURS}} | {{REDEFINES}} | {{COND_NAMES}} | {{NOTES}} |
{{/FIELDS}}
{{^FIELDS}}
| _No elementary field declared under this 01-level._ | — | — | — | — | — | — | — |
{{/FIELDS}}

##### Condition names (88-levels)
{{#COND_NAMES_DETAIL}}
- `{{COND_NAME}}` on `{{PARENT_FIELD}}` = `{{VALUES}}` → {{MEANING}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/COND_NAMES_DETAIL}}
{{^COND_NAMES_DETAIL}}
- _No 88-level condition name declared on this record._
{{/COND_NAMES_DETAIL}}
{{/RECORDS_FIELDS}}

### Overlays (REDEFINES)
{{#REDEFINES_GROUPS}}
- `{{ORIGINAL}}` redefined by `{{ALIAS}}` → {{INTERPRETATION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/REDEFINES_GROUPS}}
{{^REDEFINES_GROUPS}}
- _No `REDEFINES` overlay in this copybook._
{{/REDEFINES_GROUPS}}

### Variable cardinality (OCCURS DEPENDING ON)
{{#OCCURS_DEPENDING}}
- `{{FIELD}}` `OCCURS 1..{{MAX}} DEPENDING ON {{COUNTER}}` — {{INTERPRETATION}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/OCCURS_DEPENDING}}
{{^OCCURS_DEPENDING}}
- _No `OCCURS … DEPENDING ON` clause in this copybook._
{{/OCCURS_DEPENDING}}

### Nested COPY (transitive includes)
{{#NESTED_COPY}}
- `COPY {{NESTED_NAME}}`{{#NESTED_REPLACING}} `REPLACING {{NESTED_REPLACING}}`{{/NESTED_REPLACING}}{{#NESTED_DOC_LINK}} → [`{{NESTED_DOC_FILE}}`]({{NESTED_DOC_LINK}}){{/NESTED_DOC_LINK}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/NESTED_COPY}}
{{^NESTED_COPY}}
- _This copybook does not nest any further `COPY` statement._
{{/NESTED_COPY}}

### Structure diagram
{{#STRUCTURE_DIAGRAM}}
```mermaid
{{STRUCTURE_MERMAID}}
```
*Figure 1 — {{STRUCTURE_CAPTION}}*
{{/STRUCTURE_DIAGRAM}}
{{^STRUCTURE_DIAGRAM}}
_No structure diagram emitted — the field tables above are sufficient (no `REDEFINES` overlay, no `OCCURS … DEPENDING ON`, and no DCLGEN / business-entity ER fragment is available for this copybook)._
{{/STRUCTURE_DIAGRAM}}

> Diagram authoring rules (binding) — read `mermaid-authoring/SKILL.md`:
> - **Source of truth.** When
>   `docs/_shared/<copybook>/diagrams/er-fragment.mmd` exists (produced
>   by `diagram-renderer` for DCLGEN / business-entity copybooks),
>   embed its contents **verbatim** into `STRUCTURE_MERMAID` — do NOT
>   re-author. The `er-fragment.mmd` is the single source of truth and
>   is the file rendered to SVG by phase D.
> - **Inline authoring (only when no er-fragment exists).** Emit this
>   diagram inline **only** when at least one of the following is
>   true: (a) the copybook has ≥ 1 `REDEFINES` overlay (show every
>   variant over the shared bytes — use `classDiagram` or
>   `flowchart LR` grouped per byte range); (b) the copybook has ≥ 1
>   `OCCURS … DEPENDING ON` (show the variable-length region with its
>   counter). These two kinds have no `diagram-renderer` equivalent,
>   so authoring inline is allowed.
> - **Never written to the sidecar.** The structure diagram is NEVER
>   written to `bundle.output_paths.diagram` — that slot is reserved
>   for the inclusion graph (see below).
> - When none of the above holds, leave the inverted-section empty
>   message in place — a flat 01/05/10 tree adds no information
>   beyond the field tables and is FORBIDDEN as boilerplate.
> - `STRUCTURE_CAPTION` is a single full sentence (≤ 25 words) in the
>   document's target language that explains the overlay / variable
>   region / entity relationship in domain terms; never a restatement
>   of the copybook name.
> - Use only identifiers present in `bundle.facts_slice` (record
>   names, field names, counter names); no invented nodes.
> - **Forbidden:** `[Open in Draw.io](…)` / `app.diagrams.net` links.

## Inclusion sites
{{INCLUSION_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences. Identify every program that includes the
>   copybook, the **section** of the including program where it
>   lands, and whether the program supplies a `REPLACING` clause.
> - Make **layout divergence** explicit: when two programs include
>   the copybook with different `REPLACING` patterns, the inlined
>   layout differs, and any cross-program contract claim must be
>   qualified. List divergent sites in the matrix below and flag the
>   risk in _Warnings_.
> - Flag every `COPY … SUPPRESS` (the substituted text is omitted
>   from the listing — harmless for compilation but a documentation
>   trap), every `COPY … OF library-name` (resolution depends on the
>   `SYSLIB` concatenation), and every `COPY` issued from a section
>   that does NOT match the canonical inclusion contract above.
> - The **Incoming xref** subsection below is rendered verbatim from
>   `bundle.facts_slice.incoming_xref[]` filtered on `via == "copy"`;
>   the **Inclusion matrix** above is the analyst-authored view that
>   resolves `REPLACING`, including-section and notes. Every program
>   that appears in the xref MUST also appear in the matrix (or the
>   discrepancy MUST be raised in _Warnings_).

### Inclusion matrix
| Program | Including section | `REPLACING` clause | Resolution | Notes |
|---------|-------------------|--------------------|------------|-------|
{{#USED_BY}}
| `{{PROGRAM}}`{{#PROGRAM_DOC_LINK}} ([doc]({{PROGRAM_DOC_LINK}})){{/PROGRAM_DOC_LINK}} | {{INCLUDING_SECTION}} | {{#REPLACING}}`{{REPLACING}}`{{/REPLACING}}{{^REPLACING}}—{{/REPLACING}} | {{RESOLUTION}} | {{USAGE_NOTES}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}} |
{{/USED_BY}}
{{^USED_BY}}
| _No including program detected in workspace — copybook is orphan (see Warnings)._ | — | — | — | — |
{{/USED_BY}}

> `Including section` is one of `FILE`, `WORKING-STORAGE`,
> `LOCAL-STORAGE`, `LINKAGE`, `PROCEDURE`, `unknown`.
> `Resolution` is `direct` (resolved on the canonical search path),
> `library` (`COPY … OF <lib>` — name the library),
> `suppressed` (`COPY … SUPPRESS`), or `missing` (referenced but
> not found in the workspace — flag in _Warnings_).

### Incoming xref (workspace-scope, `via == "copy"`)
{{#INCOMING_XREF_COPY}}
- `{{CALLER_SOURCE}}` ({{CALLER_KIND}}) at L{{CALLER_LINE}}{{#CALLER_DOC_LINK}} → [doc]({{CALLER_DOC_LINK}}){{/CALLER_DOC_LINK}}
{{/INCOMING_XREF_COPY}}
{{^INCOMING_XREF_COPY}}
- _No `via="copy"` edge in `bundle.facts_slice.incoming_xref[]` — copybook is orphan in the analysed workspace (see Warnings)._
{{/INCOMING_XREF_COPY}}

> Each bullet is one entry of `bundle.facts_slice.incoming_xref[]`
> filtered on `via == "copy"`, emitted in the deterministic order
> produced by `scripts/tools/xref-incoming-pass.py` (sorted by
> `caller_source`, then `line`). Do NOT hand-edit; re-run the xref
> pass when callers change. `caller_kind` is one of `cobol`, `jcl`,
> `proc`, `bms`, `copy`.

### Other incoming edges (non-`copy`, if any)
{{#INCOMING_XREF_OTHER}}
- `{{CALLER_SOURCE}}` ({{CALLER_KIND}}) at L{{CALLER_LINE}} via `{{VIA}}` — ⚠️ unexpected for a copybook (see Warnings)
{{/INCOMING_XREF_OTHER}}
{{^INCOMING_XREF_OTHER}}
- _No non-`copy` incoming edge — expected for a well-formed copybook._
{{/INCOMING_XREF_OTHER}}

> A copybook should only ever appear as the target of a `COPY`
> statement. Any `call` / `cics-link` / `cics-xctl` / `jcl-step` edge
> targeting this member indicates either (a) a misclassified source
> file (the member is actually an executable program), (b) a stale
> facts.json that needs re-extraction, or (c) a name collision
> between a program-id and a copybook member. Each such edge MUST be
> raised in _Warnings_.

### Inclusion graph
{{#INCLUSION_DIAGRAM}}
```mermaid
{{INCLUSION_MERMAID}}
```
*Figure 2 — {{INCLUSION_CAPTION}}*
{{/INCLUSION_DIAGRAM}}
{{^INCLUSION_DIAGRAM}}
_No inclusion graph emitted — the copybook has fewer than two
including programs and no `REPLACING` divergence, so the inclusion
matrix above carries the full story._
{{/INCLUSION_DIAGRAM}}

> Diagram authoring rules (binding) — read `mermaid-authoring/SKILL.md`:
> - **Gate.** Emit this diagram **only** when (a) there are ≥ 2
>   including programs in `bundle.facts_slice.incoming_xref[]`
>   (via=`copy`), or (b) `REPLACING` divergence is present (any
>   number of includers). Below those thresholds the matrix is enough
>   and the sidecar `.mmd` is NOT emitted.
> - **Sidecar contract.** When emitted, the Mermaid source MUST be
>   written **byte-identical** to both (i) the fenced block below and
>   (ii) `bundle.output_paths.diagram` (the per-chunk `.mmd` sidecar
>   at `docs/_shared/<copybook>/diagrams/section-<chunk_id>.mmd`).
>   Phase D renders the sidecar to SVG; the inline copy is for the
>   reader. When the gate fails, the sidecar file is NOT written
>   (and any stale file from a previous run is deleted by
>   `section-doc-writer` with `--prune`).
> - **Layout.** Use `flowchart LR` with the copybook as the right-hand
>   sink and each including program as a left-hand source. Edge labels
>   carry the including-section (`WS`, `FILE`, `LINKAGE`, `PROCEDURE`,
>   `LOCAL`); when the program supplies a `REPLACING` clause, add
>   `+REPLACING` to the edge label and style that edge with
>   `linkStyle` to make divergence visually obvious.
> - When `REPLACING` divergence is present, group includers by
>   variant using Mermaid `subgraph` blocks (one per variant); the
>   subgraph title is the divergent token replacement.
> - Nodes use the bare program name (e.g. `DEMO100`) and the bare
>   copybook name; no invented nodes; no edges absent from
>   `incoming_xref` or the inclusion matrix.
> - `INCLUSION_CAPTION` is a single full sentence (≤ 25 words) in
>   the document's target language stating the blast-radius story
>   (e.g. _"Seven batch programs include this commarea contract;
>   `DEMO170` and `DEMO500` apply divergent `REPLACING` clauses."_).
> - **Forbidden:** `[Open in Draw.io](…)` / `app.diagrams.net` links;
>   nodes for programs that are not in `incoming_xref`.

### REPLACING divergence
{{#REPLACING_DIVERGENCE}}
- Token `{{PSEUDO_TEXT}}` → {{#VARIANTS}}`{{REPLACEMENT}}` (in {{#PROGRAMS}}`{{PROGRAM}}`{{^LAST}}, {{/LAST}}{{/PROGRAMS}}){{^LAST}}; {{/LAST}}{{/VARIANTS}}
{{/REPLACING_DIVERGENCE}}
{{^REPLACING_DIVERGENCE}}
- _Every including program inlines the copybook with the same
  effective text — no `REPLACING` divergence detected._
{{/REPLACING_DIVERGENCE}}

> Each bullet pins a pseudo-text token to the set of replacements
> applied across the workspace. Any token with more than one
> replacement signals layout divergence: contract claims that depend
> on the replaced name must be qualified per-program.

## Cross-references

### Producers (write the records carried by this copybook)
{{#XREF_PRODUCERS}}
- {{TYPE}}: `{{SOURCE_REF}}`{{#SOURCE_LINK}} ([`{{SOURCE_FILE_REF}}`]({{SOURCE_LINK}})){{/SOURCE_LINK}}{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_PRODUCERS}}
{{^XREF_PRODUCERS}}
- _No producer detected in workspace._
{{/XREF_PRODUCERS}}

### Consumers (read the records carried by this copybook)
{{#XREF_CONSUMERS}}
- {{TYPE}}: `{{SOURCE_REF}}`{{#SOURCE_LINK}} ([`{{SOURCE_FILE_REF}}`]({{SOURCE_LINK}})){{/SOURCE_LINK}}{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_CONSUMERS}}
{{^XREF_CONSUMERS}}
- _No consumer detected in workspace._
{{/XREF_CONSUMERS}}

### Related shared definitions
{{#XREF_RELATED}}
- {{KIND}}: `{{MEMBER}}`{{#MEMBER_LINK}} ([`{{MEMBER_FILE}}`]({{MEMBER_LINK}})){{/MEMBER_LINK}} — {{RELATION}}
{{/XREF_RELATED}}
{{^XREF_RELATED}}
- _No related copybook / DCLGEN / BMS map identified._
{{/XREF_RELATED}}

> `Relation` is `paired BMS physical map`, `companion DCLGEN for same
> table`, `sibling commarea variant`, `superseded by`, `supersedes`,
> `included alongside in every consumer`, or `other`.

## Invariants and domain constraints
{{#INVARIANTS}}
- {{INVARIANT}}{{#CITATION}} [^{{CITATION}}]{{/CITATION}}
{{/INVARIANTS}}
{{^INVARIANTS}}
- _No invariant identified on this copybook._
{{/INVARIANTS}}

> Conditions that hold on every consistent instance of the records
> carried by this copybook: referential keys, sign of numeric fields,
> valid code values (captured by `88`-levels), ordering of repeated
> groups, mutual exclusion between overlay variants, mandatory
> initialisation by the caller (for `LINKAGE` / commarea copybooks).

## Modernization implications
{{MODERNIZATION_NOTES}}

> At least 3 sentences. Indicate how this copybook maps to the
> target stack (Java record / POJO, .NET DTO, JSON / Protobuf schema,
> Postgres row, Avro envelope) and the specific risks the migration
> inherits:
> - **Cross-program contract:** every including program must be
>   migrated atomically with this copybook (or a versioning shim
>   must be introduced).
> - **`REPLACING` divergence:** when divergence is present, the
>   target schema cannot be a single type — list the variants.
> - **DCLGEN copybooks:** the schema must remain bit-exact with the
>   DB2 table; coordinate with the data-modernisation track.
> - **Commarea copybooks:** the call contract crosses the
>   COBOL / target-stack boundary; an adapter layer is required.
> - **BMS symbolic maps:** the UI track owns the migration; this
>   copybook is consumed but not authored by the back-end track.
> - **Numeric semantics:** `COMP-3` / `COMP` fields require
>   explicit conversion at the boundary.

## Complexity and migration risk
| Dimension | Value | Source |
|-----------|-------|--------|
| 01-level record count | {{RECORD_COUNT}} | `facts.json` |
| Elementary field count (total) | {{FIELD_COUNT}} | `facts.json` |
| Total length (bytes) | {{COPYBOOK_BYTES}} | `facts.json` |
| `OCCURS` tables | {{OCCURS_COUNT}} | `facts.json` |
| `OCCURS … DEPENDING ON` count | {{ODO_COUNT}} | `facts.json` |
| `REDEFINES` overlays | {{REDEFINES_COUNT}} | `facts.json` |
| `88`-level condition names | {{COND_COUNT}} | `facts.json` |
| Non-`DISPLAY` usages | {{NON_DISPLAY_COUNT}} | `facts.json` |
| Nested `COPY` statements | {{NESTED_COPY_COUNT}} | `facts.json` |
| Including programs (workspace) | {{USED_BY_COUNT}} | `facts.json` |
| `REPLACING` divergence detected? | {{REPLACING_DIVERGENCE_FLAG}} | `facts.json` |
| Migration risk | {{MIGRATION_RISK_LEVEL}} ({{MIGRATION_RISK_LEVEL_RATIONALE}}) | analyst |

> Numeric cells are mechanically lifted from `facts.json` — do NOT
> recompute or paraphrase them in the prose above.
> `REPLACING_DIVERGENCE_FLAG` is `yes` / `no`.
> `MIGRATION_RISK_LEVEL` is one of `low`, `medium`, `high`, `blocker`;
> the rationale is a short clause (e.g. _"shared by 7 programs with
> divergent `REPLACING` clauses"_, _"DCLGEN locked to DB2 table
> `CUST_MASTER`"_, _"contains `OCCURS DEPENDING ON` requiring
> variable-length serialisation"_).

## Warnings
{{#WARNINGS}}
- ⚠️ {{WARNING}}
{{/WARNINGS}}
{{^WARNINGS}}
- _No warnings raised for this copybook._
{{/WARNINGS}}

> Each of the following situations MUST surface a warning bullet here:
> orphan copybook (no `via="copy"` edge in
> `bundle.facts_slice.incoming_xref[]`); `REPLACING` divergence
> across including programs; inclusion in a section that does NOT
> match the canonical inclusion contract; `COPY … SUPPRESS` site
> (substituted text omitted from the compilation listing); `COPY`
> resolution depends on `SYSLIB` library concatenation that is not
> pinned in the workspace; nested `COPY` of a member not found in
> the workspace; DCLGEN whose underlying DB2 table is also accessed
> by ad-hoc `EXEC SQL` in any consumer (drift risk); `EXTERNAL` /
> `GLOBAL` items inside the copybook (process-wide shared state);
> record length declared in the copybook does not match the
> `RECORD CONTAINS` clause of any `FD` that includes it (multi-format
> file or stale copybook); xref discrepancy — a program in the
> _Inclusion matrix_ is missing from `incoming_xref` (stale xref
> pass) or vice versa (the matrix is incomplete); any non-`copy`
> entry in `incoming_xref` (misclassified file, stale facts, or
> name collision).

## Citations

<!-- Pandoc footnote definitions for every `[^src-N]` marker used
     above. Generated from facts.json; never hand-edit. Each entry
     pins the claim to an exact source range and records the analyst's
     confidence (high / medium / low) plus the evidence kind
     (verbatim / paraphrase / inference). See
     .github/instructions/citations-and-confidence.instructions.md.
     **BINDING:** every `CITATION_FILE` MUST be an original source
     listing (COBOL / JCL / PROC / copybook / BMS member under
     `repos/`). NEVER cite `facts.json`, `chunk-manifest.json`, any
     `*.bundle.md` / `*.bundle.json`, a facts-slice, or any other
     generated artefact — those are derived from the source and add no
     evidence beyond it. If the only available provenance is a
     generated artefact, the claim does not belong in the section
     narrative; surface it as a `_Warnings_` bullet instead. -->

{{#CITATIONS}}
[^src-{{CITATION_ID}}]: `{{CITATION_FILE}}` L{{CITATION_START}}–L{{CITATION_END}} — confidence: **{{CITATION_CONFIDENCE}}**, evidence: {{CITATION_EVIDENCE_KIND}}.{{#CITATION_NOTE}} {{CITATION_NOTE}}{{/CITATION_NOTE}}
{{/CITATIONS}}
{{^CITATIONS}}
_No citations emitted — the narrative above must therefore contain no `[^src-N]` markers._
{{/CITATIONS}}

---

<!-- Authoring self-check. MUST be evaluated by the generator before
     emitting the document; any unchecked box is a hard failure
     surfaced in the lint report. Do NOT delete this block. -->

### Authoring self-check
- [ ] Summary is a single business-language sentence, ≤ 30 words, no COBOL jargon.
- [ ] Purpose ≥ 4 sentences and avoids any forbidden transcript opener.
- [ ] `Copybook kind and inclusion contract` classifies the member
      (data-layout / DCLGEN / commarea / BMS map / constants /
      procedure-fragment / mixed) and names the canonical inclusion
      section.
- [ ] `01-level inventory` lists every 01-level in `bundle.facts_slice`
      with its role, byte length and notable clauses; each row links
      to its `data-record` per-section doc when one exists.
- [ ] `Nested COPY` lists every transitive include in `bundle.facts_slice`
      (or the explicit empty-state bullet).
- [ ] `Inclusion matrix` lists every including program in
      `bundle.facts_slice` with its `REPLACING` clause and
      including-section; orphan copybook is flagged in _Warnings_.
- [ ] `Incoming xref (via="copy")` is rendered verbatim from
      `bundle.facts_slice.incoming_xref[]` filtered on `via == "copy"`,
      sorted as produced by `scripts/tools/xref-incoming-pass.py`; the set
      of programs matches the _Inclusion matrix_ (any discrepancy is
      flagged in _Warnings_).
- [ ] `Other incoming edges` lists every non-`copy` entry in
      `bundle.facts_slice.incoming_xref[]` (or the explicit empty-state
      bullet); any such edge is flagged in _Warnings_.
- [ ] `REPLACING divergence` lists every pseudo-text token whose
      replacement differs across including programs (or the explicit
      empty-state bullet); divergence is flagged in _Warnings_.
- [ ] `Structure diagram` is emitted **only** when (a) an
      `er-fragment.mmd` produced by `diagram-renderer` exists for this
      copybook (embedded verbatim), or (b) ≥ 1 `REDEFINES` overlay /
      ≥ 1 `OCCURS … DEPENDING ON` is present (inline-authored).
      Otherwise the inverted-section empty-state message is left in
      place. The structure diagram is NEVER written to
      `bundle.output_paths.diagram`. Captions are present and
      ≤ 25 words.
- [ ] `Inclusion graph` is emitted **only** when ≥ 2 including
      programs, or any `REPLACING` divergence is present. When
      emitted, the Mermaid source is **byte-identical** to
      `bundle.output_paths.diagram` (the sidecar `.mmd`); when the
      gate fails, the sidecar file is NOT written. Every node and
      edge resolves to an entry in `incoming_xref` / _Inclusion
      matrix_; divergent edges are visually distinct. Captions are
      present and ≤ 25 words.
- [ ] Every `[^src-N]` marker in the body has a matching definition
      under _Citations_; every definition is actually referenced.
- [ ] No `[FILE:Lx-Ly]` inline tags, no `app.diagrams.net` / Draw.io
      links, no "self-contained document / bundles facts.json" banner.
- [ ] `Complexity and migration risk` cells match `bundle.facts_slice`
      byte-for-byte (counts are sourced from the slice; the same
      values were emitted by the file-level `facts.json` extractor).
