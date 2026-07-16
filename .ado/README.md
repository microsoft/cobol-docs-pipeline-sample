# Azure DevOps pipeline sample

## Description

[`azure-pipelines.yml`](azure-pipelines.yml) is the complete Azure DevOps CI sample for this
repository. It validates configuration, runs tests, executes deterministic phases A-C on Windows
and Linux, exercises Copilot dispatch in dry-run mode, builds the portal, and publishes scoped
pipeline artifacts.

## Installation

1. Create a pipeline in Azure DevOps from the repository.
2. Select **Existing Azure Pipelines YAML file**.
3. Set the YAML path to `/.ado/CI-Sample.yml`.
4. In the `cobolSources` repository resource, replace `MainframeProject/CobolSources` with the
	Azure DevOps `Project/Repository` containing the mainframe source files.
5. Grant the pipeline's build identity read access to both repositories and authorize the
	`cobolSources` resource when prompted on the first run.
6. Keep `docsCopilotDryRun` set to `true` unless the agent has an authenticated Copilot CLI.

The sample assumes the COBOL repository is Azure Repos Git in the same organization. For another
Azure DevOps organization or for GitHub/Bitbucket, change the repository resource `type` and add
an `endpoint` service connection. Cross-project Azure Repos access may also require adjusting
**Limit job authorization scope** or explicitly granting the project build service read access.

For Azure Repos Git, enable this pipeline as a **Build validation** branch policy on `main` and
`develop`; Azure Repos does not use YAML `pr` triggers. The `pr` block in the sample applies when
Azure Pipelines is connected to a GitHub or Bitbucket Cloud repository.

No deployment credentials are required for the default dry-run sample. Store any future service
connections or tokens in Azure DevOps service connections or secret variables; never commit them.

## Usage

The sample runs for changes to this repository and for pushes to `main` in the declared
`cobolSources` repository. Each job checks out this project to `s/project` and COBOL sources to
`s/cobol-sources`; `workspaceRepo: true` keeps script execution rooted in this project.

Queue-time parameters select the external ref and files:

- `cobolRef`: branch, tag, or SHA ref; defaults to `refs/heads/main`.
- `cobolSourceGlob`: source glob relative to the external checkout; defaults to `COBOL/*.CBL`.

Other runtime behavior is controlled by variables such as `throttle` and `docsCopilotDryRun`.
The default `docsCopilotCli: pwsh` is a harmless command target used only to exercise dry-run
dispatch on agents where Copilot CLI is not installed. Set it to `copilot` only when enabling
authenticated live dispatch.

Published artifacts:

- `pipeline-batch-results`: phase A-C CLIXML result files.
- `copilot-doc-results`: dry-run Copilot dispatcher result file.
- `documentation-website`: generated static portal.

## License

This sample is provided under the repository's [MIT License](../LICENSE).