---
source_file: "{{SOURCE_FILE}}"
source_path: "{{SOURCE_PATH}}"
source_type: "{{SOURCE_TYPE}}"
sha256: "{{SHA256}}"
total_lines: {{TOTAL_LINES}}
source_last_modified: "{{SOURCE_LAST_MODIFIED}}"
source_commit_sha: "{{SOURCE_COMMIT_SHA}}"
generated_at: "{{GENERATED_AT}}"
profile_fa: "{{PROFILE_FA}}"
profile_req: "{{PROFILE_REQ}}"
language: "{{LANG}}"
---

# Index — `{{SOURCE_FILE}}`

<!-- Lightweight landing page / table of contents for ONE source file.
     This document is NOT a replacement for `complete.md` — it never
     re-renders content that lives in another document; it only links.
     Long-form narrative belongs to `complete.md`; per-division detail
     belongs to the division docs; per-section detail belongs to the
     section docs.

     FORBIDDEN per .github/instructions/no-generator-boilerplate.instructions.md:
       * self-descriptive banners
       * `[FILE:Lx-Ly]` inline tags
       * links to internal pipeline artefacts (`chunk-manifest.json`,
         `facts.json`, `docs/_shared/**`, `docs/_modernization/**`)
       * `[Open in Draw.io](app.diagrams.net/...)` links. -->

