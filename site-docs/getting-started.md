# Getting started

## Prerequisites

| Capability | Requirement |
|------------|-------------|
| Deterministic phases | Python 3.8+, `pyyaml`, `jsonschema` |
| Windows runner | PowerShell 5.1+ or PowerShell 7 |
| Linux/macOS runner | Bash 4.3+ and standard POSIX utilities |
| LLM-backed phases | Authenticated GitHub Copilot CLI |
| Word output | Pandoc, optional |
| Phase-N execution portal | `markdown`, `pymdown-extensions` |

Install the common Python dependencies:

```console
python -m pip install --upgrade pip
python -m pip install pyyaml jsonschema markdown pymdown-extensions
```

## Validate the repository

```console
python scripts/validation/check-dag-integrity.py
python scripts/validation/check-phase-order.py
python scripts/validation/check-pipeline-dag-paths.py
python scripts/validation/check-glossary-drift.py
python -m pytest -q
```

## Run phases A-C

Phases A-C are the cheapest end-to-end check because they make no LLM calls.

After setting `source_root`, `include`, and `exclude` in `config/pipeline.yaml`, run the configured
source tree without repeating paths on the command line:

```powershell
pwsh -NoProfile -File scripts/run-pipeline.ps1 -From A -To C
```

The examples below select one sample file explicitly for a smaller smoke test.

=== "Windows PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -From A -To C `
      -Files repos/sample/COBOL/ORDR100.CBL `
      -SourceRoot repos/sample `
      -ResultsDir temp/smoke
    ```

=== "Linux or macOS"

    ```bash
    bash scripts/run-pipeline.sh \
      -From A -To C \
      -Files repos/sample/COBOL/ORDR100.CBL \
      -SourceRoot repos/sample \
      -ResultsDir temp/smoke
    ```

Confirm these files exist:

```text
docs/_shared/ORDR100.CBL/chunk-manifest.json
docs/_shared/ORDR100.CBL/facts.json
docs/_shared/ORDR100.CBL/chunks/index.json
```

Then use [Inspect generated artifacts](guides/artifacts.md) to verify platform classification,
chunk boundaries, facts, and hashes rather than checking file presence alone.

## Run the IBM i sample

The bundled [AS400 sample](guides/as400-sample.md) contains a CLLE controller, two
SQLCBLLE programs, one CBLLE audit program, and a shared copybook. Its manifest selects only the
five source members:

=== "Windows PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -From A -To C `
      -Manifest repos/sample-as400/sources.json `
      -SourceRoot repos/sample-as400
    ```

=== "Linux or macOS"

    ```bash
    bash scripts/run-pipeline.sh \
      -From A -To C \
      -Manifest repos/sample-as400/sources.json \
      -SourceRoot repos/sample-as400
    ```

## Preview an LLM phase safely

Use a dry run to stage bundles and inspect dispatch commands without consuming model requests:

```powershell
pwsh -NoProfile -File scripts/run-pipeline.ps1 `
  -Phases D `
  -Files repos/sample/COBOL/ORDR100.CBL `
  -SourceRoot repos/sample `
  -CopilotDocsDryRun
```

The equivalent Bash command uses `scripts/run-pipeline.sh` and the same parameter names.

Continue with [End-to-end examples](guides/examples.md) for bilingual output, workspace globs,
retry diagnosis, and full per-file documentation.

!!! note
    `docs/`, `temp/`, and `logs/` are execution outputs and are ignored by Git. This user
    portal is sourced from the tracked `site-docs/` directory.
