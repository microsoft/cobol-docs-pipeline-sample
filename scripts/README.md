# Script organization

The pipeline uses **feature ownership**, with native Bash entry points beside PowerShell entry
points where both platforms are supported.

## Feature ownership

| Path | Responsibility |
|------|----------------|
| `scripts/run-pipeline.ps1`, `scripts/run-pipeline.sh` | Native public A–N orchestrators and phase retry policies |
| `scripts/phases/` | One executable phase entry point per runner phase |
| `scripts/lib/` | Shared orchestration, dispatch, grouping, result, and DOCX helpers |
| `scripts/dispatchers/` | Copilot batch dispatchers used by LLM-backed phases |
| `scripts/validation/` | DAG, phase-order, path, and glossary drift checks |
| `scripts/portal/` | Static and offline portal builders |
| `scripts/tools/` | Standalone Python compatibility and inspection tools |
| `.github/skills/<feature>/scripts/` | Feature-owned deterministic preparation, validation, and assembly |
| `scripts/schemas/` | JSON schemas used by deterministic phases |

PowerShell and Bash are independent implementations. Bash entry points invoke the Python phase
engines, GitHub Copilot CLI, and Pandoc directly through shared `native-*.sh` helpers. They do not
launch PowerShell or delegate to `.ps1` files.

## Concurrency

Public runners keep phases sequential and parallelize work within each stage.
`-CopilotThrottle` sets the shared LLM worker limit for D-M (1-32), overriding
`pipeline.copilot_parallelism` in `config/pipeline.yaml`; the fallback is 16.
Explicit `-CopilotDocsThrottle`, `-SectionFinalizerThrottle`, and `-DiagramsThrottle`
take precedence for D, E, and H respectively. `-Throttle` controls deterministic
batches independently. Standalone phase/dispatcher defaults are unchanged.