> **{{HEADLINE}}**
>
> **Source:** `{{SOURCE_PATH}}` · **Type:** {{SOURCE_TYPE}}
> **SHA-256:** `{{SHA256}}` · **Lines:** {{TOTAL_LINES}}
> **Source last modified:** {{SOURCE_LAST_MODIFIED}}{{#SOURCE_COMMIT_SHA}} · **Commit:** `{{SOURCE_COMMIT_SHA}}`{{/SOURCE_COMMIT_SHA}}
> **Generated:** {{GENERATED_AT}} · **Language:** {{LANG}}
> **Profiles:** FA = {{PROFILE_FA_LABEL}} · Req = {{PROFILE_REQ_LABEL}}

## 1. Read first
- **[Complete document](./complete.md)** — {{COMPLETE_PITCH}}

## 2. Quick facts

<!-- One-glance dashboard. Numbers ONLY, pulled mechanically from
     facts.json. No prose. Render `0` explicitly when a counter is
     zero — never omit a row. -->

| Metric | Value |
|--------|-------|
| Sections | {{COUNT_SECTIONS}} |
| Paragraphs | {{COUNT_PARAGRAPHS}} |
| FDs / SELECTs | {{COUNT_FDS}} / {{COUNT_SELECTS}} |
| Working-Storage 01-levels | {{COUNT_WS_01}} |
| Linkage 01-levels | {{COUNT_LINKAGE_01}} |
| Copybooks included | {{COUNT_COPYBOOKS}} |
| DCLGENs included | {{COUNT_DCLGENS}} |
| EXEC SQL statements | {{COUNT_EXEC_SQL}} |
| EXEC CICS statements | {{COUNT_EXEC_CICS}} |
| Static CALLs out | {{COUNT_CALLS_STATIC}} |
| Dynamic CALLs out | {{COUNT_CALLS_DYNAMIC}} |
| Programs / JCL calling in | {{COUNT_CALLERS}} |
| Warnings | {{COUNT_WARNINGS}} |
| Dead / unreachable items | {{COUNT_DEAD}} |

## 3. Documents

### 3.1 Per-source deliverables
- [Complete document](./complete.md)
- [Functional analysis](./functional-analysis.md)
- [Requirements](./requirements.md)

### 3.2 Divisions
{{#DIVISION_DOCS}}
- [{{DIV_LABEL}}]({{DIV_FILE}}){{#DIV_NOTES}} — {{DIV_NOTES}}{{/DIV_NOTES}}
{{/DIVISION_DOCS}}
{{^DIVISION_DOCS}}
- _No division documents produced for this source type._
{{/DIVISION_DOCS}}

### 3.3 Modernization artefacts (M1–M14)
{{#MOD_ARTIFACTS_CANONICAL}}
- **{{MOD_LABEL}}** — {{#MOD_FILE}}[{{MOD_TITLE}}]({{MOD_ROOT}}/{{SOURCE_FILE}}/{{MOD_FILE}}){{/MOD_FILE}}{{^MOD_FILE}}_not produced_{{/MOD_FILE}}
{{/MOD_ARTIFACTS_CANONICAL}}

### 3.4 Quality artefacts
- [Paragraph coverage](./_coverage.md)
- [Sensitive data (PII)](./_sensitive-data.md)

## 4. Sections

| # | Section | Kind | Line range | Reachability | ⚠️ | Doc |
|---|---------|------|------------|--------------|----|-----|
{{#SECTIONS}}
| {{SECTION_NUMBER}} | `{{SECTION_NAME}}` | {{SECTION_KIND}} | L{{START_LINE}}–L{{END_LINE}} | {{REACHABILITY}} | {{WARNING_FLAG}} | [open](./sections/{{SECTION_SLUG}}.md) |
{{/SECTIONS}}

> `Kind` ∈ `NORMAL`, `CICS-ENTRY`, `DECLARATIVES`, `COPY-EXPANSION`.
> `Reachability` ∈ `REACHABLE`, `UNREACHABLE`, `ENTRY`. `⚠️` is set
> when the section carries at least one warning — open the section
> doc for details.

## 5. Last release

<!-- Single line. The full history (recent entries + summary paragraph)
     lives in `complete.md` chapter 3. Do NOT re-render the history
     here. -->

{{#LAST_RELEASE}}
- **{{LAST_REL_DATE}}** · {{LAST_REL_AUTHOR}}{{#LAST_REL_TAG}} _(tag: {{LAST_REL_TAG}})_{{/LAST_REL_TAG}} — {{LAST_REL_DESCRIPTION}}
{{/LAST_RELEASE}}
{{^LAST_RELEASE}}
- _No release banner detected in the source._
{{/LAST_RELEASE}}

→ Full release history: [complete.md §3](./complete.md#3-release-history)

## 6. Warnings beacon

<!-- Counts and jump links only — the actual warning text lives in the
     chapters this beacon points to. -->

| Where | Count | Jump |
|-------|-------|------|
| File-level warnings | {{COUNT_WARNINGS_FILE}} | [complete.md §18 / §15](./complete.md) |
| Dead / unreachable sections | {{COUNT_DEAD_SECTIONS}} | [complete.md §5.1](./complete.md#5-dead--unreachable-rollup) |
| Orphan declarations (FDs, SELECTs, copybooks, fields) | {{COUNT_DEAD_DECLS}} | [complete.md §5.2](./complete.md#5-dead--unreachable-rollup) |
| Unresolved dynamic CALL / CICS targets | {{COUNT_UNRESOLVED}} | [complete.md §5.3](./complete.md#5-dead--unreachable-rollup) |

## 7. References
- IT↔EN glossary: [{{GLOSSARY_PATH}}]({{GLOSSARY_PATH}})
{{#ALT_LANG_LINK}}
- {{ALT_LANG_LABEL}}: [{{ALT_LANG_PATH}}]({{ALT_LANG_PATH}})
{{/ALT_LANG_LINK}}

## Citations
{{#CITATIONS}}
[^src-{{CITATION_ID}}]: `{{CITATION_FILE}}` L{{CITATION_START}}–L{{CITATION_END}} — confidence: **{{CITATION_CONFIDENCE}}**, evidence: {{CITATION_EVIDENCE_KIND}}.{{#CITATION_NOTE}} {{CITATION_NOTE}}{{/CITATION_NOTE}}
{{/CITATIONS}}
{{^CITATIONS}}
_No citations recorded at the index level. The index is a navigation
artefact; substantive `[^src-N]` markers live in the documents it links
to (`complete.md`, division docs, section docs)._
{{/CITATIONS}}

---

### Authoring self-check
- [ ] YAML front-matter populated (source path, SHA-256, line count,
      source last-modified timestamp, source commit SHA, generation
      timestamp, profiles, language).
- [ ] `HEADLINE` is ONE sentence in business vocabulary — no COBOL /
      JCL jargon, no section names.
- [ ] Profile identifiers in the blockquote are rendered with
      human-readable labels (`PROFILE_FA_LABEL` / `PROFILE_REQ_LABEL`),
      not raw directory names.
- [ ] `Quick facts` table renders every row, with `0` for empty
      counters — no row is omitted.
- [ ] `Documents` chapter does NOT re-render content from the linked
      documents (no embedded release history, no embedded
      cross-references, no embedded diagrams). It links only.
- [ ] `Divisions` lists the division docs that actually exist for this
      source type (a JCL job will list none, a COBOL program will list
      four).
- [ ] `Modernization artefacts (M1–M14)` renders one bullet per
      canonical M-step; missing artefacts are surfaced as `_not
      produced_`.
- [ ] `Sections` table uses the canonical `Kind` and `Reachability`
      taxonomies and sets the `⚠️` column when the section has at
      least one warning.
- [ ] `Last release` renders ONE line and points to `complete.md §3`
      for the full history — the history is NOT duplicated here.
- [ ] `Warnings beacon` shows counts and jump links; the warning
      text itself is NOT duplicated here.
- [ ] `References` link to the IT↔EN glossary and (when applicable)
      the cross-language version. Internal pipeline artefacts
      (`chunk-manifest.json`, `facts.json`, `docs/_shared/**`,
      `docs/_modernization/**`) are NOT linked.
- [ ] No `[FILE:Lx-Ly]` inline tags survive anywhere.
- [ ] No self-descriptive banner ("Self-contained document. Bundles…
      from facts.json…", "Mandatory section — never leave empty") is
      present in rendered prose — all authoring guidance lives in HTML
      comments only.
