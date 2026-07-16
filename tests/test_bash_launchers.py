from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GENERATOR = REPO_ROOT / "scripts" / "tools" / "generate-bash-launchers.py"


class BashLauncherTests(unittest.TestCase):
    def test_generated_launchers_match_powershell_inventory(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(GENERATOR), "--check"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )

        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("Native Bash entry points OK", completed.stdout)

    def test_public_pipeline_launcher_exists(self) -> None:
        launcher = REPO_ROOT / "scripts" / "run-pipeline.sh"

        self.assertTrue(launcher.is_file())
        content = launcher.read_text(encoding="utf-8")
        self.assertIn("lib/native-common.sh", content)
        self.assertIn("phases/phase-D-section-docs.sh", content)

        phase_launcher = REPO_ROOT / "scripts" / "phases" / "phase-D-section-docs.sh"
        self.assertIn("lib/native-phase.sh", phase_launcher.read_text(encoding="utf-8"))

    def test_shell_entry_points_do_not_delegate_to_powershell(self) -> None:
        forbidden = re.compile(r"(?:pwsh|powershell|\.ps1|invoke-pwsh)", re.IGNORECASE)
        shell_files = list((REPO_ROOT / "scripts").rglob("*.sh"))
        shell_files.extend((REPO_ROOT / ".github" / "skills").rglob("*.sh"))

        violations = [
            str(path.relative_to(REPO_ROOT))
            for path in shell_files
            if forbidden.search(path.read_text(encoding="utf-8"))
        ]
        self.assertEqual(violations, [])

    def test_phase_launcher_is_colocated(self) -> None:
        phase_dir = REPO_ROOT / "scripts" / "phases"

        self.assertTrue((phase_dir / "phase-A-chunk.ps1").is_file())
        self.assertTrue((phase_dir / "phase-A-chunk.sh").is_file())

    def test_native_pipeline_honors_phase_retry_limit(self) -> None:
        with tempfile.TemporaryDirectory(dir=REPO_ROOT) as temporary_directory:
            results_dir = Path(temporary_directory).relative_to(REPO_ROOT).as_posix()
            completed = subprocess.run(
                [
                    "bash",
                    "scripts/run-pipeline.sh",
                    "-Files",
                    f"{results_dir}/missing.cbl",
                    "-From",
                    "A",
                    "-To",
                    "A",
                    "-MaxPhaseRetries",
                    "2",
                    "-ResultsDir",
                    results_dir,
                ],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
            )

        output = completed.stdout + completed.stderr
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(output.count("Phase A failed; retry"), 2)
        self.assertIn("Pipeline aborted at phase A", output)

    def test_native_docx_invokes_pandoc_directly(self) -> None:
        with tempfile.TemporaryDirectory(dir=REPO_ROOT) as temporary_directory:
            temporary_path = Path(temporary_directory)
            relative_path = temporary_path.relative_to(REPO_ROOT)
            markdown_path = temporary_path / "document.md"
            pandoc_path = temporary_path / "fake-pandoc.sh"
            results_path = temporary_path / "results.xml"
            markdown_path.write_text("# Native DOCX\n", encoding="utf-8")
            pandoc_path.write_bytes(
                (
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "output=''\n"
                "while (($#)); do\n"
                "  if [[ \"$1\" == --output ]]; then output=\"$2\"; shift 2; else shift; fi\n"
                "done\n"
                "printf 'native docx\\n' > \"${output}\"\n"
                ).encode("utf-8")
            )
            pandoc_path.chmod(0o755)
            completed = subprocess.run(
                [
                    "bash",
                    "scripts/lib/native-docx.sh",
                    "-MarkdownPaths",
                    (relative_path / markdown_path.name).as_posix(),
                    "-PandocPath",
                    (relative_path / pandoc_path.name).as_posix(),
                    "-ResultsXml",
                    (relative_path / results_path.name).as_posix(),
                ],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
            )

            results_content = results_path.read_text(encoding="utf-8")
            self.assertEqual(
                completed.returncode,
                0,
                completed.stdout + completed.stderr + results_content,
            )
            self.assertEqual(
                (temporary_path / "document.docx").read_text(encoding="utf-8"),
                "native docx\n",
            )
            self.assertIn("<exit>0</exit>", results_content)


if __name__ == "__main__":
    unittest.main()