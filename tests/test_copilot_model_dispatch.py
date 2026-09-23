from __future__ import annotations

import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest
import uuid


REPO_ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which("pwsh") or shutil.which("powershell")


@unittest.skipUnless(POWERSHELL, "PowerShell is not available")
class CopilotModelDispatchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = REPO_ROOT / f".test-copilot-model-{uuid.uuid4().hex}"
        self.root.mkdir()
        self.addCleanup(shutil.rmtree, self.root)
        for relative in (
            "scripts/lib/Invoke-CopilotDispatch.ps1",
            "scripts/dispatchers/run-docs-copilot-batch.ps1",
            "scripts/tools/resolve-copilot-model.py",
        ):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO_ROOT / relative, target)
        self.config = self.root / "config" / "pipeline.yaml"
        self.config.parent.mkdir()
        self.config.write_text("copilot: {}\n", encoding="utf-8")
        self.agent = self.root / ".github" / "agents" / "test-agent.agent.md"
        self.agent.parent.mkdir(parents=True)
        self.agent.write_text("---\nmodel: 'Agent Display Name'\n---\n", encoding="utf-8")
        self.fake = self.root / "fake-copilot.ps1"
        self.fake.write_text(
            "$ErrorActionPreference = 'Stop'\n"
            "Add-Content -LiteralPath (Join-Path $PSScriptRoot 'calls.jsonl') "
            "-Value (ConvertTo-Json -InputObject @($args) -Compress)\n"
            "[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'output.md'), 'done')\n"
            "if ($env:FAKE_MODEL_WARNING) { Write-Output $env:FAKE_MODEL_WARNING }\n"
            "Write-Output 'AI Credits 1.0 (1s)'\n",
            encoding="utf-8",
        )
        self.environment = os.environ.copy()
        self.environment.pop("COBOL_DOCS_COPILOT_MODEL", None)
        self.environment.pop("FAKE_MODEL_WARNING", None)
        self.environment["PATH"] = str(Path(sys.executable).parent) + os.pathsep + self.environment["PATH"]
        self.environment["MODEL_TEST_PYTHON"] = sys.executable

    def run_ps(self, script: str, *, success: bool = True) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [POWERSHELL, "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'\n" + script],
            cwd=self.root,
            env=self.environment,
            text=True,
            encoding="utf-8",
            errors="replace",
            capture_output=True,
            timeout=90,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def calls(self) -> list[list[str]]:
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines()] if path.exists() else []

    def common_dispatch(self, extra: str = "") -> subprocess.CompletedProcess[str]:
        return self.run_ps(
            ". .\\scripts\\lib\\Invoke-CopilotDispatch.ps1\n"
            "$work = @([pscustomobject]@{TaskId=1; Prompt='test'})\n"
            "$code = Invoke-CopilotDispatchPool -WorkItems $work -Skipped @() -LabelPrefix TEST "
            "-Agent test-agent -CopilotCli .\\fake-copilot.ps1 -Throttle 1 "
            "-ResultsXml results.xml -UsageCsvPath usage.csv " + extra + "\n"
            "exit $code\n"
        )

    def test_common_precedence_argv_and_usage(self) -> None:
        scenarios = (
            ("config-model", "override-model", "override-model", "cli", "override-model"),
            ("config-model", None, "config-model", "config", "config-model"),
            ("auto", None, "auto", "config", "auto"),
            (None, None, "Agent Display Name", "agent", None),
        )
        for configured, override, model, source, cli_model in scenarios:
            with self.subTest(configured=configured, override=override):
                self.config.write_text(
                    f"copilot:\n  default_model: {configured}\n" if configured else "copilot: {}\n",
                    encoding="utf-8",
                )
                if override is None:
                    self.environment.pop("COBOL_DOCS_COPILOT_MODEL", None)
                else:
                    self.environment["COBOL_DOCS_COPILOT_MODEL"] = override
                self.common_dispatch()
                argv = self.calls()[-1]
                if cli_model:
                    self.assertEqual(argv[argv.index("--model") + 1], cli_model)
                    self.assertEqual(argv.count("--model"), 1)
                else:
                    self.assertNotIn("--model", argv)
                rows = list(csv.DictReader((self.root / "usage.csv").read_text(encoding="utf-8-sig").splitlines()))
                self.assertEqual(rows[-1]["Model"], model)
                self.run_ps(
                    "$r = @(Import-Clixml results.xml)[0]\n"
                    f"if ($r.SelectedModel -ne '{model}' -or $r.ModelSource -ne '{source}') {{ throw 'metadata' }}\n"
                )
        self.agent.unlink()
        self.config.unlink()
        self.common_dispatch()
        argv = self.calls()[-1]
        self.assertEqual(argv[argv.index("--model") + 1], "auto")

    def test_actual_cli_model_wins_usage_fallback(self) -> None:
        self.environment["COBOL_DOCS_COPILOT_MODEL"] = "requested-model"
        self.environment["FAKE_MODEL_WARNING"] = (
            'Warning: Custom agent "test-agent" specifies model "requested-model" '
            'which is not available; using "actual-model" instead'
        )
        self.common_dispatch()
        rows = list(csv.DictReader((self.root / "usage.csv").read_text(encoding="utf-8-sig").splitlines()))
        self.assertEqual(rows[-1]["Model"], "actual-model")

    def test_fingerprints_cache_and_content_invalidation_without_working_directory(self) -> None:
        (self.root / "input.json").write_text("{}", encoding="utf-8")
        (self.root / "unrelated-cwd").mkdir()
        self.run_ps(
            ". .\\scripts\\lib\\Invoke-CopilotDispatch.ps1\n"
            "$script:resolveCount = 0\n"
            "function python { $script:resolveCount++; & $env:MODEL_TEST_PYTHON @args }\n"
            "$inputPath = Join-Path $PWD 'input.json'\n"
            "$agentPath = Join-Path $PWD '.github\\agents\\test-agent.agent.md'\n"
            "$configPath = Join-Path $PWD 'config\\pipeline.yaml'\n"
            "Set-Location unrelated-cwd\n"
            "$a = Get-ResumeFingerprint -InputFiles $inputPath -Agent test-agent -Languages en\n"
            "$again = Get-ResumeFingerprint -InputFiles $inputPath -Agent test-agent -Languages en\n"
            "if ($a -ne $again -or $script:resolveCount -ne 1) { throw 'not cached' }\n"
            "$mtime = (Get-Item $agentPath).LastWriteTimeUtc\n"
            "Set-Content $agentPath \"---`nmodel: 'Other Display Name'`n---\"\n"
            "(Get-Item $agentPath).LastWriteTimeUtc = $mtime\n"
            "$b = Get-ResumeFingerprint -InputFiles $inputPath -Agent test-agent -Languages en\n"
            "Set-Content $configPath \"copilot:`n  default_model: config-model\"\n"
            "$c = Get-ResumeFingerprint -InputFiles $inputPath -Agent test-agent -Languages en\n"
            "$env:COBOL_DOCS_COPILOT_MODEL = 'override-model'\n"
            "$d = Get-ResumeFingerprint -InputFiles $inputPath -Agent test-agent -Languages en\n"
            "if (@($a,$b,$c,$d | Select-Object -Unique).Count -ne 4) { throw 'stale fingerprint' }\n"
            "if ($script:resolveCount -ne 4) { throw 'resolver invocation count' }\n"
        )

    def test_competing_model_args_and_invalid_config_fail_before_launch(self) -> None:
        self.config.write_text("copilot:\n  default_model: config-model\n", encoding="utf-8")
        for argument in ("@('--model','other')", "@('--model=other')"):
            with self.subTest(argument=argument):
                result = self.run_ps(
                    ". .\\scripts\\lib\\Invoke-CopilotDispatch.ps1\n"
                    "Invoke-CopilotDispatchPool -WorkItems @([pscustomobject]@{TaskId=1;Prompt='test'}) "
                    "-LabelPrefix TEST -Agent test-agent -CopilotCli .\\fake-copilot.ps1 "
                    f"-ResultsXml results.xml -AdditionalCopilotArgs {argument}\n",
                    success=False,
                )
                self.assertIn("AdditionalCopilotArgs", result.stderr)
        self.config.write_text("copilot: [", encoding="utf-8")
        self.run_ps(
            ". .\\scripts\\lib\\Invoke-CopilotDispatch.ps1\n"
            "Resolve-CopilotModelSelection -AgentName test-agent\n",
            success=False,
        )
        self.assertEqual(self.calls(), [])

    def test_agent_fallback_allows_additional_model_argument(self) -> None:
        self.common_dispatch("-AdditionalCopilotArgs @('--model','other')")
        argv = self.calls()[-1]
        self.assertEqual(argv.count("--model"), 1)
        self.assertEqual(argv[argv.index("--model") + 1], "other")

    def prepare_phase_d(self) -> None:
        (self.root / "source.CBL").write_text("IDENTIFICATION DIVISION.", encoding="utf-8")
        shared = self.root / "docs" / "_shared" / "source.CBL"
        (shared / "chunks").mkdir(parents=True)
        (shared / "_bundles").mkdir()
        (shared / "chunk-manifest.json").write_text('{"chunks":[{"id":"one"}]}', encoding="utf-8")
        (shared / "chunks" / "index.json").write_text(
            '{"chunks":[{"id":"one","file":"one.txt"}]}', encoding="utf-8"
        )
        (shared / "_bundles" / "one.bundle.json").write_text(
            '{"output_paths":{"en":"output.md"}}', encoding="utf-8"
        )
        (shared / "_bundles" / "one.bundle.md").write_text("# Test bundle", encoding="utf-8")

    def phase_d(self, extra: str = "", *, success: bool = True) -> subprocess.CompletedProcess[str]:
        return self.run_ps(
            "& .\\scripts\\dispatchers\\run-docs-copilot-batch.ps1 "
            "-Files source.CBL -Agent test-agent -CopilotCli .\\fake-copilot.ps1 "
            "-EnsureFactsSlices:$false -Throttle 1 -AllowLowerThrottle "
            "-NonInteractive -Resume -TrackUsage "
            "-ResultsXml results.xml -LogsDir logs -StatePath state.jsonl -PlanPath plan.json "
            + extra,
            success=success,
        )

    def test_phase_d_model_changes_invalidate_journal_and_plan(self) -> None:
        self.prepare_phase_d()
        self.phase_d()
        self.assertNotIn("--model", self.calls()[-1])
        self.phase_d()
        self.assertEqual(len(self.calls()), 1)
        self.agent.write_text("---\nmodel: 'Changed Agent'\n---\n", encoding="utf-8")
        self.phase_d()
        self.assertEqual(len(self.calls()), 2)
        self.assertNotIn("--model", self.calls()[-1])
        self.config.write_text("copilot:\n  default_model: config-model\n", encoding="utf-8")
        self.phase_d()
        self.assertEqual(len(self.calls()), 3)
        self.assertEqual(self.calls()[-1][self.calls()[-1].index("--model") + 1], "config-model")
        self.environment["COBOL_DOCS_COPILOT_MODEL"] = "override-model"
        self.environment["FAKE_MODEL_WARNING"] = (
            'specifies model "override-model" which is not available; using "actual-model" instead'
        )
        self.phase_d()
        self.assertEqual(len(self.calls()), 4)
        self.phase_d()
        self.assertEqual(len(self.calls()), 4)
        plan = json.loads((self.root / "plan.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(plan["params"]["Model"], "override-model")
        self.assertEqual(plan["params"]["CliModel"], "override-model")
        rows = [json.loads(line) for line in (self.root / "state.jsonl").read_text(encoding="utf-8-sig").splitlines()]
        self.assertEqual(rows[-1]["model"], "override-model")
        self.assertEqual(rows[-1]["model_source"], "cli")
        self.assertEqual(rows[-1]["usage"]["model"], "actual-model")
        usage_rows = list(csv.DictReader((self.root / "logs" / "copilot-usage.csv").read_text(encoding="utf-8-sig").splitlines()))
        self.assertEqual(usage_rows[-1]["model"], "actual-model")
        # Legacy journals lack model metadata and must never satisfy resume.
        for row in rows:
            row.pop("model", None)
            row.pop("cli_model", None)
        (self.root / "state.jsonl").write_text(
            "\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8"
        )
        self.phase_d()
        self.assertEqual(len(self.calls()), 5)

    def test_phase_d_rejects_competing_model_before_launch(self) -> None:
        self.prepare_phase_d()
        self.config.write_text("copilot:\n  default_model: config-model\n", encoding="utf-8")
        self.phase_d("-AdditionalCopilotArgs @('--model=other')", success=False)
        self.assertEqual(self.calls(), [])

    def test_phase_d_agent_fallback_allows_additional_model_argument(self) -> None:
        self.prepare_phase_d()
        self.phase_d("-AdditionalCopilotArgs @('--model=other')")
        argv = self.calls()[-1]
        self.assertEqual(argv.count("--model=other"), 1)
        self.assertNotIn("--model", argv)


if __name__ == "__main__":
    unittest.main()
