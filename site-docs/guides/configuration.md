# Configure the pipeline

The configuration file is `config/pipeline.yaml`, validated by
`config/pipeline.schema.json`. The rename is not a compatibility alias: no copy
of the old configuration file is retained.

## Select generated deliverables

Both public runners (`scripts/run-pipeline.ps1` and `scripts/run-pipeline.sh`)
use the same contract:

```yaml
output:
  languages: [it]
  generate:
    docs: true
    functional_analysis: true
    requirements: true
    technical_analysis: true
```

The four `output.generate` values must be Booleans; each defaults to `true` when
omitted. Each key selects both the file and group versions of that deliverable.
When no explicit phase selector is supplied, the runner takes the union of these
enabled outputs and prerequisites:

| Key | Requested phases | Prerequisites added automatically |
|-----|------------------|-----------------------------------|
| `docs` | D/E/H/I | A/B/C |
| `requirements` | F/J | A/B/C/D/E/I |
| `functional_analysis` | G/K | A/B/C/D/E/F/I/J, including requirements and group context |
| `technical_analysis` | L/M | A/B/C/D/E/I only; neither requirements nor FA is needed |

Any enabled output also selects portal N. Overview diagrams H are selected only
when `docs: true`; section diagrams from D remain shared documentation prerequisites.
If all four keys are `false`, there is no work: no source discovery, authoring,
or portal build.

An explicitly supplied `-Phases`, `-From`, or `-To` bypasses YAML output selection.
`-Phases` takes precedence over range options. Explicit selections do not
automatically add prerequisites. Legacy `Run*` false values and `-Skip` are
applied last in all cases, and removed prerequisites are not repaired.

Disabled output types can still be generated as prerequisites of enabled types.
These switches do not delete existing outputs; a portal build may still display
documents from older runs. See [Run the pipeline](running.md) for explicit selections.

## Documentation output languages

Set the shared default in `config/pipeline.yaml`. The current setting is Italian only:

```yaml
output:
  languages: [it]
```

When no language is specified, the fallback is `[en]`. Both `scripts/run-pipeline.ps1` and
`scripts/run-pipeline.sh` apply this setting to section generation (D), file finalization
(E), requirements (F), functional analysis (G), technical analysis (L), and group
deliverables (I/J/K/M). Use `-Languages en,it` for a one-run override.

Precedence is **phase language option > `-Languages` > `output.languages` > `en`**.
`-SectionFinalizerLanguages` overrides both D and E; the other phase options are
`-RequirementsLanguages`, `-FunctionalAnalysisLanguages`, `-TechnicalAnalysisLanguages`,
and `-GroupLanguages`. Codes are lowercased and duplicates removed while preserving
requested order. No language is added: `output.languages: [it]` or `-Languages it`
generates Italian only; `it,en,it` becomes `it,en`. Invalid or empty lists fail before
phases start.

Writers follow exactly `bundle.languages` and `bundle.output_paths`. They must not
require or create unrequested English documentation, even as an intermediate.
Structural translation parity is checked only when multiple languages are requested.
Language-neutral diagrams remain shared under `docs/_shared/`. English template
headings do not select an English output; existing localization rules still apply.

Requested order also determines the source narrative: file requirements, functional
and technical analysis, and group deliverables stage their narrative inputs from
the first requested language (`bundle.languages[0]`). Section finalization instead
uses each output language's `toc[].summaries[lang]`; the legacy `summary_en` field
is empty when English is unrequested.

Standalone phase scripts use their own `-Languages` option (default `en`); YAML defaults
are resolved by the public pipeline runners. This is distinct from
`modernization.target_languages`, which selects Java/.NET targets.

After changing languages, rerun from D with the existing A-C artifacts to regenerate
bundles and documentation. Existing unselected language trees are not deleted.
The static portal currently supports `en` and `it` only; additional language codes can
be authored but are not published by the portal.

## Source discovery

Edit `config/pipeline.yaml` to define the source root and file selection.

```yaml
source_root: "./repos/enterprise"

include:
  - "Accounting"
  - "Payments"

exclude:
  - "**/archive/**"
  - "**/old/**"
```

Folder names and globs are relative to `source_root`. Folder entries are scanned recursively and
limited to supported COBOL, CL, JCL, copybook, and BMS extensions. With this configuration, the
execution of the selected deliverables is simply:

