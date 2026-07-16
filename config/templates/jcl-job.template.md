---
source_file: "{{SOURCE_FILE}}"
source_path: "{{SOURCE_PATH}}"
source_type: "JCL"
job_name: "{{JOB_NAME}}"
sha256: "{{SHA256}}"
total_lines: {{TOTAL_LINES}}
generated_at: "{{GENERATED_AT}}"
language: "{{LANG}}"
---

# JCL job — `{{JOB_NAME}}`

<!-- Per-job deliverable for ONE JCL member (job or in-stream proc invocation).
     Cataloged PROCs and INCLUDE members are documented separately and linked
     from chapter 7. Self-descriptive banners ("Self-contained document.
     Bundles… from facts.json…") and `[Open in Draw.io](app.diagrams.net/...)`
     links are FORBIDDEN per
     .github/instructions/no-generator-boilerplate.instructions.md. All
     authoring guidance lives in HTML comments — never as rendered prose. -->

> **File:** `{{SOURCE_PATH}}` · **SHA-256:** `{{SHA256}}` · **Lines:** {{TOTAL_LINES}}
> **Steps:** {{STEP_COUNT}} · **Programs invoked:** {{PROGRAM_COUNT}} · **Procs invoked:** {{PROC_COUNT}} · **DDs:** {{DD_COUNT}}
> **Generated:** {{GENERATED_AT}} · **Language:** {{LANG}}

## 1. Summary

<!-- 2–3 sentences. What the job does in business terms, what triggers it,
     what it leaves behind. No JCL jargon. -->

{{TLDR}}

## 2. Purpose

<!-- 1–2 paragraphs. Business role in the batch chain, where it sits relative
     to upstream feeds and downstream consumers, and the value it produces.
     Do NOT describe what JCL is. -->

{{PURPOSE}}

## 3. Job header

| Attribute | Value | Notes |
|-----------|-------|-------|
| Job name | `{{JOB_NAME}}` | |
| Accounting | `{{JOB_ACCOUNT}}` | |
| Class | `{{JOB_CLASS}}` | |
| Msg class | `{{JOB_MSGCLASS}}` | |
| Msg level | `{{JOB_MSGLEVEL}}` | |
| Region | `{{JOB_REGION}}` | |
| Time | `{{JOB_TIME}}` | |
| Notify | `{{JOB_NOTIFY}}` | |
| Typrun | `{{JOB_TYPRUN}}` | `SCAN` / `HOLD` / `COPY` / _none_ |
| Restart | `{{JOB_RESTART}}` | |
| Schenv | `{{JOB_SCHENV}}` | |
| Jcllib | `{{JOB_JCLLIB}}` | `JCLLIB ORDER=(…)` libraries searched for PROCs/INCLUDEs |

{{#JOB_HEADER_NOTES}}
> {{JOB_HEADER_NOTES}}
{{/JOB_HEADER_NOTES}}

## 4. Triggers and scheduling

<!-- Who launches the job? Control-M / TWS-OPC / IWS / Zeke / cron / manual.
     Predecessors, successors, calendar, SLA, criticality. When the
     scheduler metadata is not available, state so explicitly — do not
     fabricate. -->

- **Scheduler:** {{SCHEDULER}}
- **Predecessors:** {{#SCHED_PREDS}}`{{NAME}}`{{^LAST}}, {{/LAST}}{{/SCHED_PREDS}}{{^SCHED_PREDS}}_none recorded_{{/SCHED_PREDS}}
- **Successors:** {{#SCHED_SUCCS}}`{{NAME}}`{{^LAST}}, {{/LAST}}{{/SCHED_SUCCS}}{{^SCHED_SUCCS}}_none recorded_{{/SCHED_SUCCS}}
- **Calendar / cadence:** {{SCHED_CALENDAR}}
- **SLA / criticality:** {{SCHED_SLA}}

## 5. Step inventory

| # | Step | Kind | Target | COND / IF | Expected RC | Notes |
|---|------|------|--------|-----------|-------------|-------|
{{#STEP_INVENTORY}}
| {{STEP_NUMBER}} | `{{STEP_NAME}}` | {{STEP_KIND}} | `{{STEP_TARGET}}` | `{{STEP_COND}}` | `{{STEP_EXPECTED_RC}}` | {{STEP_NOTES}} |
{{/STEP_INVENTORY}}

> `Kind` is one of `PGM` (executes a program), `PROC` (executes a cataloged
> or in-stream procedure), `UTIL` (well-known utility — `IEFBR14`,
> `IEBGENER`, `IDCAMS`, `SORT`/`ICEMAN`, `IKJEFT01`, `DSNUTILB`,
> `BPXBATCH`). `Target` is the program name, the proc name, or the utility
> name. `COND / IF` captures the legacy `COND=` form **and** the modern
> `IF/THEN/ELSE/ENDIF` predicate that gates the step.

## 6. Step details

{{#STEPS}}
---

### 6.{{STEP_NUMBER}}. `{{STEP_NAME}}` — {{STEP_TARGET}}

**Kind:** {{STEP_KIND}} · **Source lines:** L{{STEP_START}}–L{{STEP_END}}

#### EXEC
- **EXEC:** `EXEC {{EXEC_VERB}}={{STEP_TARGET}}`
- **PARM:** `{{PARM}}`
- **COND:** `{{COND}}`
- **IF predicate:** `{{IF_PREDICATE}}`
- **RESTART:** `{{RESTART}}`
- **REGION / TIME / DYNAMNBR overrides:** `{{STEP_OVERRIDES}}`

{{#HAS_PROC_OVERRIDES}}
#### PROC overrides
{{#PROC_SYMBOL_OVERRIDES}}
- Symbolic: `{{PARAM}}` = `{{VALUE}}`
{{/PROC_SYMBOL_OVERRIDES}}
{{#PROC_DD_OVERRIDES}}
- DD override: `{{PROCSTEP}}.{{DD_NAME}}` — `{{OVERRIDE}}`
{{/PROC_DD_OVERRIDES}}
{{/HAS_PROC_OVERRIDES}}

#### DDs
| DD | DSN / source | Kind | Direction | DISP | DCB / SPACE | Notes |
|----|--------------|------|-----------|------|-------------|-------|
{{#DDS}}
| `{{DD_NAME}}` | `{{DSN}}` | {{DD_KIND}} | {{DD_DIRECTION}} | `{{DISP}}` | `{{DCB_OR_SPACE}}` | {{NOTES}} |
{{/DDS}}

> Per-DD `Kind` ∈ `PS`, `PO`, `VSAM-KSDS`, `VSAM-ESDS`, `VSAM-RRDS`,
> `GDG-BASE`, `GDG-GEN`, `TEMP` (`&&NAME`), `SYSOUT`, `INSTREAM` (`DD *`),
> `DUMMY`, `BACKREF` (`*.STEP.DD`), `CONCAT`. `Direction` ∈ `IN`, `OUT`,
> `MOD`, `SHR`, `OLD`, `NEW`. `DISP` MUST be the full triplet
> `(status,normal,abnormal)`.

{{#HAS_INSTREAM}}
#### Instream input
{{#INSTREAM_BLOCKS}}
- `DD {{DD_NAME}}` — see [`{{INSTREAM_FILE}}`]({{INSTREAM_LINK}}){{#INSTREAM_NOTES}} — {{INSTREAM_NOTES}}{{/INSTREAM_NOTES}}
{{/INSTREAM_BLOCKS}}
{{/HAS_INSTREAM}}

#### Return-code contract
- **Expected RC:** `{{STEP_EXPECTED_RC}}`
- **Abend handling:** {{STEP_ABEND_HANDLING}}
- **Downstream gates on this step:** {{#STEP_GATES}}`{{GATING_STEP}}` ({{GATING_COND}}){{^LAST}}, {{/LAST}}{{/STEP_GATES}}{{^STEP_GATES}}_no downstream gate references this step_{{/STEP_GATES}}

{{#STEP_NOTES_LONG}}
#### Notes
{{STEP_NOTES_LONG}}
{{/STEP_NOTES_LONG}}

{{/STEPS}}

## 7. Procedures invoked

| Step | PROC | Source | Origin | Notes |
|------|------|--------|--------|-------|
{{#PROCS_INVOKED}}
| `{{STEP_NAME}}` | `{{PROC_NAME}}` | [`{{PROC_FILE}}`]({{PROC_LINK}}) | {{PROC_ORIGIN}} | {{NOTES}} |
{{/PROCS_INVOKED}}
{{^PROCS_INVOKED}}
| _No procedures invoked._ | — | — | — | — |
{{/PROCS_INVOKED}}

> `Origin` ∈ `CATALOGED` (looked up via `JCLLIB`/SYS1.PROCLIB), `INSTREAM`
> (`// PROC … // PEND` block inside this job), `UNRESOLVED` (referenced
> but no source found in the workspace).
> Use the facts `jcl_steps[].resolved_source`: when non-null the PROC source
> exists in the workspace — render it in `Source` (linked) and set `Origin` to
> `CATALOGED`; only use `UNRESOLVED` when `resolved_source` is null.

## 8. Programs invoked

| Step | PGM | Source | Binding | Notes |
|------|-----|--------|---------|-------|
{{#PROGRAMS_INVOKED}}
| `{{STEP_NAME}}` | `{{PGM_NAME}}` | {{#PGM_FILE}}[`{{PGM_FILE}}`]({{PGM_LINK}}){{/PGM_FILE}}{{^PGM_FILE}}_unresolved_{{/PGM_FILE}} | {{PGM_BINDING}} | {{NOTES}} |
{{/PROGRAMS_INVOKED}}
{{^PROGRAMS_INVOKED}}
| _No programs invoked._ | — | — | — | — |
{{/PROGRAMS_INVOKED}}

> `Binding` ∈ `STATIC` (well-known utility / direct EXEC PGM=), `DYNAMIC`
> (program name passed via `PARM` to a driver like `IKJEFT01`,
> `DSNUTILB`, `BPXBATCH`), `UNRESOLVED`.
> Use the facts `jcl_steps[].resolved_source` to populate `Source` (linked when
> non-null); a null `resolved_source` for a direct `EXEC PGM=` means the load
> module has no documented source in the workspace.

## 9. Datasets touched

| DD | DSN | Kind | Direction | DISP | GDG role | Step(s) | Notes |
|----|-----|------|-----------|------|----------|---------|-------|
{{#DATASETS}}
| `{{DD_NAME}}` | `{{DSN}}` | {{DD_KIND}} | {{DD_DIRECTION}} | `{{DISP}}` | {{GDG_ROLE}} | {{#STEPS_TOUCHING}}`{{STEP}}`{{^LAST}}, {{/LAST}}{{/STEPS_TOUCHING}} | {{NOTES}} |
{{/DATASETS}}
{{^DATASETS}}
| _No datasets referenced._ | — | — | — | — | — | — | — |
{{/DATASETS}}

> `GDG role` ∈ `BASE`, `CURRENT` (`(0)`), `PREVIOUS` (`(-n)`), `NEW`
> (`(+n)`), `—` (not a GDG).

## 10. Symbolic parameters

| Parameter | Default | Required | Overridden by | Notes |
|-----------|---------|----------|---------------|-------|
{{#SYMBOLIC_PARAMS}}
| `{{PARAM}}` | `{{DEFAULT}}` | {{REQUIRED}} | {{#OVERRIDES}}`{{STEP}}`={{VALUE}}{{^LAST}}, {{/LAST}}{{/OVERRIDES}}{{^OVERRIDES}}_—_{{/OVERRIDES}} | {{NOTES}} |
{{/SYMBOLIC_PARAMS}}
{{^SYMBOLIC_PARAMS}}
| _No symbolic parameters declared._ | — | — | — | — |
{{/SYMBOLIC_PARAMS}}

{{#SYSTEM_SYMBOLS_USED}}
> System symbols referenced: {{#SYSTEM_SYMBOLS}}`{{SYMBOL}}`{{^LAST}}, {{/LAST}}{{/SYSTEM_SYMBOLS}}.
{{/SYSTEM_SYMBOLS_USED}}

## 11. External resources

| Kind | Resource | Step | Direction | Notes |
|------|----------|------|-----------|-------|
{{#EXTERNAL_RESOURCES}}
| {{RES_KIND}} | `{{RES_NAME}}` | `{{STEP_NAME}}` | {{RES_DIRECTION}} | {{NOTES}} |
{{/EXTERNAL_RESOURCES}}
{{^EXTERNAL_RESOURCES}}
| _No external resources detected beyond the datasets listed above._ | — | — | — | — |
{{/EXTERNAL_RESOURCES}}

> `Kind` ∈ `DB2-PLAN`, `DB2-PACKAGE`, `DB2-TABLE`, `MQ-QUEUE`, `MQ-MGR`,
> `FTP-SERVER`, `IDCAMS-CMD`, `SORT-CTL`, `BPX-SHELL-CMD`, `REXX-EXEC`,
> `INCLUDE-MEMBER`, `JCLLIB-ENTRY`. Use this table for everything the
> job touches that is **not** a plain dataset (those live in chapter 9).

## 12. Control-flow diagram

<!-- One Mermaid `flowchart TD` showing: job entry → step order →
     COND / IF branches (success path solid, skip path dashed) → abend
     paths to JES exit. Do NOT redraw the per-program logic; this is
     step-level only. Inline Mermaid only — no SVG/image embed, no
     SVG/image link, no `[Open in Draw.io](...)` / `app.diagrams.net`
     link. -->

```mermaid
{{FLOW_MERMAID}}
```
*Figure 1 — replace with a business-language description of the job control flow (≤ 25 words).*

## 13. Return-code contract

| Step | Expected RC | On RC > expected | On abend | Effect on MAXCC |
|------|-------------|------------------|----------|-----------------|
{{#RC_CONTRACT}}
| `{{STEP_NAME}}` | `{{EXPECTED_RC}}` | {{ON_HIGH_RC}} | {{ON_ABEND}} | {{MAXCC_EFFECT}} |
{{/RC_CONTRACT}}

- **Job-level MAXCC contract:** {{MAXCC_CONTRACT}}
- **Downstream consumers gate on:** {{DOWNSTREAM_GATE}}

## 14. Restart and recovery

| Step | Restartable? | Reset actions before restart | Checkpoint dataset | Notes |
|------|--------------|------------------------------|--------------------|-------|
{{#RESTART_MATRIX}}
| `{{STEP_NAME}}` | {{RESTARTABLE}} | {{RESET_ACTIONS}} | `{{CHKPT_DSN}}` | {{NOTES}} |
{{/RESTART_MATRIX}}

{{#RESTART_PROCEDURE}}
> {{RESTART_PROCEDURE}}
{{/RESTART_PROCEDURE}}

## 15. Cross-references

### 15.1 Incoming (what triggers this job)
{{#XREF_INCOMING}}
- {{TYPE}}: `{{SOURCE_REF}}`{{#SOURCE_LINK}} ([`{{SOURCE_FILE_REF}}`]({{SOURCE_LINK}})){{/SOURCE_LINK}}{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_INCOMING}}
{{^XREF_INCOMING}}
- _No incoming trigger detected in workspace._
{{/XREF_INCOMING}}

### 15.2 Outgoing artefacts (datasets / messages produced and consumed downstream)
{{#XREF_OUTGOING}}
- {{KIND}}: `{{NAME}}` consumed by {{#CONSUMERS}}`{{CONSUMER}}`{{^LAST}}, {{/LAST}}{{/CONSUMERS}}{{^CONSUMERS}}_no downstream consumer detected_{{/CONSUMERS}}
{{/XREF_OUTGOING}}
{{^XREF_OUTGOING}}
- _No outgoing artefacts tracked._
{{/XREF_OUTGOING}}

### 15.3 Included members (`JCLLIB` / `INCLUDE`)
{{#INCLUDED_MEMBERS}}
- `{{MEMBER}}` from `{{LIBRARY}}` — {{#MEMBER_LINK}}[`{{MEMBER_FILE}}`]({{MEMBER_LINK}}){{/MEMBER_LINK}}{{^MEMBER_LINK}}_unresolved_{{/MEMBER_LINK}}
{{/INCLUDED_MEMBERS}}
{{^INCLUDED_MEMBERS}}
- _No `INCLUDE` members referenced._
{{/INCLUDED_MEMBERS}}

## 16. Dead / unused rollup

### 16.1 Unreachable steps
{{#DEAD_STEPS}}
- ⚠️ `{{STEP_NAME}}` (L{{STEP_START}}–L{{STEP_END}}) — {{DEAD_REASON}}
{{/DEAD_STEPS}}
{{^DEAD_STEPS}}
- No unreachable steps detected.
{{/DEAD_STEPS}}

### 16.2 Unused DDs
{{#DEAD_DDS}}
- ⚠️ `{{STEP_NAME}}.{{DD_NAME}}` — {{DEAD_REASON}}
{{/DEAD_DDS}}
{{^DEAD_DDS}}
- No unused DD detected.
{{/DEAD_DDS}}

### 16.3 Unused symbolic parameters / overrides
{{#DEAD_SYMBOLS}}
- ⚠️ `{{PARAM}}` declared at L{{DECL_LINE}} — {{DEAD_REASON}}
{{/DEAD_SYMBOLS}}
{{^DEAD_SYMBOLS}}
- No unused symbolic parameter or override detected.
{{/DEAD_SYMBOLS}}

## 17. Migration risks

| Dimension | Value | Risk level | Notes |
|-----------|-------|------------|-------|
| GDG datasets | {{RISK_GDG_COUNT}} | {{RISK_GDG_LEVEL}} | {{RISK_GDG_NOTES}} |
| VSAM clusters | {{RISK_VSAM_COUNT}} | {{RISK_VSAM_LEVEL}} | {{RISK_VSAM_NOTES}} |
| Tape volumes (`UNIT=TAPE`, `VOL=SER=`) | {{RISK_TAPE_COUNT}} | {{RISK_TAPE_LEVEL}} | {{RISK_TAPE_NOTES}} |
| DB2 batch utilities | {{RISK_DB2_COUNT}} | {{RISK_DB2_LEVEL}} | {{RISK_DB2_NOTES}} |
| IDCAMS inline scripts | {{RISK_IDCAMS_COUNT}} | {{RISK_IDCAMS_LEVEL}} | {{RISK_IDCAMS_NOTES}} |
| SORT control statements | {{RISK_SORT_COUNT}} | {{RISK_SORT_LEVEL}} | {{RISK_SORT_NOTES}} |
| JES-specific routing (`/*ROUTE`, `/*JOBPARM`, `MSGCLASS`) | {{RISK_JES_COUNT}} | {{RISK_JES_LEVEL}} | {{RISK_JES_NOTES}} |
| Dynamic PGM resolution (`IKJEFT01`, `BPXBATCH`) | {{RISK_DYNPGM_COUNT}} | {{RISK_DYNPGM_LEVEL}} | {{RISK_DYNPGM_NOTES}} |
| System-symbol dependencies | {{RISK_SYSSYM_COUNT}} | {{RISK_SYSSYM_LEVEL}} | {{RISK_SYSSYM_NOTES}} |

## 18. Warnings
{{#WARNINGS}}
- ⚠️ {{WARNING_TEXT}}{{#WARNING_CITATION}} [^src-{{WARNING_CITATION}}]{{/WARNING_CITATION}}
{{/WARNINGS}}
{{^WARNINGS}}
- _No warnings._
{{/WARNINGS}}

## 19. Citations
{{#CITATIONS}}
[^src-{{CITATION_ID}}]: `{{CITATION_FILE}}` L{{CITATION_START}}–L{{CITATION_END}} — confidence: **{{CITATION_CONFIDENCE}}**, evidence: {{CITATION_EVIDENCE_KIND}}.{{#CITATION_NOTE}} {{CITATION_NOTE}}{{/CITATION_NOTE}}
{{/CITATIONS}}
{{^CITATIONS}}
_No citations recorded._
{{/CITATIONS}}

---

### Authoring self-check
- [ ] YAML front-matter populated (source path, SHA-256, line count, job
      name, generation timestamp, language).
- [ ] `Summary` is 2–3 sentences and uses business vocabulary — no `EXEC`,
      `DD`, `COND`, `RC` jargon.
- [ ] `Job header` table reflects the actual `JOB` statement; missing
      attributes are rendered as `—`, never invented.
- [ ] `Triggers and scheduling` either names the scheduler and the
      predecessors/successors, or explicitly states the metadata is not
      available — no fabrication.
- [ ] `Step inventory` lists every step in source order and uses the
      canonical `Kind` taxonomy (`PGM` / `PROC` / `UTIL`).
- [ ] `Step details` includes, per step: EXEC, PROC overrides (when
      applicable), DD table with the canonical `Kind`/`Direction`/full
      `DISP` triplet, instream input references, and an RC contract.
- [ ] `Procedures invoked` and `Programs invoked` tables link to the
      target documents when resolved and surface `UNRESOLVED` otherwise.
- [ ] `Datasets touched` uses the canonical `Kind` and `GDG role`
      taxonomies; `DISP` is the full triplet.
- [ ] `Symbolic parameters` table records defaults, required-flag and
      per-step overrides; system symbols are listed separately.
- [ ] `External resources` covers DB2 / MQ / FTP / IDCAMS / SORT /
      BPXBATCH / REXX / INCLUDE / JCLLIB — anything that is **not** a
      plain dataset.
- [ ] `Control-flow diagram` is a `flowchart TD` of step order plus
      `COND`/`IF` branches plus abend paths. No `app.diagrams.net` /
      Draw.io link.
- [ ] Every Mermaid diagram in the document is immediately followed by
      an italicised caption line `*Figure N — <description>.*` with
      sequential figure numbering starting at 1.
- [ ] `Return-code contract` is filled for every step and the job-level
      MAXCC contract is stated.
- [ ] `Restart and recovery` covers every step (restartable yes/no,
      reset actions, checkpoint dataset).
- [ ] `Cross-references` covers incoming triggers, outgoing artefacts
      and included members. Internal pipeline artefacts
      (`chunk-manifest.json`, `facts.json`, `docs/_shared/**`,
      `docs/_modernization/**`) are NOT linked.
- [ ] `Dead / unused rollup` separately lists unreachable steps, unused
      DDs and unused symbolic parameters / overrides.
- [ ] `Migration risks` table is fully populated (every dimension has a
      count, level and note); zero counts are rendered as `0`, never
      omitted.
- [ ] No `[FILE:Lx-Ly]` inline tags survive anywhere.
- [ ] No self-descriptive banner ("Self-contained document. Bundles…
      from facts.json…", "Mandatory section — never leave empty") is
      present in rendered prose — all authoring guidance lives in HTML
      comments only.
