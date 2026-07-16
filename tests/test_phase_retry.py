from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = REPO_ROOT / "scripts" / "lib" / "Resolve-PhaseInputs.ps1"
POWERSHELL = shutil.which("pwsh") or shutil.which("powershell")


@unittest.skipUnless(POWERSHELL, "PowerShell is required for phase retry tests")
class PhaseRetryTests(unittest.TestCase):
    def run_retry(self, fail_until: int, max_retries: int) -> tuple[int, int]:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            probe_path = temp_path / "phase-probe.ps1"
            counter_path = temp_path / "counter.txt"
            probe_path.write_text(
                """param([string]$CounterPath, [int]$FailUntil)
$count = if (Test-Path $CounterPath) { [int](Get-Content $CounterPath) } else { 0 }
$count++
Set-Content -Path $CounterPath -Value $count
if ($count -le $FailUntil) { exit 9 }
exit 0
""",
                encoding="utf-8",
            )

            environment = os.environ.copy()
            environment.update(
                {
                    "HELPER_PATH": str(HELPER_PATH),
                    "PROBE_PATH": str(probe_path),
                    "COUNTER_PATH": str(counter_path),
                    "FAIL_UNTIL": str(fail_until),
                    "MAX_RETRIES": str(max_retries),
                }
            )
            command = (
                ". $env:HELPER_PATH; "
                "$result = Invoke-PhaseWithRetry -PhaseId TEST "
                "-PhaseScript $env:PROBE_PATH "
                "-PhaseArgs @{ CounterPath = $env:COUNTER_PATH; "
                "FailUntil = [int]$env:FAIL_UNTIL } "
                "-MaxRetries ([int]$env:MAX_RETRIES); "
                "$attempts = [int](Get-Content $env:COUNTER_PATH); "
                "Write-Output \"RESULT=$result ATTEMPTS=$attempts\""
            )
            completed = subprocess.run(
                [POWERSHELL, "-NoProfile", "-Command", command],
                check=True,
                capture_output=True,
                text=True,
                env=environment,
            )

            result_line = next(
                line for line in completed.stdout.splitlines() if line.startswith("RESULT=")
            )
            values = dict(part.split("=", 1) for part in result_line.split())
            return int(values["RESULT"]), int(values["ATTEMPTS"])

    def test_retries_until_phase_succeeds(self) -> None:
        result, attempts = self.run_retry(fail_until=2, max_retries=3)

        self.assertEqual(result, 0)
        self.assertEqual(attempts, 3)

    def test_returns_final_exit_code_after_retry_exhaustion(self) -> None:
        result, attempts = self.run_retry(fail_until=10, max_retries=3)

        self.assertEqual(result, 9)
        self.assertEqual(attempts, 4)

    def test_zero_retries_runs_phase_once(self) -> None:
        result, attempts = self.run_retry(fail_until=1, max_retries=0)

        self.assertEqual(result, 9)
        self.assertEqual(attempts, 1)


if __name__ == "__main__":
    unittest.main()