```powershell
pwsh -File scripts/run-pipeline.ps1
```

The Bash equivalent is `bash scripts/run-pipeline.sh`. When work is selected, the runner recursively discovers files
using `include` and `exclude`; no manifest or command-line glob is required. Explicit `-Files`,
`-Paths`, and `-Manifest` selectors are also filtered by these rules for files below
`source_root`.

`source_root` may point outside this repository. Use an absolute path for this case. In YAML, quote
Windows paths and prefer forward slashes so backslashes are not interpreted as escape sequences:

```yaml
source_root: "D:/Customers/Acme/legacy-sources"
```

For a one-off run against another complete tree, override only the root:

```powershell
pwsh -File scripts/run-pipeline.ps1 -SourceRoot 'D:\Customers\Acme\other-sources'
```

### Selector examples

Use `-Files` for a small explicit set:

```powershell
pwsh -File scripts/run-pipeline.ps1 `
  -From A -To C `
  -Files repos/enterprise/COBOL/PROG1.CBL,repos/enterprise/COBOL/PROG2.CBL `
  -SourceRoot repos/enterprise
```

Use `-Paths` to process a temporary list of folders below one common root. Directories are scanned
recursively, so extension globs are unnecessary:

```powershell
$paths = @(
  'D:\Customers\Acme\legacy-sources\Accounting'
  'D:\Customers\Acme\legacy-sources\Payments'
)
& scripts/run-pipeline.ps1 `
  -Paths $paths `
  -SourceRoot 'D:\Customers\Acme\legacy-sources'
```

The equivalent Bash invocation is:

```bash
source_root='/mnt/d/Customers/Acme/legacy-sources'
bash scripts/run-pipeline.sh \
  -Paths "$source_root/Accounting" "$source_root/Payments" \
  -SourceRoot "$source_root"
```

Use path syntax for the environment that launches the command. Native PowerShell uses paths such
as `D:\Customers\...`; WSL uses the mounted form `/mnt/d/Customers/...`.

### Source manifests

A manifest remains available when an exact, versioned inventory is required. JSON and CSV are
accepted and each row or object must contain `path`. Paths may be repository-relative or absolute.

```json
[
  { "path": "repos/enterprise/QCLSRC/ORDERJOB.CLLE" },
  { "path": "repos/enterprise/QCBLSRC/ORDERUPD.SQLCBLLE" },
  { "path": "repos/enterprise/QCPYSRC/ORDERREC.CPY" }
]
```

Equivalent CSV:

```csv
path
repos/enterprise/COBOL/PROG1.CBL
repos/enterprise/JCL/JOB1.JCL
```

Run either inventory with `-Manifest <file> -SourceRoot repos/enterprise`. Platform and encoding
rules continue to come from `config/pipeline.yaml` and automatic detection. The bundled IBM i
manifest also carries descriptive `sourceRoot` and `platform` properties so each entry is
self-contained for tools that consume those fields.

## Platform selection

Use automatic detection for conventional extensions and add per-glob overrides for ambiguous
`.CBL` or `.COB` members.

```yaml
platform: "auto"
platforms:
  "mainframe/**": "mainframe"
  "ibmi/**": "ibmi"
```

`.CBLLE`, `.SQLCBLLE`, `.CL`, `.CLP`, and `.CLLE` identify IBM i automatically.

## Encodings

Encoding rules are glob keyed. `auto` supports UTF-8, common EBCDIC input, and fallback decoding.

```yaml
encodings:
  "**/*.cbl": "auto"
  "legacy/**/*.cpy": "cp037"
```

## Copybook paths

```yaml
copybook_search_paths:
  - "COBOL/COPY"
  - "copybooks"
```

Paths are relative to `source_root`.

IBM i repositories commonly export copybooks from `QCPYSRC`, while mainframe repositories often
use `COBOL/COPY`:

```yaml
copybook_search_paths:
  - "COBOL/COPY"
  - "QCPYSRC"
  - "copybooks"
```

## Copilot model

```yaml
copilot:
  default_model: "claude-sonnet-4.5"