The shared resolver is [resolve-copilot-parallelism.py](tools/resolve-copilot-parallelism.py).
The public runners do not consume declarative `execution_mode`, `per_file_parallelism`,
or DAG `max_parallel`. See [configuration guidance](../site-docs/guides/configuration.md#execution-settings).

## Copilot model

Both public runners accept `-CopilotModel <model-id|auto>`. Selection precedence is
the explicit CLI option, `copilot.default_model` in
[pipeline.yaml](../config/pipeline.yaml), the agent's `model:` frontmatter, then
Copilot automatic selection. The checked-in default is `claude-sonnet-4.5`.
Omit the configuration key to preserve each agent's default. Blank or null values
are rejected; `auto` is an explicit override, not an absent value.

[resolve-copilot-model.py](tools/resolve-copilot-model.py) resolves selection for both
platforms. Runners transport the resolved override through the internal, phase-scoped
`COBOL_DOCS_COPILOT_MODEL` environment variable; it is not a public configuration tier.
PowerShell restores the previous value even on a phase failure. Standalone dispatchers
also read the YAML model default. No agent files are rewritten.

## Group prerequisites and retries

Phases J and K honor the upstream per-file `_req-bundles/_skipped.json` and
`_fa-bundles/_skipped.json` decisions, in addition to excluding PRC members.
Skipped members (for example, copybooks and BMS mapsets) are listed with their
reasons in the group bundle, but do not require a per-file narrative document.
The remaining members retain their manifest order. An explicit per-file profile
can enable generation again; its stager removes the corresponding skip marker.
A missing document without a skip marker is still an error, not an implicit skip.

Missing eligible member documents, or a staged group with no eligible inputs,
return prerequisite exit code **4**. Both runners stop immediately on this code
instead of retrying the same deterministic failure. Other nonzero exits retain
the configured retry policy. Existing PRC-only batch no-ops are unchanged.
PowerShell J/K summaries use the last updated step report from the current
attempt, rather than counting successes from an old finalizer report.

After repairing prerequisites, resume at the failed phase without `-Force` or
`-Restart`; existing dispatch resume checks remain in effect.

## DOCX diagnostics

The shared PowerShell [DOCX converter](lib/Convert-MdToDocx.ps1) captures Pandoc
stderr and uses its exit code to determine conversion success, including on
Windows PowerShell 5.1 with `ErrorActionPreference=Stop`. Diagnostics from a
successful conversion remain visible as warnings and in the result's `Stderr`.
Nonzero conversion results fail the DOCX-producing phases after their result
XML has been saved; they are not treated as successful exports.

## Portal languages

The [static builder](portal/build-portal-static.py) and
[offline builder](portal/build-portal-offline.py) use `output.languages` from
[pipeline.yaml](../config/pipeline.yaml). Only selected languages are published,
even when old Markdown editions remain on disk. English and Italian portal
controls are localized; source code, identifiers, and shared Markdown content
are preserved unchanged.

In Italian pages, recognized standard template headings (for example `Summary`,
`Purpose`, and `Entry contract`) are translated when rendering HTML, including
numbered headings and matching table-of-contents links. Existing heading anchors
are retained so bookmarks still work. Inline code in recognized headings (such
as `EXEC SQL`) retains its identifiers and markup. Original Markdown files,
prose, code blocks, custom headings, and other inline markup are not rewritten.
Authoring self-check and author/redaction verification sections are omitted from
published web and offline pages without modifying their source Markdown.
The offline source viewer embeds these same localized pages and translates its
chunk-type labels without changing source identifiers.

Standalone builders accept `--languages it` (PowerShell wrappers:
`-Languages it`). The public runners forward the ordered union of their resolved
document-language selections to phase N. A source-viewer link from a document
selects that document's language; saved browser preferences cannot select an
excluded language. Missing chunk documentation is reported rather than silently
replaced with another language.

After changing languages, rebuild the portal without `--skip-build`/`-SkipBuild`.
Skip-build verifies the existing static manifest and refuses a different language
selection. Building phase N only renders existing documentation and packages
offline resources; it does not rerun chunk authoring or invoke Copilot.

Footnote cleanup is a best-effort text scan, not a Markdown parser. For example,
`` `[^key]` `` is literal code, not a footnote reference, so Pandoc can still
report the definition as unused. Use `[^key]` outside backticks for a real
citation. Such warnings do not require regenerating chunks.

To retry only a Word export without invoking Copilot or modifying the Markdown:

```powershell
. .\scripts\lib\Convert-MdToDocx.ps1
$result = Convert-MdToDocx -MarkdownPath '.\docs\it\ATVERS01.CBL\complete.md' -Force
if ($result.Exit -ne 0) { throw $result.Stderr }
```

## Platform launchers

| Path | Responsibility |
|------|----------------|
| `scripts/run-pipeline.cmd` | Windows `cmd.exe` launcher |
| `scripts/run-pipeline.sh` | Linux/macOS Bash launcher |
| `scripts/phases/*.sh` | Bash launchers beside A–N phase entry points |
| `scripts/dispatchers/*.sh` | Bash launchers beside Copilot batch dispatchers |
| `.github/skills/*/scripts/*.sh` | Bash launchers beside skill-owned batch scripts |
| `scripts/lib/native-common.sh` | Shared input, path, batch, and XML result helpers |
| `scripts/lib/native-skill-batch.sh` | Native deterministic skill batch implementation |
| `scripts/lib/native-copilot-dispatch.sh` | Native Copilot planning, dispatch, retry, and state handling |
| `scripts/lib/native-phase.sh` | Shared native implementation for phases D–N |
| `scripts/lib/native-docx.sh` | Native Pandoc conversion helper |

Regenerate or validate generated native entry points after adding or renaming a supported
PowerShell entry point:

```bash
python3 scripts/tools/generate-bash-launchers.py
python3 scripts/tools/generate-bash-launchers.py --check
```

Do not edit generated entry points directly. Update `generate-bash-launchers.py` or the owning
native shared engine instead. The eight maintained Bash files, including `run-pipeline.sh` and
the `native-*.sh` helpers, are edited directly.