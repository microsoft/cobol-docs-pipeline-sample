# {{SECTION_NUMBER}}. Step `{{STEP_NAME}}` — {{STEP_TARGET}}

> **Source file:** `{{SOURCE_PATH}}` · **Chunk kind:** {{CHUNK_KIND}} · **Parent job / proc:** `{{PARENT_NAME}}` · **Kind:** {{STEP_KIND}}

<!-- Per-chunk deliverable for ONE JCL step (a single chunk of kind
     `jcl-step`). Whole-job narrative (header, scheduler, step inventory,
     control-flow diagram, MAXCC contract) belongs in `jcl-job.template.md`;
     do NOT restate it here. Provenance (line range, DD count, instream
     count) lives in facts.json and in citation footnotes; do NOT surface it
     as a header banner or as narrative filler. The reader needs to
     understand WHAT this step does in the batch chain, WHICH datasets and
     resources it touches, HOW it is gated by upstream steps, and WHAT the
     downstream steps gate on its return code. See
     .github/instructions/no-generator-boilerplate.instructions.md — the
     "Self-contained document. Bundles… from facts.json…" banner and
     `[Open in Draw.io](app.diagrams.net/...)` links are FORBIDDEN. -->

## Summary
{{TLDR_ONE_LINER}}

> Authoring rules (binding):
> - Exactly **one sentence**, ≤ 30 words, written in business / operations
>   language.
> - Must answer: _"What does this step do for the batch chain?"_
> - **FORBIDDEN:** JCL jargon (`EXEC PGM=`, `DD`, `DISP=`, `COND=`),
>   line counts, DD counts, or restating the step name. No citations
>   here — the Summary is a hook; evidence lives below.

## Purpose
{{PURPOSE_PARAGRAPH}}

> Authoring rules (binding):
> - At least 4 full sentences (≈ 80–120 words) focused on **what this
>   step accomplishes for the batch chain** — i.e. the business or
>   operational concern it addresses — not on what a JCL step **is** in
>   the abstract and not on the wider job.
> - **FORBIDDEN OPENERS:** "This step executes the following program…",
>   "The step spans lines X to Y and references the following DDs…",
>   "This `EXEC PGM=` step invokes …". Always pivot to the concrete
>   intent: _"This step refreshes the customer-balance extract by
>   sorting the previous-day movements file against the master and
>   writing the regulated audit trail; downstream reporting steps gate
>   on its RC=0 to enter the dispatch phase…"_.
> - Identify the **operational responsibility** of the step (which
>   batch-chain stage it belongs to, which sibling steps it cooperates
>   with).
> - Identify the **business value** (what changes for the downstream
>   chain after execution).
> - **FORBIDDEN:** sentences that report line counts, DD counts or any
>   other structural statistic. Those facts live in `facts.json` and in
>   citation footnotes — never in prose.
> - Cite source ranges using the Pandoc-footnote form `[^src-N]`
>   (see `citations-and-confidence.instructions.md`); never inline
>   `[FILE:Lx-Ly]` tags.

## Business / operational context
{{BUSINESS_CONTEXT}}

> At least 3 sentences. Explain which business process the step
> implements, which upstream feeds it consumes, which downstream
> consumers depend on its output, and which regulatory / contractual
> constraints it inherits (audit trail, retention, recovery window).