```

Model selection uses this order:

1. Explicit `-CopilotModel` on either public runner.
2. `copilot.default_model` in `config/pipeline.yaml`.
3. The selected agent's `model:` frontmatter.
4. Copilot automatic selection.

Use a **Copilot CLI model ID**, not an IDE display name, for the first two tiers.
`auto` explicitly selects automatic routing even if an agent requests a specific
model. To retain agent-specific selection instead, omit `default_model` (or the
whole `copilot` mapping). Empty strings, nulls, non-string values, and whitespace
in configured model IDs fail before phases start. Model availability and any
agent-level fallback warnings remain controlled by your installed CLI/account.

```powershell
pwsh -File scripts/run-pipeline.ps1 -CopilotModel claude-sonnet-4.5
pwsh -File scripts/run-pipeline.ps1 -CopilotModel auto -CopilotThrottle 32
```

The Bash runner accepts the same options. The default applies to every Copilot
dispatch stage D-M, including group and finalizer stages; it does not rewrite
agent definitions or change deterministic processing. Standalone dispatchers
also read the configured model default.

Model selection is included in PowerShell resume fingerprints/plans, so changing
it does not reuse authoring results cached under a different selection. Native
Bash records the selection in its plan and success journal; its dispatcher
currently reruns all selected bundles rather than skipping journal entries.
Do not pass a competing `--model` through `AdditionalCopilotArgs`; use the public
option or configuration instead. These controls select the top-level CLI call,
not independent IDE sessions or models explicitly selected by nested agents.

## Execution settings

```yaml
pipeline:
  copilot_parallelism: 16
```

Both public runners use **16 concurrent Copilot tasks per stage** by default, with a
supported range of **1-32**. Phases remain sequential across the selected source set,
so prerequisite and group fan-in boundaries are preserved. The limit is per runner;
starting multiple runners multiplies the possible concurrent calls.

Precedence is **explicit phase throttle > `-CopilotThrottle` >
`pipeline.copilot_parallelism` > 16**:

| Public runner option | Scope |
|----------------------|-------|
| `-CopilotThrottle` | All Copilot stages D-M |
| `-CopilotDocsThrottle` | Override section authoring D only |
| `-SectionFinalizerThrottle` | Override file documentation finalization E only |
| `-DiagramsThrottle` | Override overview diagrams H only |
| `-Throttle` | Independent deterministic batch concurrency |

For example, increase overall concurrency while keeping section authoring lower:

```powershell
pwsh -File scripts/run-pipeline.ps1 -CopilotThrottle 32 -CopilotDocsThrottle 8
```

The same options work with `bash scripts/run-pipeline.sh`. An explicit limit of 1 is
honored, including in phase D. Invalid limits fail before any phases start. YAML limits
must be integers, not strings or Booleans. Standalone phase and dispatcher scripts retain
their own defaults and options; they do not resolve this YAML key.

More workers can reduce elapsed time when enough independent work exists, but increase
memory consumption and concurrent API traffic. Reduce the limit if rate limits or memory
pressure occur; 32 is a supported ceiling, not a guaranteed speedup.

The declarative orchestrator settings `execution_mode` and `per_file_parallelism`, and
`max_parallel` in `config/pipeline-dag.yaml`, are **not consumed by the public runners**.
Changing them does not increase runner throughput.

## Groups

Declare business or runtime groups in `config/grouping.yaml`. Group phases I, J, K, and M are
workspace-scoped and become no-ops when no groups are declared.

```yaml
groups:
  - id: "daily-order-processing"
    description: "Daily order validation, update, and audit flow"
    members:
      - "COBOL/ORDR100.CBL"
      - "COBOL/ORDR200.CBL"
      - "JCL/ORDRJOB.JCL"
```

Member paths must use the same source identity convention as generated per-file artifacts. Keep
group IDs stable because they become output folder names and document identifiers.

## Validate configuration

Run the contract checks after editing source, DAG, grouping, or glossary configuration:

```console
python scripts/validation/check-dag-integrity.py
python scripts/validation/check-phase-order.py
python scripts/validation/check-pipeline-dag-paths.py
python scripts/validation/check-glossary-drift.py
```

Then run phases A-C against one representative source before scaling out.

## Profiles and glossary

- `config/templates/docs/requirements/` owns requirement profiles.
- `config/templates/docs/functional-analysis/` owns functional-analysis profiles.
- `config/templates/docs/technical-analysis/` owns technical-analysis profiles.
- `config/glossary.yaml` is the source of truth for shared terminology.

After glossary changes, run:

```console
python scripts/validation/sync-glossary.py
python scripts/validation/check-glossary-drift.py
```
