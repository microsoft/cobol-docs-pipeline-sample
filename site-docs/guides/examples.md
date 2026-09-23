# End-to-end examples

These recipes start with deterministic extraction and progress to Copilot-authored deliverables.
Run commands from the repository root. Replace sample paths only after the bundled examples pass.

## Choose a workflow

| Goal | Phases | Model calls | Start with |
|------|--------|-------------|------------|
| Verify installation | A-C | No | One bundled COBOL program |
| Verify IBM i support | A-C | No | The five-member IBM i manifest |
| Inspect authoring work | D dry run | No | Existing A-C artifacts |
| Document one program | A-H, L | Yes | Skip group and portal phases |
| Document a workspace | A-N | Yes | Globs or a source manifest |

## Example 1: extract one mainframe program

This is the fastest meaningful pipeline run. It parses `ORDR100.CBL`, extracts facts, performs
workspace cross-reference resolution, and writes one raw text file per chunk.

=== "Windows PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -From A -To C `
      -Files repos/sample/COBOL/ORDR100.CBL `
      -SourceRoot repos/sample `
      -ResultsDir temp/example-mainframe
    ```

=== "Linux or macOS"

    ```bash
    bash scripts/run-pipeline.sh \
      -From A -To C \
      -Files repos/sample/COBOL/ORDR100.CBL \
      -SourceRoot repos/sample \
      -ResultsDir temp/example-mainframe
    ```

A successful run reports one successful source in each phase:

```text
PHASE-DONE phase=A ok=1 failed=0 ... state=success
PHASE-DONE phase=B ok=1 failed=0 ... state=success
PHASE-DONE phase=C ok=1 failed=0 ... state=success
```

Inspect these checkpoints before using an LLM phase:

| Checkpoint | What to verify |
|------------|----------------|
| `docs/_shared/ORDR100.CBL/chunk-manifest.json` | Platform, source kind, encoding, and chunk boundaries |
| `docs/_shared/ORDR100.CBL/facts.json` | Program ID, paragraphs, calls, copybooks, SQL, CICS, and data records |
| `docs/_shared/ORDR100.CBL/chunks/index.json` | One raw source slice for every documented chunk |
| `temp/example-mainframe/*.xml` | Per-file status and failure details for automation |

## Example 2: extract the IBM i workspace

The manifest selects a CLLE controller, three ILE COBOL programs, and one copybook. Processing the
members together allows phase B to resolve library-qualified calls into incoming references.

=== "Windows PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -From A -To C `
      -Manifest repos/sample-as400/sources.json `
      -SourceRoot repos/sample-as400 `
      -ResultsDir temp/example-ibmi
    ```

=== "Linux or macOS"

    ```bash
    bash scripts/run-pipeline.sh \
      -From A -To C \
      -Manifest repos/sample-as400/sources.json \
      -SourceRoot repos/sample-as400 \
      -ResultsDir temp/example-ibmi
    ```

Expected result: phases A-C each report `ok=5 failed=0`. In the generated facts, confirm these
relationships:

```text
ORDRJOB --CL CALL/SBMJOB--> ORDRINQ and ORDRUPD
ORDRUPD --COBOL CALL------> ORDRAUD
ORDRAUD --COPY------------> ORDAUDR
```

See [IBM i sample repository](as400-sample.md) for the source layout and DB2 for i behavior.

## Example 3: stage section authoring without model calls

Run A-C first, then use the phase-D dry-run switch. This creates prepared bundles and a dispatch
plan without submitting prompts to Copilot.

=== "Windows PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -Phases D `
      -Files repos/sample/COBOL/ORDR100.CBL `
      -SourceRoot repos/sample `
      -CopilotDocsDryRun
    ```

=== "Linux or macOS"

    ```bash
    bash scripts/run-pipeline.sh \
      -Phases D \
      -Files repos/sample/COBOL/ORDR100.CBL \
      -SourceRoot repos/sample \
      -CopilotDocsDryRun
    ```

Review `docs/_shared/ORDR100.CBL/_bundles/` and the dispatch plan under `temp/`. A bundle should
contain one chunk's source text, its fact slice, the selected profile, and authoritative output
paths. Fix configuration or stale deterministic artifacts before enabling model calls.

## Example 4: document one program

After authenticating the GitHub Copilot CLI, run the per-file phases and omit workspace group
phases. `-SkipDocx` avoids a Pandoc dependency during the first authored run.

=== "Windows PowerShell"

    ```powershell
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -Files repos/sample/COBOL/ORDR100.CBL `
      -SourceRoot repos/sample `
      -Skip I,J,K,M,N `
      -SectionFinalizerLanguages en,it `
      -RequirementsLanguages en,it `
      -FunctionalAnalysisLanguages en,it `
      -TechnicalAnalysisLanguages en,it `
      -SkipDocx `
      -TechnicalAnalysisSkipDocx `
      -MaxPhaseRetries 3
    ```

=== "Linux or macOS"

    ```bash
    bash scripts/run-pipeline.sh \
      -Files repos/sample/COBOL/ORDR100.CBL \
      -SourceRoot repos/sample \
      -Skip I,J,K,M,N \
      -SectionFinalizerLanguages en,it \
      -RequirementsLanguages en,it \
      -FunctionalAnalysisLanguages en,it \
      -TechnicalAnalysisLanguages en,it \
      -SkipDocx \
      -TechnicalAnalysisSkipDocx \
      -MaxPhaseRetries 3
    ```

The principal English outputs are:

```text
docs/en/ORDR100.CBL/index.md
docs/en/ORDR100.CBL/complete.md
docs/en/ORDR100.CBL/requirements.md
docs/en/ORDR100.CBL/functional-analysis.md
docs/en/ORDR100.CBL/technical-analysis.md
```

The same paths are produced under `docs/it/`. Reviews and language-neutral diagrams remain under
`docs/_reviews/` and `docs/_shared/ORDR100.CBL/`.

Both editions are generated because this example explicitly requests `en,it`.
To generate Italian only, replace every language option above with `it`, or omit
those phase options and set `output.languages: [it]` in `config/pipeline.yaml`
(alternatively pass `-Languages it`). No English intermediate is required or generated.

## Example 5: process a mainframe workspace

Use globs when the source tree follows predictable folders. In PowerShell, invoke the script in
the current process when passing an array; `pwsh -File` does not preserve an array argument.

=== "Windows PowerShell"

    ```powershell
    $samplePaths = @(
      'repos/sample/COBOL/*.CBL'
      'repos/sample/JCL/*.JCL'
      'repos/sample/JCL/*.PRC'
    )

    & scripts/run-pipeline.ps1 `
      -Paths $samplePaths `
      -SourceRoot repos/sample `
      -Throttle 4 `
      -GroupLanguages en,it `
      -MaxPhaseRetries 3
    ```

=== "Linux or macOS"

    ```bash
    bash scripts/run-pipeline.sh \
      -Paths 'repos/sample/COBOL/*.CBL' 'repos/sample/JCL/*.JCL' 'repos/sample/JCL/*.PRC' \
      -SourceRoot repos/sample \
      -Throttle 4 \
      -GroupLanguages en,it \
      -MaxPhaseRetries 3
    ```

Group phases are no-ops until `config/grouping.yaml` declares at least one group. Phase N builds
the generated-documentation portal under `docs/_portal/`; it is separate from this GitHub Pages
site.

## Example 6: rerun a failed slice

Start with retries disabled while diagnosing a repeatable failure:

```powershell
pwsh -NoProfile -File scripts/run-pipeline.ps1 `
  -Phases D `
  -Files repos/sample/COBOL/ORDR100.CBL `
  -SourceRoot repos/sample `
  -CopilotDocsDryRun `
  -MaxPhaseRetries 0
```

After correcting the cause, rerun the same selection. Dispatch state allows completed work to be
resumed; use a phase-specific force switch only when an otherwise current output must be rebuilt.
See [Run the pipeline](running.md#resume-and-retries) for retry and force guidance.

## Next steps

1. [Configure sources](configuration.md) for your repository and encoding rules.
2. [Inspect generated artifacts](artifacts.md) before authoring documentation.
3. [Run the pipeline](running.md) with deliberate phase, retry, and language choices.