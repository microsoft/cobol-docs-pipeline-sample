from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


REPO_ROOT = Path(__file__).resolve().parents[1]
POWERSHELLS = list(dict.fromkeys(
    executable for name in ("pwsh", "powershell")
    if (executable := shutil.which(name))
))
PANDOC = shutil.which("pandoc")


@unittest.skipUnless(POWERSHELLS and PANDOC, "PowerShell and pandoc are required")
class MdToDocxTests(unittest.TestCase):
    def run_powershell(self, shell: str, script: str, directory: Path) -> dict:
        env = {
            **{key: value for key, value in os.environ.items()
               if key.upper() != "PSMODULEPATH"},
            "DOCX_TEST_ROOT": str(REPO_ROOT),
            "DOCX_TEST_DIR": str(directory),
            "DOCX_TEST_PANDOC": str(PANDOC),
        }
        result = subprocess.run(
            [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", """
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$WarningPreference = 'Continue'
. (Join-Path $env:DOCX_TEST_ROOT 'scripts/lib/Convert-MdToDocx.ps1')
Set-Location -LiteralPath $env:DOCX_TEST_DIR
""" + script],
            env=env, cwd=REPO_ROOT, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=90,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = next(
            line.removeprefix("RESULT:")
            for line in result.stdout.splitlines() if line.startswith("RESULT:")
        )
        return json.loads(payload)

    def assert_docx(self, path: Path) -> None:
        with zipfile.ZipFile(path) as archive:
            self.assertIsNone(archive.testzip())
            self.assertIn("word/document.xml", archive.namelist())

    def test_warning_does_not_abort_and_up_to_date_output_is_skipped(self) -> None:
        for shell in POWERSHELLS:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                source = directory / "input with spaces.md"
                content = "# Example\n\nLiteral `[^unused]`.\n\n[^unused]: Evidence.\n"
                source.write_text(content, encoding="utf-8")
                result = self.run_powershell(shell, """
$warnings = @()
$result = Convert-MdToDocx -MarkdownPath './input with spaces.md' -PandocPath $env:DOCX_TEST_PANDOC -WarningVariable warnings
$skip = Convert-MdToDocx -MarkdownPath './input with spaces.md' -PandocPath $env:DOCX_TEST_PANDOC
Write-Output ('RESULT:' + (@{
  Result = $result; Skip = $skip; Warnings = @($warnings | ForEach-Object { "$_" })
  ErrorPreference = "$ErrorActionPreference"; NativePreference = $PSNativeCommandUseErrorActionPreference
} | ConvertTo-Json -Depth 5 -Compress))
""", directory)
                self.assertEqual(result["Result"]["Status"], "converted")
                self.assertEqual(result["Result"]["Exit"], 0)
                self.assertIn("not used", result["Result"]["Stderr"])
                self.assertTrue(any("not used" in w for w in result["Warnings"]))
                self.assertEqual(result["Skip"]["Status"], "skipped-up-to-date")
                self.assertEqual(result["ErrorPreference"], "Stop")
                self.assertTrue(result["NativePreference"])
                self.assertEqual(source.read_text(encoding="utf-8"), content)
                self.assert_docx(source.with_suffix(".docx"))

    def test_real_pandoc_failure_returns_nonzero_and_diagnostics(self) -> None:
        for shell in POWERSHELLS:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                (directory / "input.md").write_text("# Valid input\n", encoding="utf-8")
                (directory / "invalid reference.docx").write_text("not a ZIP archive")
                result = self.run_powershell(shell, """
$result = Convert-MdToDocx -MarkdownPath './input.md' -ReferenceDoc './invalid reference.docx' -PandocPath $env:DOCX_TEST_PANDOC
Write-Output ('RESULT:' + (@{
  Result = $result; ErrorPreference = "$ErrorActionPreference"
  NativePreference = $PSNativeCommandUseErrorActionPreference
} | ConvertTo-Json -Depth 5 -Compress))
""", directory)
                self.assertEqual(result["Result"]["Status"], "failed")
                self.assertNotEqual(result["Result"]["Exit"], 0)
                self.assertTrue(result["Result"]["Stderr"])
                self.assertEqual(result["ErrorPreference"], "Stop")
                self.assertTrue(result["NativePreference"])

    def test_missing_executable_is_not_a_success_with_stale_exit_code(self) -> None:
        for shell in POWERSHELLS:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                (directory / "input.md").write_text("# Example\n", encoding="utf-8")
                result = self.run_powershell(shell, """
$LASTEXITCODE = 0
$caught = $false
try {
  $null = Convert-MdToDocx -MarkdownPath './input.md' -PandocPath './missing-pandoc.exe'
} catch { $caught = $true }
Write-Output ('RESULT:' + (@{ Caught = $caught; ErrorPreference = "$ErrorActionPreference" } | ConvertTo-Json -Compress))
""", directory)
                self.assertTrue(result["Caught"])
                self.assertEqual(result["ErrorPreference"], "Stop")
                self.assertFalse((directory / "input.docx").exists())

    def test_batch_keeps_failure_when_a_later_conversion_succeeds(self) -> None:
        for shell in POWERSHELLS:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                for name in ("first", "second"):
                    (directory / f"{name}.md").write_text("# Example\n", encoding="utf-8")
                (directory / "first.docx").mkdir()
                result = self.run_powershell(shell, """
$results = @(Invoke-MdToDocxBatch -MarkdownPaths './first.md','./second.md' -PandocPath $env:DOCX_TEST_PANDOC -Force)
Write-Output ('RESULT:' + (@{ Results = $results } | ConvertTo-Json -Depth 5 -Compress))
""", directory)
                self.assertEqual(len(result["Results"]), 2)
                self.assertEqual(result["Results"][0]["Status"], "failed")
                self.assertNotEqual(result["Results"][0]["Exit"], 0)
                self.assertEqual(result["Results"][1]["Status"], "converted")
                self.assert_docx(directory / "second.docx")

    def test_phase_failure_gates_reject_failed_docx_results(self) -> None:
        for shell in POWERSHELLS:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as tmp:
                result = self.run_powershell(shell, """
$checks = @()
foreach ($phase in Get-ChildItem (Join-Path $env:DOCX_TEST_ROOT 'scripts/phases/phase-*.ps1')) {
  $tokens = $null
  $errors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($phase.FullName, [ref]$tokens, [ref]$errors)
  if ($errors.Count) { throw "Parse error in $($phase.Name): $errors" }
  $gate = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.IfStatementAst] -and
      $node.Clauses[0].Item1.Extent.Text -eq '$docxFail.Count -gt 0'
  }, $true)
  if (-not $gate) { continue }
  $action = [scriptblock]::Create($gate.Extent.Text)
  $docxFail = @([pscustomobject]@{ MarkdownPath = 'first.md'; Stderr = 'conversion failed'; Exit = 1 })
  $caught = $false
  try { & $action } catch { $caught = $true }
  $docxFail = @()
  & $action
  $checks += @{ Phase = $phase.Name; Rejected = $caught }
}
Write-Output ('RESULT:' + (@{ Checks = $checks } | ConvertTo-Json -Depth 5 -Compress))
""", Path(tmp))
                self.assertEqual(len(result["Checks"]), 8)
                for check in result["Checks"]:
                    self.assertTrue(check["Rejected"], check["Phase"])


if __name__ == "__main__":
    unittest.main()
