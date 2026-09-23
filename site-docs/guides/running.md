# Run the pipeline

## Simplest execution

Set `source_root`, `include`, `exclude`, and `output.generate` in
`config/pipeline.yaml`, then run:

=== "PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1
    ```

=== "Bash"

    ```bash
    bash scripts/run-pipeline.sh
    ```

This selects the configured deliverables and their prerequisites, then scans the
configured root recursively using the include/exclude globs. All four
`output.generate` values default to `true` when omitted. If all are `false`,
the run does no work, including no source discovery or portal build.

## Run against another source folder

For a temporary root override, one parameter is enough:

=== "PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -SourceRoot 'D:\Customers\Acme\legacy-sources'
    ```

=== "Bash / WSL"

    ```bash
    bash scripts/run-pipeline.sh \
      -SourceRoot '/mnt/d/Customers/Acme/legacy-sources'
    ```

The override still uses `include` and `exclude` from `config/pipeline.yaml`.

## Run selected folders

Pass directories directly to `-Paths`; every directory is scanned recursively:

```powershell
$sourceRoot = 'D:\Customers\Acme\legacy-sources'
$folders = @(
  "$sourceRoot\Accounting"
  "$sourceRoot\Payments"
)
& scripts/run-pipeline.ps1 -Paths $folders -SourceRoot $sourceRoot
```

Use `-Files` for explicit files and `-Manifest` for an exact JSON/CSV inventory.

## Select phases

| Option | Example | Behavior |
|--------|---------|----------|
| `-Phases` | `-Phases A,B,C` | Run an explicit set |
| `-From`, `-To` | `-From A -To C` | Run an inclusive range |
| `-Skip` | `-Skip I,J,K,M,N` | Remove phases from the selected set |

With no explicit phase selectors, both public runners use `output.generate`:
`docs` selects D/E/H/I plus A/B/C; `requirements` selects F/J plus A/B/C/D/E/I;
`functional_analysis` selects G/K plus A/B/C/D/E/F/I/J; `technical_analysis`
selects L/M plus A/B/C/D/E/I, without requirements or FA. Enabled outputs are
combined and add portal N. H is included only for `docs: true` in this mode.

An explicitly supplied `-Phases`, `-From`, or `-To` bypasses this YAML selection
and does not auto-add prerequisites. `-Phases` takes precedence over `-From` and
`-To`; the selected phases run in pipeline order. Legacy `Run*` false toggles and
`-Skip` are applied last, including with `-Phases`, and removed prerequisites
are not repaired. Supply missing prerequisites yourself or reuse existing artifacts.

Each YAML key selects both file and group outputs. Disabled types can still be
generated as prerequisites. Existing output is not deleted, so the portal may
show older documents. See [configuration](configuration.md#select-generated-deliverables)
for the complete contract, shared by PowerShell and Bash.

Common selections:

| Intent | Selection |
|--------|-----------|
| Deterministic validation | `-From A -To C` |
| Restage section authoring only | `-Phases D -CopilotDocsDryRun` |
| Per-file docs without groups or portals | `-Skip I,J,K,M,N` |
| Rebuild overview diagrams | `-Phases H -DiagramsForce` |
| Build only the generated portal | `-Phases N` |

## Deterministic extraction

=== "PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -From A -To C `
      -Paths 'repos/sample/COBOL/*.CBL' `
      -SourceRoot repos/sample `
      -Throttle 4 `
      -MaxPhaseRetries 3
    ```

=== "Bash"

    ```bash
    bash scripts/run-pipeline.sh \
      -From A -To C \
      -Paths 'repos/sample/COBOL/*.CBL' \
      -SourceRoot repos/sample \
      -Throttle 4 \
      -MaxPhaseRetries 3
    ```

## Full per-file documentation

After authenticating the Copilot CLI:

=== "PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -Files repos/sample/COBOL/ORDR100.CBL `
      -SourceRoot repos/sample `
      -Skip I,J,K,M,N `
      -SectionFinalizerLanguages en,it `
      -RequirementsLanguages en,it `
      -FunctionalAnalysisLanguages en,it `
      -TechnicalAnalysisLanguages en,it `
      -MaxPhaseRetries 3
    ```

=== "Bash"

    ```bash
    bash scripts/run-pipeline.sh \
      -Files repos/sample/COBOL/ORDR100.CBL \
      -SourceRoot repos/sample \
      -Skip I,J,K,M,N \
      -SectionFinalizerLanguages en,it \
      -RequirementsLanguages en,it \
      -FunctionalAnalysisLanguages en,it \
      -TechnicalAnalysisLanguages en,it \
      -MaxPhaseRetries 3
    ```

Use `-SkipDocx` when Pandoc output is not needed. Use phase-specific `DryRun` and `Force` switches
to inspect dispatches or regenerate stale content.

## Resume and retries

- `-MaxPhaseRetries 3` allows one initial attempt plus up to three retries after failures.
- `-MaxPhaseRetries 0` disables retries and is useful while diagnosing deterministic failures.
- Dispatchers persist plans, state, logs, and XML results under `temp/` and `logs/`.
- Re-running unchanged deterministic phases is safe.
- Force switches should be used only when an up-to-date check must be bypassed.

| Switch | Scope | Typical use |
|--------|-------|-------------|
| `-SectionFinalizerForce` | E | Rebuild `index.md` after changing the finalizer prompt |
| `-RequirementsForce` | F | Restage requirement bundles after profile changes |
| `-FunctionalAnalysisForce` | G | Restage functional-analysis bundles |
| `-DiagramsForce` | H | Re-author file-level Mermaid sources |
| `-TechnicalAnalysisForce` | L | Re-author per-file technical analysis |
| `-GroupForce` | I, J, K, M | Rebuild group-scoped deliverables |

Prefer a dry-run switch before force when one exists. A force switch can consume new model
requests even when current output is usable.

## Results, logs, and exit behavior

`-ResultsDir` isolates machine-readable XML from concurrent or comparative runs:

```powershell
pwsh -File scripts/run-pipeline.ps1 `
  -From A -To C `
  -Files repos/sample/COBOL/ORDR100.CBL `
  -SourceRoot repos/sample `
  -ResultsDir temp/run-2026-07-14
```

The orchestrator returns non-zero when a phase remains unsuccessful after its retry budget. A
phase missing required upstream artifacts fails fast with exit code 4 and lists each missing path.
Retain `temp/`, `logs/`, and Copilot OTEL files when investigating authored-phase failures.

## Build execution results

Phase N builds a portal for generated program documentation:

```console
python scripts/portal/build-portal-static.py --source-root repos/sample
```

This is distinct from the GitHub Pages user portal you are reading. Phase N writes
`docs/_portal/site`; GitHub Pages builds tracked guidance from `site-docs/`.
