# CI and GitHub Actions

## Validation workflow

`.github/workflows/ci-sample.yml` demonstrates cross-platform validation with an external source
repository. It includes:

- configuration and schema validation;
- unit tests;
- deterministic phases A-C on Windows and Linux;
- Bash launcher syntax and parity checks;
- Copilot dispatcher dry runs;
- phase-N execution-portal artifact creation.

Configure these repository variables when using a separate source repository:

| Variable | Meaning |
|----------|---------|
| `COBOL_REPOSITORY` | Source repository in `owner/name` format |
| `COBOL_REF` | Branch, tag, or commit, default `main` |
| `COBOL_SOURCE_GLOB` | Source glob relative to that repository |

Private source repositories also require a read-only `COBOL_REPOSITORY_TOKEN` secret.

Example repository variables for a source repository on its default branch:

```text
COBOL_REPOSITORY=example-org/order-mainframe
COBOL_REF=main
COBOL_SOURCE_GLOB=COBOL/*.CBL
```

Keep the token scoped to repository contents read access. The documentation pipeline repository
does not need permission to push changes into the source repository.

## Pipeline user documentation on GitHub Pages

`.github/workflows/pages.yml` builds this tracked MkDocs portal. It does not publish files from
`docs/` and does not depend on a pipeline execution.

The workflow runs when:

- `site-docs/**` changes on `main`;
- `mkdocs.yml` or `requirements-docs.txt` changes on `main`;
- the Pages workflow changes on `main`;
- a maintainer starts it manually.

Repository setup:

1. Open **Settings -> Pages**.
2. Set **Source** to **GitHub Actions**.
3. Merge the workflow and documentation files into `main` or run the workflow manually.
4. Open the deployment URL recorded in the `github-pages` environment.

The workflow uses the official `configure-pages`, `upload-pages-artifact`, and `deploy-pages`
actions. `mkdocs build --strict --clean` rejects broken navigation and documentation warnings.

## Local preview

```console
python -m pip install -r requirements-docs.txt
mkdocs serve
```

Open `http://127.0.0.1:8000/`. The preview reloads when files under `site-docs/` change.

For the same validation used in CI, run a clean strict build:

```console
python -m mkdocs build --strict --clean
```

The static output appears under the ignored `site/` directory. Do not commit that directory;
GitHub Actions rebuilds it from tracked Markdown on every documentation deployment.
