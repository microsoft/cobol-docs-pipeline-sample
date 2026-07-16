# Configure sources

## Source discovery

Edit `config/sources.yaml` to define the source root and file selection.

```yaml
source_root: "./repos/enterprise"

include:
  - "mainframe/**/*.cbl"
  - "mainframe/**/*.jcl"
  - "ibmi/**/*.sqlcblle"
  - "ibmi/**/*.clle"

exclude:
  - "**/archive/**"
  - "**/old/**"
```

Globs are relative to `source_root`. Command-line `-Files`, `-Paths`, or `-Manifest` selectors can
override discovery for a run.

### Selector examples

Use `-Files` for a small explicit set:

```powershell
pwsh -File scripts/run-pipeline.ps1 `
  -From A -To C `
  -Files repos/enterprise/COBOL/PROG1.CBL,repos/enterprise/COBOL/PROG2.CBL `
  -SourceRoot repos/enterprise
```

Use `-Paths` for concrete folders or globs. Expansion is non-recursive, so provide one glob for
each source directory instead of expecting `repos/enterprise/*.*` to descend into subfolders.

```powershell
$paths = @(
  'repos/enterprise/COBOL/*.CBL'
  'repos/enterprise/JCL/*.JCL'
  'repos/enterprise/JCL/*.PRC'
)
& scripts/run-pipeline.ps1 -From A -To C -Paths $paths -SourceRoot repos/enterprise
```

### Source manifests

A manifest is the most reproducible selector for mixed folders. JSON and CSV are accepted and
each row or object must contain `path`. Paths should be repository-relative or absolute.

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
rules continue to come from `config/sources.yaml` and automatic detection. The bundled IBM i
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

## Execution settings

```yaml
pipeline:
  execution_mode: "per-file-loop"
  per_file_parallelism: 2
```

Keep file parallelism conservative for LLM-backed runs. Per-phase fan-out is separately bounded by
`max_parallel` in `config/pipeline-dag.yaml` and command-line throttle options.

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
