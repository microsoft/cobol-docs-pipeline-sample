---
group_id: "{{GROUP_ID}}"
grouping_strategy: "{{GROUPING_STRATEGY}}"
member_count: {{MEMBER_COUNT}}
program_count: {{PROGRAM_COUNT}}
jcl_count: {{JCL_COUNT}}
generated_at: "{{GENERATED_AT}}"
language: "{{LANG}}"
---

# Flow — `{{GROUP_ID}}`

<!-- Cross-source business-flow deliverable. ONE flow = one end-to-end
     business process that may span multiple programs, JCL jobs, online
     transactions and integrations.

     SCOPE BOUNDARY: the step-level graph of a SINGLE JCL job lives in
     `jcl-job.template.md` (chapter 12) — do NOT duplicate it here. This
     template is meant for `manifest` and `call-graph` groupings; when
     `{{GROUPING_STRATEGY}}` is `jcl-job` the flow doc should be a thin
     pointer to the underlying jcl-job document rather than a re-render.

     FORBIDDEN per .github/instructions/no-generator-boilerplate.instructions.md:
       * `[Open in Draw.io](app.diagrams.net/...)` links
       * `[FILE:Lx-Ly]` inline tags
       * self-descriptive banners ("Self-contained document. Bundles…
         from facts.json…", "Mandatory section — never leave empty")
       * links to internal pipeline artefacts (`chunk-manifest.json`,
         `facts.json`, `docs/_shared/**`, `docs/_modernization/**`). -->

> **Group:** `{{GROUP_ID}}` · **Strategy:** {{GROUPING_STRATEGY}} (`manifest` / `jcl-job` / `call-graph`)
> **Members:** {{MEMBER_COUNT}} ({{PROGRAM_COUNT}} programs · {{JCL_COUNT}} JCL jobs · {{OTHER_COUNT}} other)
> **Generated:** {{GENERATED_AT}} · **Language:** {{LANG}}

## 1. Summary

<!-- 2–3 sentences. The business outcome of the flow, who triggers it,
     what changes in the system once it has run. No COBOL / JCL jargon. -->

{{TLDR}}

## 2. Purpose

<!-- 1–2 paragraphs. Where this flow sits in the business chain, which
     functional capability it implements, and which value it produces.
     Do NOT enumerate members here — that is chapter 4. -->

{{PURPOSE}}

## 3. Trigger and termination contract

### 3.1 Triggers (what starts the flow)
{{#TRIGGERS}}
- **{{TRIGGER_KIND}}**: `{{TRIGGER_REF}}`{{#TRIGGER_SCHEDULE}} — schedule: {{TRIGGER_SCHEDULE}}{{/TRIGGER_SCHEDULE}}{{#TRIGGER_NOTES}} — {{TRIGGER_NOTES}}{{/TRIGGER_NOTES}}
{{/TRIGGERS}}
{{^TRIGGERS}}
- _No trigger recorded._
{{/TRIGGERS}}

> `Trigger kind` ∈ `JCL-JOB`, `CICS-TRANSID`, `MQ-MESSAGE`,
> `FILE-WATCH`, `SCHEDULER` (Control-M / TWS-OPC / IWS), `MANUAL`,
> `UPSTREAM-FLOW`.

### 3.2 Terminations (what the flow leaves behind)
{{#TERMINATIONS}}
- **{{TERM_KIND}}**: `{{TERM_REF}}`{{#TERM_NOTES}} — {{TERM_NOTES}}{{/TERM_NOTES}}
{{/TERMINATIONS}}
{{^TERMINATIONS}}
- _No termination recorded._
{{/TERMINATIONS}}

> `Termination kind` ∈ `DATASET-PRODUCED`, `DB2-TABLE-UPDATED`,
> `MQ-MESSAGE-EMITTED`, `CICS-RESPONSE`, `RETURN-CODE`,
> `DOWNSTREAM-FLOW-RELEASED`.

## 4. Members

| Order | Member | Kind | Role | Coverage | Doc |
|-------|--------|------|------|----------|-----|
{{#MEMBERS}}
| {{ORDER}} | `{{MEMBER_NAME}}` | {{MEMBER_KIND}} | {{MEMBER_ROLE}} | {{MEMBER_COVERAGE}} | [`{{MEMBER_NAME}}`]({{LANG_ROOT}}/{{MEMBER_NAME}}/index.md) |
{{/MEMBERS}}

> `Kind` ∈ `COBOL-PGM`, `JCL-JOB`, `PROC`, `COPYBOOK`, `DCLGEN`,
> `BMS-MAP`, `REXX`, `IDCAMS-SCRIPT`, `SORT-CTL`. `Role` ∈ `ENTRY`
> (kicks the flow), `INTERMEDIATE`, `TERMINAL` (closes the flow),
> `SUPPORT` (called/included by another member). `Coverage` ∈ `FULL`
> (every section of the member participates) or `PARTIAL` (only some
> sections; member is shared with other flows — see chapter 10).

## 5. End-to-end flow

<!-- Pick the diagram type by flow shape:
       * batch chain → `flowchart LR`
       * online conversation → `sequenceDiagram`
     Nodes = members. Edges carry the handoff label (dataset / DB2
     table / MQ queue / CICS commarea). Trigger and termination nodes
     MUST be styled distinctly from intermediate members. Do NOT walk
     per-paragraph COBOL verbs — those belong to procedure-section
     diagrams. Inline Mermaid only — no SVG/image embed, no SVG/image
     link, no `[Open in Draw.io](...)` / `app.diagrams.net` link. -->

```mermaid
{{FLOW_MERMAID}}
```
*Figure 1 — replace with a business-language description of the end-to-end flow (≤ 25 words).*

## 6. Step sequence

| # | Step | Member | Operation | Handoff in | Handoff out | Sync? | Failure mode |
|---|------|--------|-----------|------------|-------------|-------|--------------|
{{#STEPS}}
| {{STEP_NUMBER}} | {{STEP_NAME}} | `{{STEP_MEMBER}}` | {{STEP_OPERATION}} | `{{STEP_IN}}` | `{{STEP_OUT}}` | {{STEP_SYNC}} | {{STEP_FAILURE}} |
{{/STEPS}}

> `Sync?` ∈ `SYNC` (in-process `CALL`/`LINK`/`PERFORM`), `ASYNC`
> (MQ / file handoff / decoupled DB2 row), `SCHEDULED` (next JCL job
> in the chain released by the scheduler).

## 7. Data flow

<!-- How business data — not control — moves through the flow:
     input dataset → enrichment → DB2 table → extract → output
     dataset. Either a table or a `flowchart LR` focused on data
     payloads, NOT on member invocation order. Business analysts
     read this chapter first. -->

{{#DATA_FLOW_DIAGRAM}}
```mermaid
{{DATA_FLOW_DIAGRAM}}
```
*Figure 2 — replace with a business-language description of the data flow (≤ 25 words).*
{{/DATA_FLOW_DIAGRAM}}

| # | Payload | Origin | Transformation | Destination | Volume | Notes |
|---|---------|--------|----------------|-------------|--------|-------|
{{#DATA_FLOW_STEPS}}
| {{DF_NUMBER}} | `{{DF_PAYLOAD}}` | `{{DF_ORIGIN}}` | {{DF_TRANSFORM}} | `{{DF_DESTINATION}}` | {{DF_VOLUME}} | {{DF_NOTES}} |
{{/DATA_FLOW_STEPS}}

## 8. External integrations

| Kind | Endpoint | Direction | Member | Notes |
|------|----------|-----------|--------|-------|
{{#INTEGRATIONS}}
| {{KIND}} | `{{ENDPOINT}}` | {{DIRECTION}} | `{{MEMBER_NAME}}` | {{NOTES}} |
{{/INTEGRATIONS}}
{{^INTEGRATIONS}}
| _No external integration detected._ | — | — | — | — |
{{/INTEGRATIONS}}

> `Kind` ∈ `FILE`, `VSAM-CLUSTER`, `DB2-TABLE`, `DB2-CURSOR`,
> `CICS-TS-QUEUE`, `CICS-TD-QUEUE`, `CICS-MAP`, `MQ-QUEUE`, `MQ-TOPIC`,
> `FTP-SERVER`, `REST-API`, `SOAP-API`, `EMAIL`, `PRINTER`. `Direction`
> ∈ `IN`, `OUT`, `I/O`.

## 9. Touched resources (rollup)

### 9.1 Datasets
{{#TOUCHED_DATASETS}}
- `{{NAME}}` — {{DIRECTION}}{{#KIND}} ({{KIND}}){{/KIND}} — touched by {{#MEMBERS}}`{{MEMBER}}`{{^LAST}}, {{/LAST}}{{/MEMBERS}}
{{/TOUCHED_DATASETS}}
{{^TOUCHED_DATASETS}}
- _No datasets touched._
{{/TOUCHED_DATASETS}}

### 9.2 DB2 tables / cursors
{{#TOUCHED_DB2}}
- `{{NAME}}` — {{DIRECTION}} — verbs: {{#VERBS}}`{{VERB}}`{{^LAST}}, {{/LAST}}{{/VERBS}} — touched by {{#MEMBERS}}`{{MEMBER}}`{{^LAST}}, {{/LAST}}{{/MEMBERS}}
{{/TOUCHED_DB2}}
{{^TOUCHED_DB2}}
- _No DB2 access detected._
{{/TOUCHED_DB2}}

### 9.3 MQ queues / topics
{{#TOUCHED_MQ}}
- `{{NAME}}` — {{DIRECTION}} — touched by {{#MEMBERS}}`{{MEMBER}}`{{^LAST}}, {{/LAST}}{{/MEMBERS}}
{{/TOUCHED_MQ}}
{{^TOUCHED_MQ}}
- _No MQ access detected._
{{/TOUCHED_MQ}}

### 9.4 CICS resources
{{#TOUCHED_CICS}}
- {{KIND}}: `{{NAME}}` — touched by {{#MEMBERS}}`{{MEMBER}}`{{^LAST}}, {{/LAST}}{{/MEMBERS}}
{{/TOUCHED_CICS}}
{{^TOUCHED_CICS}}
- _No CICS resources accessed._
{{/TOUCHED_CICS}}

### 9.5 Programs called from outside the group
{{#CALLED_IN}}
- `{{PROGRAM}}` ← `{{CALLER}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/CALLED_IN}}
{{^CALLED_IN}}
- _No external caller reaches into this flow._
{{/CALLED_IN}}

### 9.6 Programs in the group calling out
{{#CALLED_OUT}}
- `{{PROGRAM}}` → `{{CALLEE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/CALLED_OUT}}
{{^CALLED_OUT}}
- _This flow does not call out to external programs._
{{/CALLED_OUT}}

## 10. Boundary

### 10.1 Upstream flows (produce our inputs)
{{#UPSTREAM_FLOWS}}
- [`{{UPSTREAM_GROUP_ID}}`]({{LANG_ROOT}}/../flows/{{UPSTREAM_GROUP_ID}}/flow.md) — handoff: `{{HANDOFF}}`
{{/UPSTREAM_FLOWS}}
{{^UPSTREAM_FLOWS}}
- _No upstream flow recorded._
{{/UPSTREAM_FLOWS}}

### 10.2 Downstream flows (consume our outputs)
{{#DOWNSTREAM_FLOWS}}
- [`{{DOWNSTREAM_GROUP_ID}}`]({{LANG_ROOT}}/../flows/{{DOWNSTREAM_GROUP_ID}}/flow.md) — handoff: `{{HANDOFF}}`
{{/DOWNSTREAM_FLOWS}}
{{^DOWNSTREAM_FLOWS}}
- _No downstream flow recorded._
{{/DOWNSTREAM_FLOWS}}

### 10.3 Shared members (also belong to other flows)
{{#SHARED_MEMBERS}}
- `{{MEMBER_NAME}}` — also in {{#OTHER_FLOWS}}[`{{OTHER_GROUP_ID}}`]({{LANG_ROOT}}/../flows/{{OTHER_GROUP_ID}}/flow.md){{^LAST}}, {{/LAST}}{{/OTHER_FLOWS}}
{{/SHARED_MEMBERS}}
{{^SHARED_MEMBERS}}
- _No member is shared with another flow._
{{/SHARED_MEMBERS}}

## 11. SLA, volumes, recovery, security, compliance

| Dimension | Value | Notes |
|-----------|-------|-------|
| Start window | {{SLA_START}} | |
| End-of-day deadline | {{SLA_DEADLINE}} | |
| Latency target | {{SLA_LATENCY}} | |
| Volume (records/run) | {{VOLUME_RECORDS}} | |
| Volume (files/run) | {{VOLUME_FILES}} | |
| Volume (msgs/sec, online) | {{VOLUME_MSGS}} | |
| Restartability | {{RECOVERY_RESTART}} | |
| Idempotency | {{RECOVERY_IDEMPOTENT}} | |
| Replayability | {{RECOVERY_REPLAY}} | |
| PII categories crossed | {{SEC_PII}} | |
| Encryption at rest / in flight | {{SEC_ENCRYPTION}} | |
| RACF / authorisation profiles | {{SEC_AUTH}} | |
| Data residency | {{COMPL_RESIDENCY}} | |
| Retention | {{COMPL_RETENTION}} | |
| Audit log | {{COMPL_AUDIT}} | |

## 12. Failure modes and blast radius

| Failure | Where it surfaces | Detection | Blast radius | Mitigation |
|---------|-------------------|-----------|--------------|------------|
{{#FAILURE_MODES}}
| {{FAILURE}} | `{{FAILURE_WHERE}}` | {{FAILURE_DETECTION}} | {{FAILURE_BLAST}} | {{FAILURE_MITIGATION}} |
{{/FAILURE_MODES}}
{{^FAILURE_MODES}}
| _No failure modes recorded._ | — | — | — | — |
{{/FAILURE_MODES}}

## 13. Dead / unused rollup

### 13.1 Unreached members
{{#DEAD_MEMBERS}}
- ⚠️ `{{MEMBER_NAME}}` — declared in the grouping but never reached by the flow Mermaid. Reason: {{DEAD_REASON}}.
{{/DEAD_MEMBERS}}
{{^DEAD_MEMBERS}}
- All declared members participate in the flow.
{{/DEAD_MEMBERS}}

### 13.2 Declared but unobserved integrations
{{#DEAD_INTEGRATIONS}}
- ⚠️ {{KIND}}: `{{ENDPOINT}}` — declared but no member actually accesses it.
{{/DEAD_INTEGRATIONS}}
{{^DEAD_INTEGRATIONS}}
- All declared integrations are observed.
{{/DEAD_INTEGRATIONS}}

### 13.3 Declared but unenforced constraints
{{#DEAD_CONSTRAINTS}}
- ⚠️ {{CONSTRAINT}} — declared in chapter 11 but no member implements it.
{{/DEAD_CONSTRAINTS}}
{{^DEAD_CONSTRAINTS}}
- All declared constraints are enforced.
{{/DEAD_CONSTRAINTS}}

## 14. Migration risks

| Dimension | Value | Risk level | Notes |
|-----------|-------|------------|-------|
| GDG datasets in the chain | {{RISK_GDG_COUNT}} | {{RISK_GDG_LEVEL}} | {{RISK_GDG_NOTES}} |
| VSAM clusters | {{RISK_VSAM_COUNT}} | {{RISK_VSAM_LEVEL}} | {{RISK_VSAM_NOTES}} |
| DB2 batch utility invocations | {{RISK_DB2_COUNT}} | {{RISK_DB2_LEVEL}} | {{RISK_DB2_NOTES}} |
| MQ async handoffs | {{RISK_MQ_COUNT}} | {{RISK_MQ_LEVEL}} | {{RISK_MQ_NOTES}} |
| Online ↔ batch handoffs | {{RISK_TIER_HANDOFFS}} | {{RISK_TIER_LEVEL}} | {{RISK_TIER_NOTES}} |
| `EXEC CICS START` / scheduled CICS triggers | {{RISK_CICS_START_COUNT}} | {{RISK_CICS_START_LEVEL}} | {{RISK_CICS_START_NOTES}} |
| Shared members (cross-flow coupling) | {{RISK_SHARED_COUNT}} | {{RISK_SHARED_LEVEL}} | {{RISK_SHARED_NOTES}} |
| Dynamic call / unresolved targets | {{RISK_DYN_COUNT}} | {{RISK_DYN_LEVEL}} | {{RISK_DYN_NOTES}} |

## 15. Warnings
{{#WARNINGS}}
- ⚠️ {{WARNING_TEXT}}{{#WARNING_CITATION}} [^src-{{WARNING_CITATION}}]{{/WARNING_CITATION}}
{{/WARNINGS}}
{{^WARNINGS}}
- _No warnings._
{{/WARNINGS}}

## 16. References
- IT↔EN glossary: [{{GLOSSARY_PATH}}]({{GLOSSARY_PATH}})
{{#ALT_LANG_LINK}}
- {{ALT_LANG_LABEL}}: [{{ALT_LANG_PATH}}]({{ALT_LANG_PATH}})
{{/ALT_LANG_LINK}}

## Citations
{{#CITATIONS}}
[^src-{{CITATION_ID}}]: `{{CITATION_FILE}}` L{{CITATION_START}}–L{{CITATION_END}} — confidence: **{{CITATION_CONFIDENCE}}**, evidence: {{CITATION_EVIDENCE_KIND}}.{{#CITATION_NOTE}} {{CITATION_NOTE}}{{/CITATION_NOTE}}
{{/CITATIONS}}
{{^CITATIONS}}
_No citations recorded at the flow level. Member documents define their
own `[^src-N]` footnotes scoped to their own files._
{{/CITATIONS}}

---

### Authoring self-check
- [ ] YAML front-matter populated (group id, grouping strategy, member
      counts, generation timestamp, language).
- [ ] `Summary` is 2–3 sentences and uses business vocabulary — no COBOL
      verbs, no JCL DD jargon.
- [ ] When `grouping_strategy` is `jcl-job`, the document is a thin
      pointer to the underlying `jcl-job.md` and does NOT duplicate its
      chapter 12 step diagram.
- [ ] `Trigger and termination contract` uses the canonical
      trigger-kind and termination-kind taxonomies.
- [ ] `Members` table is in execution order, uses the canonical `Kind`
      and `Role` taxonomies, and flags `PARTIAL` coverage when a member
      is shared with other flows.
- [ ] `End-to-end flow` Mermaid picks the right shape (`flowchart LR`
      for batch chains, `sequenceDiagram` for online conversations).
      Trigger / termination nodes are styled distinctly. No
      `app.diagrams.net` / Draw.io link.
- [ ] Every Mermaid diagram in the document is immediately followed by
      an italicised caption line `*Figure N — <description>.*` with
      sequential figure numbering starting at 1.
- [ ] `Step sequence` carries the `Sync?` column with one of `SYNC`,
      `ASYNC`, `SCHEDULED` and a non-empty `Failure mode`.
- [ ] `Data flow` chapter exists and is focused on business payloads —
      not on member invocation order (which is chapter 6).
- [ ] `External integrations` uses the canonical `Kind` taxonomy
      (shared with `source-complete` chapter 4.4 and `jcl-job`
      chapter 11).
- [ ] `Touched resources` rollups (datasets, DB2, MQ, CICS, called-in,
      called-out) are emitted even when empty (with a `No … detected`
      line).
- [ ] `Boundary` chapter lists upstream flows, downstream flows AND
      shared members. Cross-links use `{{LANG_ROOT}}` — never
      hard-coded `../../en/` or `../../it/` paths.
- [ ] `SLA, volumes, recovery, security, compliance` table is fully
      populated; unknown values are rendered as `—`, never invented.
- [ ] `Failure modes and blast radius` is filled at flow level — not a
      copy of per-step abend behaviour.
- [ ] `Dead / unused rollup` separately lists unreached members,
      unobserved integrations and unenforced constraints.
- [ ] `Migration risks` table is fully populated; zero counts are
      rendered as `0`, never omitted.
- [ ] `References` link to the IT↔EN glossary and (when applicable) the
      cross-language version. Internal pipeline artefacts
      (`chunk-manifest.json`, `facts.json`, `docs/_shared/**`,
      `docs/_modernization/**`) are NOT linked.
- [ ] No `[FILE:Lx-Ly]` inline tags survive anywhere.
- [ ] No self-descriptive banner ("Self-contained document. Bundles…
      from facts.json…", "Mandatory section — never leave empty") is
      present in rendered prose — all authoring guidance lives in HTML
      comments only.
