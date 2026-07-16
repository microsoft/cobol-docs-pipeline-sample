# GitHub Actions workflows

## CI sample

[`ci-sample.yml`](ci-sample.yml) validates this documentation pipeline while reading COBOL and related
mainframe sources from a separate GitHub repository. Every job checks out the source repository
into `repos/external` and passes that directory to the phase orchestrator.

## Installation

Configure these repository variables in the documentation repository under **Settings > Secrets
and variables > Actions > Variables**:

- `COBOL_REPOSITORY`: required `owner/repository` identifier for the source repository.
- `COBOL_REF`: optional branch, tag, or SHA; defaults to `main`.
- `COBOL_SOURCE_GLOB`: optional source glob relative to that repository; defaults to
  `COBOL/*.CBL`.

For a private source repository, create a `COBOL_REPOSITORY_TOKEN` Actions secret. Use a read-only
fine-grained personal access token or GitHub App installation token limited to **Contents: read**
on the source repository. The default `GITHUB_TOKEN` normally cannot read a different private
repository. Public source repositories do not require an additional token.

Manual runs can override repository, ref, and source glob through `workflow_dispatch` inputs.

## Usage

Changes in another repository do not automatically trigger this workflow. Add a workflow like the
following to the external COBOL repository and store a token with permission to dispatch workflows
in the documentation repository as `DOCUMENTATION_REPOSITORY_TOKEN`:

```yaml
name: Notify documentation pipeline

on:
  push:
    branches:
      - main
    paths:
      - "COBOL/**"
      - "JCL/**"
      - "COPYBOOK/**"

jobs:
  notify:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Dispatch documentation build
        env:
          GH_TOKEN: ${{ secrets.DOCUMENTATION_REPOSITORY_TOKEN }}
          DOCUMENTATION_REPOSITORY: your-org/your-documentation-repository
        run: |
          gh api \
            --method POST \
            "repos/${DOCUMENTATION_REPOSITORY}/dispatches" \
            -f event_type=cobol-sources-updated \
            -f 'client_payload[cobol_repository]=${{ github.repository }}' \
            -f 'client_payload[cobol_ref]=${{ github.sha }}' \
            -f 'client_payload[cobol_source_glob]=COBOL/*.CBL'
```

The receiving workflow validates `repository_dispatch` events with type
`cobol-sources-updated` and uses the payload values ahead of repository-variable defaults.

## GitHub Pages user guide

[`pages.yml`](pages.yml) publishes tracked repository and DAG pipeline documentation from
`site-docs/`. It does not publish phase-N execution output, download generated documentation
artifacts, or read `docs.zip`.

To enable it:

1. Open **Settings > Pages** in the documentation repository.
2. Select **GitHub Actions** as the source.
3. Merge a change under `site-docs/`, `mkdocs.yml`, or `requirements-docs.txt` into `main`, or run
  the workflow manually.

Preview the same strict build locally:

```console
python -m pip install -r requirements-docs.txt
mkdocs build --strict --clean
mkdocs serve
```

The generated site directory is `site/` and remains a disposable build output. Phase N continues
to own the separate generated-program portal under `docs/_portal/`.

## License

This sample is provided under the repository's [MIT License](../../LICENSE).
