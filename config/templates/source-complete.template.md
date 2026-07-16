---
source_file: "{{SOURCE_FILE}}"
source_path: "{{SOURCE_PATH}}"
source_type: "{{SOURCE_TYPE}}"
sha256: "{{SHA256}}"
total_lines: {{TOTAL_LINES}}
generated_at: "{{GENERATED_AT}}"
profile_fa: "{{PROFILE_FA}}"
profile_req: "{{PROFILE_REQ}}"
language: "{{LANG}}"
---

# Complete document — `{{SOURCE_FILE}}`

<!-- Single-file deliverable that integrates the operational summary, the
     division-level overviews, the per-section narrative, the functional
     analysis, the requirements, and the links to the M1–M14 modernization
     artefacts. The previous self-descriptive banner ("Omni-comprehensive,
     self-contained… bundles… from facts.json…") is FORBIDDEN per
     .github/instructions/no-generator-boilerplate.instructions.md and must
     NEVER be re-introduced. All authoring guidance in this template lives in
     HTML comments — never as rendered prose inside numbered sections. -->

> **Source:** `{{SOURCE_PATH}}`
> **Type:** {{SOURCE_TYPE}} · **SHA-256:** `{{SHA256}}` · **Lines:** {{TOTAL_LINES}}
> **Generated:** {{GENERATED_AT}} · **Language:** {{LANG}} · **FA profile:** {{PROFILE_FA}} · **Req profile:** {{PROFILE_REQ}}

## 1. Operational summary

<!-- One short paragraph (≤ 6 sentences) answering: which business process this
     program implements, which JCL job / CICS transaction triggers it, which
     upstream feeds it consumes, which downstream artefacts it produces, and
     which return-code / commarea contract it honours with its caller. No
     COBOL jargon, no line counts. This is the ONE paragraph a reader who
     only opens the document for 30 seconds will read. -->

{{OPERATIONAL_SUMMARY}}

## 2. High-level flow

<!-- Coarse end-to-end picture: entry → main phases → exits, plus the major
     external dependencies (files, DB2 tables, queues, called programs).
     Decision branches, loops and individual I/O verbs belong to the
     per-section diagrams in chapter 7, NOT here.
     Diagrams are emitted as inline Mermaid only — no pre-rendered SVG
     embeds, no SVG/image links, no `app.diagrams.net` / Draw.io links. -->

```mermaid
{{OVERVIEW_MERMAID}}
```
*Figure 1 — replace with a business-language description of the overview (≤ 25 words).*

### 2.1 Section-by-section map

<!-- Discursive prose summary covering every section in execution order. Each
     paragraph fuses _what the section is about_ (purpose), _how it works_
     (logic in one or two sentences) and _where it sits in the run_ (flow
     position). Group related sections when it improves readability. Do NOT
     emit a bulleted list of section names. Do NOT repeat textbook
     definitions of COBOL divisions — jump straight to the concrete content
     of THIS program. The full per-section narrative (with its own diagram)
     lives in chapter 7. -->

{{SECTION_BY_SECTION_PROSE}}

## 3. Release history

### 3.1 Recent releases (latest 3–5)
{{#RELEASE_HISTORY_RECENT}}
- **{{REL_DATE}}** · {{REL_AUTHOR}}{{#REL_TAG}} _(tag: {{REL_TAG}})_{{/REL_TAG}} — {{REL_DESCRIPTION}}[^src-{{REL_CITATION}}]
{{/RELEASE_HISTORY_RECENT}}
{{^RELEASE_HISTORY_RECENT}}
- _No release banner detected in the source._
{{/RELEASE_HISTORY_RECENT}}

### 3.2 Earlier history (summary)

<!-- Single summarising paragraph: date range, total entries, recurring
     authors, dominant themes. Do NOT enumerate every historical entry one
     by one. -->

{{#RELEASE_HISTORY_SUMMARY}}
{{RELEASE_HISTORY_SUMMARY}}
{{/RELEASE_HISTORY_SUMMARY}}
{{^RELEASE_HISTORY_SUMMARY}}
_No earlier entries beyond those listed above._
{{/RELEASE_HISTORY_SUMMARY}}

## 4. Cross-references

### 4.1 Incoming callers (programs / JCL that invoke this one)
{{#XREF_CALLERS}}
- {{TYPE}}: `{{SOURCE_REF}}` — `{{SOURCE_FILE_REF}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_CALLERS}}
{{^XREF_CALLERS}}
- _No incoming caller detected in workspace._
{{/XREF_CALLERS}}

### 4.2 Outgoing callees (programs this one invokes)
{{#XREF_CALLEES}}
- {{TYPE}}: `{{TARGET}}`{{#TARGET_FILE}} (`{{TARGET_FILE}}`){{/TARGET_FILE}}{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_CALLEES}}
{{^XREF_CALLEES}}
- _No outgoing calls detected._
{{/XREF_CALLEES}}

### 4.3 JCL / triggers that schedule this program
{{#XREF_JCL}}
- {{TYPE}}: `{{TARGET}}` — `{{TARGET_FILE}}`{{#NOTES}} — {{NOTES}}{{/NOTES}}
{{/XREF_JCL}}
{{^XREF_JCL}}
- _No JCL or CICS trigger detected in workspace._
{{/XREF_JCL}}

### 4.4 External dependencies (datasets / tables / queues / maps / copybooks)
| Kind | Name | Direction | Notes |
|------|------|-----------|-------|
{{#EXTERNAL_DEPS}}
| {{KIND}} | `{{NAME}}` | {{DIRECTION}} | {{NOTES}} |
{{/EXTERNAL_DEPS}}
{{^EXTERNAL_DEPS}}
| _No external dependencies detected._ | — | — | — |
{{/EXTERNAL_DEPS}}

> `Kind` is one of `FILE`, `VSAM-CLUSTER`, `DB2-TABLE`, `DB2-CURSOR`,
> `CICS-TS-QUEUE`, `CICS-TD-QUEUE`, `CICS-MAP`, `MQ-QUEUE`, `COPYBOOK`,
> `DCLGEN`, `PROGRAM`, `PRINTER`, `CONSOLE`. `Direction` is `IN`, `OUT`,
> `I/O`, `INCLUDE`, `CALL`.

## 5. Dead / unreachable rollup

### 5.1 Unreachable sections / paragraphs
{{#DEAD_SECTIONS}}
- ⚠️ **{{DEAD_KIND}}** `{{DEAD_NAME}}` (L{{DEAD_START}}–L{{DEAD_END}}) — {{DEAD_REASON}}
{{/DEAD_SECTIONS}}
{{^DEAD_SECTIONS}}
- No unreachable sections or paragraphs detected.
{{/DEAD_SECTIONS}}

### 5.2 Orphan declarations (FDs, SELECTs, copybooks, fields)
{{#DEAD_DECLARATIONS}}
- ⚠️ **{{DEAD_KIND}}** `{{DEAD_NAME}}` (L{{DEAD_START}}–L{{DEAD_END}}) — {{DEAD_REASON}}
{{/DEAD_DECLARATIONS}}
{{^DEAD_DECLARATIONS}}
- No orphan declarations detected.
{{/DEAD_DECLARATIONS}}

### 5.3 Unresolved dynamic CALLs / EXEC CICS targets
{{#UNRESOLVED_TARGETS}}
- ⚠️ {{TARGET_KIND}}: `{{TARGET_REF}}` resolved from `{{TARGET_SOURCE}}` — {{TARGET_REASON}}
{{/UNRESOLVED_TARGETS}}
{{^UNRESOLVED_TARGETS}}
- All call / link / xctl targets resolve statically.
{{/UNRESOLVED_TARGETS}}

## 6. Divisions

<!-- Embed (or link, when the source is non-COBOL) the four division-level
     overview documents in canonical order. Each division overview is a
     standalone document with its own Summary, Purpose, tables and migration
     risks — produced from identification-division.template.md,
     environment-division.template.md, data-division.template.md and
     procedure-division.template.md. Do NOT duplicate their narrative here;
     embed the rendered body verbatim. -->

### 6.1 IDENTIFICATION DIVISION
{{IDENTIFICATION_DIVISION_BODY}}

### 6.2 ENVIRONMENT DIVISION
{{ENVIRONMENT_DIVISION_BODY}}

### 6.3 DATA DIVISION
{{DATA_DIVISION_BODY}}

### 6.4 PROCEDURE DIVISION
{{PROCEDURE_DIVISION_BODY}}

## 7. Sections (inline, full content)

<!-- Sections are listed in the order they appear in the source program
     (ascending start_line). EVERY section file under `sections/` MUST be
     embedded here — none omitted, none reordered. Per-section bodies come
     from procedure-section-doc.template.md and already contain their own
     Summary, entry/exit contracts, flow, side effects and citations. -->

{{#SECTIONS}}
---

### 7.{{SECTION_NUMBER}}. {{SECTION_NAME}} _(L{{START_LINE}}–L{{END_LINE}}, {{CHUNK_KIND}}, reachability: {{REACHABILITY}})_

{{SECTION_BODY_INLINE}}
{{/SECTIONS}}

## 8. Functional analysis
{{FUNCTIONAL_ANALYSIS_BODY}}

## 9. Requirements
{{REQUIREMENTS_BODY}}

## 10. Modernization artifacts (M1–M14)

<!-- Render one bullet per canonical M-step. When an artefact has not been
     produced, render the placeholder bullet ("not produced") so the reader
     can see what is missing rather than silently skipping it. -->

{{#MOD_ARTIFACTS_CANONICAL}}
- **{{MOD_LABEL}}** — {{#MOD_FILE}}[{{MOD_TITLE}}]({{MOD_ROOT}}/{{SOURCE_FILE}}/{{MOD_FILE}}){{/MOD_FILE}}{{^MOD_FILE}}_not produced_{{/MOD_FILE}}
{{/MOD_ARTIFACTS_CANONICAL}}

## 11. Coverage & quality
- [Paragraph coverage](./_coverage.md)
- [Sensitive data (PII)](./_sensitive-data.md)

## 12. References
- IT↔EN glossary: [{{GLOSSARY_PATH}}]({{GLOSSARY_PATH}})
{{#ALT_LANG_LINK}}
- {{ALT_LANG_LABEL}}: [{{ALT_LANG_PATH}}]({{ALT_LANG_PATH}})
{{/ALT_LANG_LINK}}

<!-- Internal pipeline artefacts (chunk-manifest.json, facts.json,
     docs/_shared/**, docs/_modernization/**) MUST NOT be linked from a
     human-facing deliverable. See
     .github/instructions/no-generator-boilerplate.instructions.md. -->

## Citations

<!-- Pandoc footnote definitions for every `[^src-N]` marker emitted by the
     release-history block above AND for any marker that survives in the
     embedded division / section bodies. Generated from facts.json; never
     hand-edit. -->

{{#CITATIONS}}
[^src-{{CITATION_ID}}]: `{{CITATION_FILE}}` L{{CITATION_START}}–L{{CITATION_END}} — confidence: **{{CITATION_CONFIDENCE}}**, evidence: {{CITATION_EVIDENCE_KIND}}.{{#CITATION_NOTE}} {{CITATION_NOTE}}{{/CITATION_NOTE}}
{{/CITATIONS}}
{{^CITATIONS}}
_No citations emitted at the file level. The embedded division and section
bodies define their own `[^src-N]` footnotes scoped to their own ranges._
{{/CITATIONS}}

---

<!-- Authoring self-check. MUST be evaluated by the generator before emitting
     the document; any unchecked box is a hard failure surfaced in the lint
     report. Do NOT delete this block — it is the contract that keeps the
     deliverable honest. -->

### Authoring self-check
- [ ] Front-matter YAML is populated (source path, SHA-256, line count,
      generation timestamp, profiles, language).
- [ ] `Operational summary` is one paragraph, ≤ 6 sentences, no COBOL
      jargon, and names the trigger (JCL job / CICS transid), the
      upstream feeds and the downstream artefacts.
- [ ] `High-level flow` is an inline Mermaid block only — no SVG/image
      embed, no SVG/image link, no `[Open in Draw.io](...)` /
      `app.diagrams.net` link. The diagram stays coarse: entry → main
      phases → exits, plus the major external dependencies. No
      per-paragraph verb walks.
- [ ] `Section-by-section map` covers every section in execution order
      with discursive prose, not a bulleted list of names.
- [ ] `Release history` shows 3 to 5 recent entries verbatim and a single
      summarising paragraph for the older ones.
- [ ] `Cross-references` carry the typed taxonomy (callers, callees, JCL
      triggers, external dependencies) and the external-dependency table
      uses one of the canonical `Kind` values.
- [ ] `Dead / unreachable rollup` aggregates unreachable sections, orphan
      declarations AND unresolved dynamic targets — each in its own
      sub-section.
- [ ] `Divisions` embeds (in canonical order) the IDENTIFICATION,
      ENVIRONMENT, DATA and PROCEDURE division bodies. None is omitted;
      none is reordered.
- [ ] `Sections (inline, full content)` embeds every file under
      `sections/` in source-order; none omitted, none reordered.
- [ ] `Modernization artifacts (M1–M14)` renders one bullet per
      canonical M-step; missing artefacts are surfaced as `_not produced_`.
- [ ] `References` link to the cross-language pair (when applicable) and
      to the IT↔EN glossary; no link points to internal pipeline
      artefacts (`chunk-manifest.json`, `facts.json`, `docs/_shared/**`,
      `docs/_modernization/**`).
- [ ] No `[FILE:Lx-Ly]` inline tags survive anywhere in the document.
- [ ] No self-descriptive banner ("Self-contained document. Bundles…
      from facts.json…", "Omni-comprehensive…", "Mandatory section —
      never leave empty") is present in rendered prose — all authoring
      guidance lives in HTML comments only.
