# Script organization

The pipeline uses **feature ownership**, with native Bash entry points beside PowerShell entry
points where both platforms are supported.

## Feature ownership

| Path | Responsibility |
|------|----------------|
| `scripts/run-pipeline.ps1`, `scripts/run-pipeline.sh` | Native public A–N orchestrators and phase retry policies |
| `scripts/phases/` | One executable phase entry point per runner phase |
| `scripts/lib/` | Shared orchestration, dispatch, grouping, result, and DOCX helpers |
| `scripts/dispatchers/` | Copilot batch dispatchers used by LLM-backed phases |
| `scripts/validation/` | DAG, phase-order, path, and glossary drift checks |
| `scripts/portal/` | Static and offline portal builders |
| `scripts/tools/` | Standalone Python compatibility and inspection tools |
| `.github/skills/<feature>/scripts/` | Feature-owned deterministic preparation, validation, and assembly |
| `scripts/schemas/` | JSON schemas used by deterministic phases |

PowerShell and Bash are independent implementations. Bash entry points invoke the Python phase
engines, GitHub Copilot CLI, and Pandoc directly through shared `native-*.sh` helpers. They do not
launch PowerShell or delegate to `.ps1` files.

## Concurrency

Public runners keep phases sequential and parallelize work within each stage.
`-CopilotThrottle` sets the shared LLM worker limit for D-M (1-32), overriding
`pipeline.copilot_parallelism` in `config/pipeline.yaml`; the fallback is 16.
Explicit `-CopilotDocsThrottle`, `-SectionFinalizerThrottle`, and `-DiagramsThrottle`
take precedence for D, E, and H respectively. `-Throttle` controls deterministic
batches independently. Standalone phase/dispatcher defaults are unchanged.

The shared resolver is [resolve-copilot-parallelism.py](tools/resolve-copilot-parallelism.py).
The public runners do not consume declarative `execution_mode`, `per_file_parallelism`,
or DAG `max_parallel`. See [configuration guidance](../site-docs/guides/configuration.md#execution-settings).

## Copilot model

Both public runners accept `-CopilotModel <model-id|auto>`. Selection precedence is
the explicit CLI option, `copilot.default_model` in
[pipeline.yaml](../config/pipeline.yaml), the agent's `model:` frontmatter, then
Copilot automatic selection. The checked-in default is `claude-sonnet-4.5`.
Omit the configuration key to preserve each agent's default. Blank or null values
are rejected; `auto` is an explicit override, not an absent value.

[resolve-copilot-model.py](tools/resolve-copilot-model.py) resolves selection for both
platforms. Runners transport the resolved override through the internal, phase-scoped
`COBOL_DOCS_COPILOT_MODEL` environment variable; it is not a public configuration tier.
PowerShell restores the previous value even on a phase failure. Standalone dispatchers
also read the YAML model default. No agent files are rewritten.

## Platform launchers

| Path | Responsibility |
|------|----------------|
| `scripts/run-pipeline.cmd` | Windows `cmd.exe` launcher |
| `scripts/run-pipeline.sh` | Linux/macOS Bash launcher |
| `scripts/phases/*.sh` | Bash launchers beside A–N phase entry points |
| `scripts/dispatchers/*.sh` | Bash launchers beside Copilot batch dispatchers |
| `.github/skills/*/scripts/*.sh` | Bash launchers beside skill-owned batch scripts |
| `scripts/lib/native-common.sh` | Shared input, path, batch, and XML result helpers |
| `scripts/lib/native-skill-batch.sh` | Native deterministic skill batch implementation |
| `scripts/lib/native-copilot-dispatch.sh` | Native Copilot planning, dispatch, retry, and state handling |
| `scripts/lib/native-phase.sh` | Shared native implementation for phases D–N |
| `scripts/lib/native-docx.sh` | Native Pandoc conversion helper |

Regenerate or validate generated native entry points after adding or renaming a supported
PowerShell entry point:

```bash
python3 scripts/tools/generate-bash-launchers.py
python3 scripts/tools/generate-bash-launchers.py --check
```

Do not edit generated entry points directly. Update `generate-bash-launchers.py` or the owning
native shared engine instead. The eight maintained Bash files, including `run-pipeline.sh` and
the `native-*.sh` helpers, are edited directly.