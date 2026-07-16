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