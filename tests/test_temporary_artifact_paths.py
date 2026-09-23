from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class TemporaryArtifactPathTests(unittest.TestCase):
    def test_copilot_dispatch_keeps_runtime_artifacts_under_temp(self) -> None:
        dispatcher = (
            REPO_ROOT / "scripts" / "dispatchers" / "run-docs-copilot-batch.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("[string]$LogsDir = 'temp/logs'", dispatcher)
        self.assertIn("Join-Path $logsDir 'copilot-usage.csv'", dispatcher)
        self.assertIn("$psi.EnvironmentVariables['TEMP'] = $tempRoot", dispatcher)
        self.assertIn("$psi.EnvironmentVariables['TMP']  = $tempRoot", dispatcher)
        self.assertIn("[void]$argv.Add($copilotLogDir)", dispatcher)

    def test_shared_dispatch_usage_log_is_under_temp(self) -> None:
        helper = (
            REPO_ROOT / "scripts" / "lib" / "Invoke-CopilotDispatch.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn(
            "Join-Path $WorkingDirectory 'temp/logs/copilot-usage.csv'",
            helper,
        )
        self.assertNotIn(
            "Join-Path $WorkingDirectory 'logs/copilot-usage.csv'",
            helper,
        )

    def test_python_batch_uses_repo_temp_directory(self) -> None:
        helper = (
            REPO_ROOT / "scripts" / "lib" / "Invoke-PythonBatch.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("'temp/python-batch'", helper)
        self.assertIn("$env:PYTHONDONTWRITEBYTECODE = '1'", helper)
        self.assertNotIn("New-TemporaryFile", helper)


if __name__ == "__main__":
    unittest.main()
