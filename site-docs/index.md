# COBOL documentation pipeline

This portal explains how to configure, run, extend, and troubleshoot the repository's
mainframe and IBM i documentation pipeline. It documents the pipeline itself. Generated
program documentation is a separate phase-N execution result under `docs/_portal/`.

## Start here

<div class="grid cards" markdown>

-   **Run a deterministic smoke test**

    Install the Python dependencies and run phases A-C without model calls.

    [Getting started](getting-started.md)

-   **Understand the execution model**

    See how per-file work, workspace fan-in, agents, and deterministic scripts interact.

    [Architecture](concepts/architecture.md)

-   **Navigate the DAG**

    Compare declarative DAG nodes with executable runner phases A-N.

    [DAG and execution model](concepts/dag.md)

-   **Use your own sources**

    Configure source roots, globs, encodings, platforms, groups, and profiles.

    [Configuration](guides/configuration.md)

-   **Follow complete examples**

    Run mainframe and IBM i recipes from deterministic extraction through authored deliverables.

    [End-to-end examples](guides/examples.md)

-   **Inspect pipeline evidence**

    Read manifests, facts, cross-references, chunk slices, bundles, and QA findings.

    [Generated artifacts](guides/artifacts.md)

</div>

## Fastest working command

=== "Windows PowerShell"

    ```powershell
    python -m pip install pyyaml jsonschema
    pwsh -NoProfile -File scripts/run-pipeline.ps1 `
      -From A -To C `
      -Files repos/sample/COBOL/ORDR100.CBL `
      -SourceRoot repos/sample
    ```

=== "Linux or macOS"

    ```bash
    python3 -m pip install pyyaml jsonschema
    bash scripts/run-pipeline.sh \
      -From A -To C \
      -Files repos/sample/COBOL/ORDR100.CBL \
      -SourceRoot repos/sample
    ```

The deterministic smoke test creates a chunk manifest, a facts graph, incoming
cross-references, and raw chunk slices. Continue with the
[running guide](guides/running.md) when Copilot-authored documentation is required.

## Supported source families

| Platform | COBOL and data | Control and presentation |
|----------|----------------|--------------------------|
| Mainframe / z/OS | `.CBL`, `.COB`, `.CPY` | `.JCL`, `.PRC`, `.BMS` |
| IBM i / AS400 | `.CBLLE`, `.SQLCBLLE`, `.CBL`, `.COB`, `.CPY` | `.CL`, `.CLP`, `.CLLE` |

IBM i Control Language is modeled as `source_kind: cl`. It is not treated as JCL.

## Documentation products

| Product | Source | Built by | Purpose |
|---------|--------|----------|---------|
| Pipeline user guide | Tracked `site-docs/` | MkDocs and GitHub Pages | Explain how to operate this repository |
| Generated web portal | `docs/_portal/site/` | Phase N | Browse generated source documentation |
| Offline portal | `docs/_portal/site-offline/` | Phase N | Review generated docs from disk |

The products are intentionally independent. Publishing this user guide never requires a pipeline
run and never reads `docs.zip`.
