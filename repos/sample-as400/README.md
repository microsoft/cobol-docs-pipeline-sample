# IBM i order processing sample

## Description

This original, vendor-neutral sample repository models a small IBM i (AS400) order workflow. It
exists to exercise the documentation pipeline with first-class ILE COBOL, embedded SQL, Control
Language, library-qualified calls, database file overrides, submitted jobs, copybooks, and DB2 for
i objects.

The flow is intentionally compact:

1. `ORDRJOB.CLLE` overrides `ORDERS` to `DEMODATA/ORDERS` and selects query, update, or batch mode.
2. `ORDRINQ.SQLCBLLE` reads an order from DB2 for i.
3. `ORDRUPD.SQLCBLLE` updates the order, commits or rolls back, and calls `ORDRAUD`.
4. `ORDRAUD.CBLLE` writes an audit row using the `ORDAUDR` copybook.

This is a proof-of-concept sample, not production IBM i application code.

## Repository layout

```text
sample-as400/
|-- QCLSRC/
|   `-- ORDRJOB.CLLE
|-- QCBLSRC/
|   |-- ORDRAUD.CBLLE
|   |-- ORDRINQ.SQLCBLLE
|   `-- ORDRUPD.SQLCBLLE
|-- QCPYSRC/
|   `-- ORDAUDR.CPY
|-- DATA/
|   |-- schema.sql
|   `-- orders.csv
|-- sources.json
|-- LICENSE
`-- README.md
```

The `QCLSRC`, `QCBLSRC`, and `QCPYSRC` directories represent source physical files exported from
IBM i into stream files. Their member extensions preserve the source type used during export.

## Installation

For documentation generation, install the pipeline dependencies from the repository root:

```console
python -m pip install pyyaml jsonschema markdown pymdown-extensions
```

To compile on IBM i, create `DEMOLIB` and `DEMODATA`, run `DATA/schema.sql`, and place source
members in source physical files with matching names and types. Example IBM i commands:

```text
CRTSQLCBLI OBJ(DEMOLIB/ORDRINQ) SRCFILE(DEMOLIB/QCBLSRC) SRCMBR(ORDRINQ)
CRTSQLCBLI OBJ(DEMOLIB/ORDRUPD) SRCFILE(DEMOLIB/QCBLSRC) SRCMBR(ORDRUPD)
CRTBNDCBL  PGM(DEMOLIB/ORDRAUD) SRCFILE(DEMOLIB/QCBLSRC) SRCMBR(ORDRAUD)
CRTCLPGM   PGM(DEMOLIB/ORDRJOB) SRCFILE(DEMOLIB/QCLSRC) SRCMBR(ORDRJOB)
```

Ensure `QCPYSRC` is present in the compile-time copybook search path for `ORDRAUD`.

## Usage

Run deterministic phases A-C against the complete sample.

### Windows PowerShell

```powershell
pwsh -NoProfile -File scripts/run-pipeline.ps1 `
  -From A -To C `
  -Manifest repos/sample-as400/sources.json `
  -SourceRoot repos/sample-as400 `
  -ResultsDir temp/as400-sample
```

### Linux or macOS

```bash
bash scripts/run-pipeline.sh \
  -From A -To C \
  -Manifest repos/sample-as400/sources.json \
  -SourceRoot repos/sample-as400 \
  -ResultsDir temp/as400-sample
```

The manifest intentionally lists only source members. It prevents README, license, SQL setup, and
CSV seed data from being interpreted as source when explicit path selection is used.

Run one source when diagnosing a specific contract:

```console
python scripts/tools/chunk.py --source repos/sample-as400/QCLSRC/ORDRJOB.CLLE
```

Expected platform contracts:

| Extension | `source_platform` | `source_kind` |
|-----------|-------------------|---------------|
| `.CLLE` | `ibmi` | `cl` |
| `.CBLLE` | `ibmi` | `cobol` |
| `.SQLCBLLE` | `ibmi` | `cobol` |
| `.CPY` | inherited or configured | `copybook` |

## License

This sample is available under the [MIT License](LICENSE).
