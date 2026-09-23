# Troubleshooting

## A source is not discovered

Without explicit phase selectors, all four `output.generate` keys set to `false`
intentionally skip discovery and all other work. Enable a deliverable in
`config/pipeline.yaml` or supply an explicit phase selection before investigating
source filters.

1. Confirm `source_root` in `config/pipeline.yaml`.
2. Check include and exclude ordering.
3. Use a repo-relative path with `-Files` to isolate discovery from glob behavior.
4. Confirm the extension is supported and its case is handled by the active platform.

`-Paths` does not recurse into child directories. This selects only files directly matched by the
glob:

```powershell
-Paths 'repos/enterprise/COBOL/*.CBL'
```

For nested layouts, provide one concrete glob per folder or use a JSON/CSV manifest.

## The manifest or facts file is stale

Source hashes connect phases A-C. Re-run from phase A after source changes:

```console
pwsh -File scripts/run-pipeline.ps1 -From A -To C -Files <source> -SourceRoot <root>
```

Do not edit manifests, facts, chunks, or slices by hand.

If phase D reports a hash mismatch, rerunning phase D alone is insufficient. Regenerate A-C so
the manifest, facts graph, raw text, and slices agree on the source hash.

## A Copilot phase fails

- Confirm the Copilot CLI is installed and authenticated in the active shell.
- Run the phase's dry-run option to inspect bundles and dispatch commands.
- Review state and task logs under `temp/` and `logs/`.
- Lower the relevant throttle when rate limits or resource pressure are involved.
- Set `-MaxPhaseRetries 0` while debugging to avoid repeated model requests.

Use the narrowest dry run that reproduces the issue. For phase D:

```powershell
pwsh -File scripts/run-pipeline.ps1 `
	-Phases D `
	-Files <source> `
	-SourceRoot <root> `
	-CopilotDocsDryRun `
	-MaxPhaseRetries 0
```

If dry run succeeds but live dispatch fails, inspect authentication, model availability, rate
limits, and the task-specific Copilot log. If dry run fails, inspect bundle prerequisites and
configuration before retrying model calls.

## DOCX files are missing

Markdown generation does not require Pandoc. Install Pandoc and rerun the owning finalizer, or use
the documented skip switches when Word output is intentionally disabled.

## CL is shown as JCL

Verify phase-A facts report `source_platform: ibmi` and `source_kind: cl`. Use `.CL`, `.CLP`, or
`.CLLE`, or supply an IBM i platform override for ambiguous source members. Regenerate stale
bundles after correcting the source contract.

## An expected incoming call is missing

Incoming references are computed at workspace scope during phase B. Confirm caller and target were
both selected in the same run, then inspect the caller's outbound facts and the target program ID.
Rerun phase B over the complete workspace; processing only the target cannot discover callers that
are absent from the selected source set.

## A downstream phase exits with code 4

Exit code 4 means required upstream artifacts are absent. Read the emitted path list, then run the
owning earlier phase instead of forcing the downstream phase. Common dependencies are:

| Failing phase | Usually missing |
|---------------|-----------------|
| B | `chunk-manifest.json` from A |
| C | manifest or `facts.json` from A-B |
| D | raw chunks or fact slices from A-C |
| E | section Markdown from D |
| L | per-file `complete.md` from E |

## Generated portal pages are empty or incomplete

Phase N can only publish deliverables that exist under `docs/<lang>/`. Verify the expected
per-file or group Markdown before rebuilding the portal. The GitHub Pages site is unrelated and
cannot be used to diagnose missing phase-N program documentation.

## DAG validation fails

Run each validator separately to identify the contract that drifted:

```console
python scripts/validation/check-dag-integrity.py
python scripts/validation/check-phase-order.py
python scripts/validation/check-pipeline-dag-paths.py
```

Update the declarative DAG and executable phase map together.

## GitHub Pages does not deploy

1. Set **Settings -> Pages -> Source** to **GitHub Actions**.
2. Open the `Deploy pipeline documentation to GitHub Pages` workflow run.
3. Check the strict MkDocs build before the deployment job.
4. Run `mkdocs build --strict --clean` locally to reproduce navigation or link warnings.

GitHub Pages publishes `site-docs/`. It intentionally does not read `docs.zip` or generated
execution output under `docs/`.