## EXEC contract
{{EXEC_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences describing **what is invoked and under which
>   conditions**. Identify the `EXEC` verb (`PGM` for a program,
>   `PROC` for a cataloged or in-stream procedure), the `PARM=`
>   payload, the `COND=` predicate or the modern `IF/THEN/ELSE/ENDIF`
>   gate, and any `RESTART=` / `REGION=` / `TIME=` / `DYNAMNBR=`
>   overrides. When the step is gated by upstream steps, name them
>   explicitly and state the predicate.

### EXEC summary
| Attribute | Value | Notes |
|-----------|-------|-------|
| EXEC verb | `EXEC {{EXEC_VERB}}={{STEP_TARGET}}` | |
| PARM | `{{PARM}}` | |
| COND | `{{COND}}` | legacy gate |
| IF predicate | `{{IF_PREDICATE}}` | modern gate |
| RESTART | `{{RESTART}}` | |
| Region / Time / Dynamnbr | `{{STEP_OVERRIDES}}` | |
| Expected RC | `{{STEP_EXPECTED_RC}}` | |

{{#HAS_PROC_OVERRIDES}}
### PROC overrides
{{#PROC_SYMBOL_OVERRIDES}}
- Symbolic: `{{PARAM}}` = `{{VALUE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/PROC_SYMBOL_OVERRIDES}}
{{#PROC_DD_OVERRIDES}}
- DD override: `{{PROCSTEP}}.{{DD_NAME}}` — `{{OVERRIDE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/PROC_DD_OVERRIDES}}
{{/HAS_PROC_OVERRIDES}}

## DD statements
{{DD_NARRATIVE}}

> Authoring rules (binding):
> - At least 3 sentences grouping DDs by **role** — input feeds,
>   primary output, audit / log output, sort work, parameter cards,
>   instream control, dummy / sysout — rather than walking them in
>   source order. Call out every DD that constrains the operations
>   plan: GDG generations (`(+1)`, `(0)`, `(-n)`), VSAM clusters,
>   temporary datasets (`&&NAME`), backreferences (`*.STEP.DD`),
>   `DISP=(NEW,CATLG,DELETE)` triplets whose abnormal disposition
>   matters for restart, and instream blocks (`DD *`) that carry
>   parameter cards.
> - Cite every claim with `[^src-N]` markers anchored to the relevant
>   DD statement.

### DD inventory
| DD | DSN / source | Kind | Direction | DISP | DCB / SPACE | Notes |
|----|--------------|------|-----------|------|-------------|-------|
{{#DDS}}
| `{{DD_NAME}}` | `{{DSN}}` | {{DD_KIND}} | {{DD_DIRECTION}} | `{{DISP}}` | `{{DCB_OR_SPACE}}` | {{NOTES}} |
{{/DDS}}
{{^DDS}}
| _This step declares no DD statements._ | — | — | — | — | — | — |
{{/DDS}}

> `Kind` ∈ `PS`, `PO`, `VSAM-KSDS`, `VSAM-ESDS`, `VSAM-RRDS`,
> `GDG-BASE`, `GDG-GEN`, `TEMP` (`&&NAME`), `SYSOUT`, `INSTREAM`
> (`DD *`), `DUMMY`, `BACKREF` (`*.STEP.DD`), `CONCAT`. `Direction` ∈
> `IN`, `OUT`, `MOD`, `SHR`, `OLD`, `NEW`. `DISP` MUST be the full
> triplet `(status,normal,abnormal)`.

{{#HAS_INSTREAM}}
### Instream input
{{#INSTREAM_BLOCKS}}
- `DD {{DD_NAME}}` — see [`{{INSTREAM_FILE}}`]({{INSTREAM_LINK}}){{#INSTREAM_NOTES}} — {{INSTREAM_NOTES}}{{/INSTREAM_NOTES}}
{{/INSTREAM_BLOCKS}}
{{/HAS_INSTREAM}}

## Datasets touched
| DD | DSN | Kind | Direction | DISP | GDG role | Notes |
|----|-----|------|-----------|------|----------|-------|
{{#DATASETS}}
| `{{DD_NAME}}` | `{{DSN}}` | {{DD_KIND}} | {{DD_DIRECTION}} | `{{DISP}}` | {{GDG_ROLE}} | {{NOTES}} |
{{/DATASETS}}
{{^DATASETS}}
| _No catalogued datasets referenced — step uses only instream / sysout / temporary DDs._ | — | — | — | — | — | — |
{{/DATASETS}}

> `GDG role` ∈ `BASE`, `CURRENT` (`(0)`), `PREVIOUS` (`(-n)`), `NEW`
> (`(+n)`), `—` (not a GDG).

## External resources
| Kind | Resource | Direction | Notes |
|------|----------|-----------|-------|
{{#EXTERNAL_RESOURCES}}
| {{RES_KIND}} | `{{RES_NAME}}` | {{RES_DIRECTION}} | {{NOTES}} |
{{/EXTERNAL_RESOURCES}}
{{^EXTERNAL_RESOURCES}}
| _No external resources touched beyond the datasets listed above._ | — | — | — |
{{/EXTERNAL_RESOURCES}}

> `Kind` ∈ `DB2-PLAN`, `DB2-PACKAGE`, `DB2-TABLE`, `MQ-QUEUE`,
> `MQ-MGR`, `FTP-SERVER`, `IDCAMS-CMD`, `SORT-CTL`, `BPX-SHELL-CMD`,
> `REXX-EXEC`, `INCLUDE-MEMBER`, `JCLLIB-ENTRY`. Use this table for
> everything the step touches that is **not** a plain dataset.

## Program / utility behaviour
{{PROGRAM_BEHAVIOR_NARRATIVE}}

> At least 3 sentences. When the EXEC target is a well-known utility
> (`IEFBR14`, `IEBGENER`, `IDCAMS`, `SORT` / `ICEMAN`, `IKJEFT01`,
> `DSNUTILB`, `BPXBATCH`), describe what control cards the step
> submits (read from `SYSIN` / `SYSTSIN` / `SORTIN` etc.) and what
> operation they request. When the target is an application program,
> link to its per-program documentation and summarise the contract
> (input record format, output record format, return-code semantics).

### Program / utility binding
| Attribute | Value | Notes |
|-----------|-------|-------|
| Target | `{{STEP_TARGET}}` | |
| Binding | {{PGM_BINDING}} | `STATIC` / `DYNAMIC` / `UNRESOLVED` |
| Source | {{#PGM_FILE}}[`{{PGM_FILE}}`]({{PGM_LINK}}){{/PGM_FILE}}{{^PGM_FILE}}_unresolved_{{/PGM_FILE}} | |

## Return-code contract
{{RC_NARRATIVE}}

> At least 2 sentences. Identify the nominal RC the step is expected
> to produce, the abnormal RCs that trigger restart / abort, the
> downstream steps that gate on this RC, and the effect on the
> job-level `MAXCC`.

### Return-code matrix
| Expected RC | On RC > expected | On abend | Effect on MAXCC |
|-------------|------------------|----------|-----------------|
| `{{STEP_EXPECTED_RC}}` | {{ON_HIGH_RC}} | {{ON_ABEND}} | {{MAXCC_EFFECT}} |

### Downstream gates on this step
{{#STEP_GATES}}
- `{{GATING_STEP}}` — `{{GATING_COND}}`
{{/STEP_GATES}}
{{^STEP_GATES}}
- _No downstream step gates on this step's RC._
{{/STEP_GATES}}

## Restart and recovery
{{RESTART_NARRATIVE}}

> At least 2 sentences. State whether the step is restartable, what
> reset actions an operator must perform before resubmitting
> (`DELETE` `(+1)` GDG generation, uncatalog the partial output,
> reset a checkpoint dataset, reposition the cursor), and which
> checkpoint / commit boundary the step inherits from the underlying
> program.

| Restartable? | Reset actions before restart | Checkpoint dataset | Notes |
|--------------|------------------------------|--------------------|-------|
| {{RESTARTABLE}} | {{RESET_ACTIONS}} | `{{CHKPT_DSN}}` | {{RESTART_NOTES}} |

## Cross-references

### Upstream (predecessor steps / triggers)
{{#XREF_UPSTREAM}}
- {{TYPE}}: `{{SOURCE_REF}}`{{#SOURCE_LINK}} ([`{{SOURCE_FILE_REF}}`]({{SOURCE_LINK}})){{/SOURCE_LINK}}{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_UPSTREAM}}
{{^XREF_UPSTREAM}}
- _No upstream dependency detected in workspace._
{{/XREF_UPSTREAM}}

### Downstream (consumers of this step's outputs)
{{#XREF_DOWNSTREAM}}
- {{KIND}}: `{{NAME}}` consumed by {{#CONSUMERS}}`{{CONSUMER}}`{{^LAST}}, {{/LAST}}{{/CONSUMERS}}{{^CONSUMERS}}_no downstream consumer detected_{{/CONSUMERS}}
{{/XREF_DOWNSTREAM}}
{{^XREF_DOWNSTREAM}}
- _No downstream artefact tracked for this step._
{{/XREF_DOWNSTREAM}}

### Included members (`JCLLIB` / `INCLUDE`)
{{#INCLUDED_MEMBERS}}
- `{{MEMBER}}` from `{{LIBRARY}}` — {{#MEMBER_LINK}}[`{{MEMBER_FILE}}`]({{MEMBER_LINK}}){{/MEMBER_LINK}}{{^MEMBER_LINK}}_unresolved_{{/MEMBER_LINK}}
{{/INCLUDED_MEMBERS}}
{{^INCLUDED_MEMBERS}}
- _No `INCLUDE` member referenced by this step._
{{/INCLUDED_MEMBERS}}

### `DDNAME` ↔ program data bindings (workspace)
| DDNAME | Logical file in program (`SELECT` / `FD`) | 01-level record bound | Mode in program | Procedure section / paragraph | Notes |
|--------|-------------------------------------------|------------------------|-----------------|-------------------------------|-------|
{{#XREF_DD_BINDINGS}}
| `{{DDB_NAME}}` | `{{DDB_LOGICAL}}` | `{{DDB_RECORD}}` | {{DDB_MODE}} | `{{DDB_OWNER}}` | {{DDB_NOTES}} |
{{/XREF_DD_BINDINGS}}
{{^XREF_DD_BINDINGS}}
| _Invoked program is unresolved in the workspace, or this step targets a utility (`IEFBR14`, `IDCAMS`, `SORT`, …) that owns no FD bindings._ | — | — | — | — | — |
{{/XREF_DD_BINDINGS}}

> Populate by joining each row of the `DD inventory` table above with
> the invoked program's `files[]` slice (DDNAME ↔ external-name ↔
> logical SELECT/FD) and its `data_records[]` slice (the FD's
> attached `01`-level). `Mode in program` (`R`, `W`, `R/W`) and
> `Procedure section / paragraph` come from the program's
> `data_records[].consumers[]` / `procedure-section` slices.
> When the invoked program is not in the workspace, mark every cell
> as `—` and surface a warning bullet rather than guessing.

## Modernization implications
{{MODERNIZATION_NOTES}}

> At least 2 sentences. Indicate how this step maps to the target
> orchestrator (Azure Data Factory pipeline activity, Airflow task,
> Spring Batch step, Argo Workflows node) and which specific risks
> the migration inherits: GDG generation semantics, VSAM key access,
> `COND=` chains that span multiple steps, `RESTART=` semantics,
> dynamic program invocation via `IKJEFT01` / `BPXBATCH`,
> well-known-utility-specific control cards.

## Complexity and migration risk
| Dimension | Value | Source |
|-----------|-------|--------|
| DD count | {{DD_COUNT}} | `facts.json` |
| Dataset references | {{DATASET_COUNT}} | `facts.json` |
| GDG generations touched | {{GDG_COUNT}} | `facts.json` |
| Instream blocks (`DD *`) | {{INSTREAM_COUNT}} | `facts.json` |
| External resources | {{EXT_RES_COUNT}} | `facts.json` |
| Gated by upstream `COND` / `IF`? | {{GATED_BY_UPSTREAM}} | `facts.json` |
| Downstream gates on this RC? | {{HAS_DOWNSTREAM_GATE}} | `facts.json` |
| Dynamic program invocation? | {{DYNAMIC_PGM}} | `facts.json` |
| Migration risk | {{MIGRATION_RISK_LEVEL}} ({{MIGRATION_RISK_LEVEL_RATIONALE}}) | analyst |

> Numeric cells are mechanically lifted from `facts.json` — do NOT
> recompute or paraphrase them in the prose above. `Gated by upstream`,
> `Downstream gates on this RC?` and `Dynamic program invocation?`
> are `yes` / `no`. `MIGRATION_RISK_LEVEL` is one of `low`, `medium`,
> `high`, `blocker`; the rationale is a short clause (e.g. _"dynamic
> `PGM=&PROG` resolved at submit time"_, _"GDG `(+1)` produced and
> consumed in same job"_, _"`COND=ONLY` introduces non-trivial gate"_).

## Warnings
{{#WARNINGS}}
- ⚠️ {{WARNING}}
{{/WARNINGS}}
{{^WARNINGS}}
- _No warnings raised for this step._
{{/WARNINGS}}

> Unreachable step (`COND` predicate always true), unresolved program /
> proc reference, GDG generation produced without a downstream
> consumer, `DISP=(NEW,CATLG,DELETE)` whose abnormal disposition leaks
> partial output on abend, dynamic program invocation that escapes
> static analysis, instream control cards whose target utility is not
> in the workspace MUST each surface a warning bullet here.

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
_No citations emitted — the step narrative above must therefore contain no `[^src-N]` markers._
{{/CITATIONS}}

---

<!-- Authoring self-check. MUST be evaluated by the generator before emitting
     the document; any unchecked box is a hard failure surfaced in the lint
     report. Do NOT delete this block. -->

### Authoring self-check
- [ ] Summary is a single operations-language sentence, ≤ 30 words, no JCL jargon.
- [ ] Purpose ≥ 4 sentences and avoids any forbidden transcript opener.
- [ ] `EXEC contract` names the verb, PARM, COND / IF gate and any overrides
      from `bundle.facts_slice`.
- [ ] `DD statements` groups DDs by role; every GDG / VSAM / TEMP /
      BACKREF / INSTREAM DD is called out.
- [ ] `DD inventory` lists every DD in `bundle.facts_slice` with its kind,
      direction and full `DISP` triplet.
- [ ] `Datasets touched` and `External resources` are populated or marked
      _None_ — never left blank.
- [ ] `Return-code contract` names every downstream step that gates on this
      RC; unreachable / always-skipped steps are flagged in _Warnings_.
- [ ] `Restart and recovery` states whether the step is restartable and
      lists the reset actions an operator must perform.
- [ ] Every `[^src-N]` marker in the body has a matching definition under
      _Citations_; every definition is actually referenced.
- [ ] No `[FILE:Lx-Ly]` inline tags, no `app.diagrams.net` / Draw.io
      links, no "self-contained document / bundles facts.json" banner.
- [ ] `Complexity and migration risk` cells match `bundle.facts_slice`
      byte-for-byte (counts are sourced from the slice; the same values
      were emitted by the file-level `facts.json` extractor).
