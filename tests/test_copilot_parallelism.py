from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

import jsonschema
import yaml

import test_output_languages as language_tests
from test_output_languages import BASH, POWERSHELL, REPO_ROOT


RESOLVER = REPO_ROOT / "scripts" / "tools" / "resolve-copilot-parallelism.py"
spec = importlib.util.spec_from_file_location("copilot_parallelism", RESOLVER)
assert spec and spec.loader
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


class CopilotParallelismTests(unittest.TestCase):
    def test_defaults_and_precedence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pipeline.yaml"
            path.write_text("source_root: .\n", encoding="utf-8")
            self.assertEqual(resolver.resolve_parallelism(path), [16] * 4)
            path.write_text("pipeline:\n  copilot_parallelism: 24\n", encoding="utf-8")
            self.assertEqual(resolver.resolve_parallelism(path), [24] * 4)
            self.assertEqual(
                resolver.resolve_parallelism(path, "32", sections="1", finalizer="2"),
                [32, 1, 2, 32],
            )

    def test_invalid_config_and_overrides_fail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pipeline.yaml"
            for content in ("[]", "pipeline: null", "pipeline: []", *(
                f"pipeline:\n  copilot_parallelism: {value}\n"
                for value in ("0", "-1", "33", "true", "null", "1.5", "'16'")
            )):
                with self.subTest(content=content):
                    path.write_text(content, encoding="utf-8")
                    result = subprocess.run(
                        [sys.executable, str(RESOLVER), "--config", str(path)],
                        capture_output=True, text=True, timeout=30,
                    )
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(result.stdout, "")
            path.write_text("pipeline: {}\n", encoding="utf-8")
            for value in ("", "0", "-1", "33", "true", "1.5"):
                for option in ("throttle", *resolver.SCOPES):
                    with self.subTest(value=value, option=option), self.assertRaises(ValueError):
                        resolver.resolve_parallelism(path, **{option: value})

    def test_schema_limits(self) -> None:
        schema = json.loads((REPO_ROOT / "config" / "pipeline.schema.json").read_text())
        config = yaml.safe_load((REPO_ROOT / "config" / "pipeline.yaml").read_text())
        for limit in (1, 16, 32):
            config["pipeline"]["copilot_parallelism"] = limit
            jsonschema.validate(config, schema)
        for limit in (0, 33, True, "16", None, 1.5):
            with self.subTest(limit=limit), self.assertRaises(jsonschema.ValidationError):
                config["pipeline"]["copilot_parallelism"] = limit
                jsonschema.validate(config, schema)


class PipelineParallelismTests(unittest.TestCase):
    def check_runner(self, executable: str, shell: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            language_tests.PipelineLanguageTests().make_repository(root, shell, ["en"])
            # Keep phase D real, to verify that low limits reach its dispatcher unchanged.
            targets = [("D", root / "scripts" / "dispatchers" / f"run-docs-copilot-batch.{shell}")]
            for phase in "EFGHIJKLM":
                original = next((REPO_ROOT / "scripts" / "phases").glob(f"phase-{phase}-*.{shell}"))
                targets.append((phase, root / "scripts" / "phases" / original.name))
            for phase, target in targets:
                if shell == "ps1":
                    probe = (
                        "param([int]$Throttle, [int]$SectionThrottle, [int]$FinalizerThrottle, "
                        "[int]$DiagramsThrottle, [switch]$AllowLowerThrottle)\n"
                        f'Write-Host "LIMIT:{phase}:$Throttle,$SectionThrottle,$FinalizerThrottle,$DiagramsThrottle"\n'
                        'if ($Throttle -lt 10 -and "' + phase + '" -eq "D" -and -not $AllowLowerThrottle) { exit 7 }\n'
                        "exit 0\n"
                    )
                else:
                    probe = (
                        "#!/usr/bin/env bash\nset -euo pipefail\n"
                        "t=0; s=0; f=0; d=0\n"
                        'while (($#)); do\ncase "$1" in\n'
                        '-Throttle) t="$2"; shift ;;\n-SectionThrottle) s="$2"; shift ;;\n'
                        '-FinalizerThrottle) f="$2"; shift ;;\n-DiagramsThrottle) d="$2"; shift ;;\n'
                        'esac\nshift\ndone\n'
                        f'printf "LIMIT:{phase}:%s,%s,%s,%s\\n" "$t" "$s" "$f" "$d"\n'
                    )
                target.write_text(probe, encoding="utf-8", newline="\n")
                target.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = str(Path(sys.executable).parent) + os.pathsep + environment["PATH"]
            if shell == "sh":
                bin_dir = root / "bin"
                bin_dir.mkdir()
                shim = bin_dir / "python3"
                shim.write_text(
                    f'#!/usr/bin/env bash\nexec {shlex.quote(Path(sys.executable).as_posix())} "$@"\n',
                    encoding="utf-8", newline="\n",
                )
                shim.chmod(0o755)
                environment["PATH"] = str(bin_dir) + os.pathsep + environment["PATH"]
            scenarios = [
                ({}, [], [16] * 4),
                ({"copilot_parallelism": 24}, [], [24] * 4),
                ({"copilot_parallelism": 24}, ["-CopilotThrottle", "32"], [32] * 4),
                ({}, ["-CopilotThrottle", "8", "-CopilotDocsThrottle", "1",
                      "-SectionFinalizerThrottle", "2", "-DiagramsThrottle", "3"], [8, 1, 2, 3]),
                ({}, ["-CopilotThrottle", "0"], None),
                ({}, ["-DiagramsThrottle", "33"], None),
                ({}, ["-CopilotThrottle", "1.5"], None),
            ]
            for pipeline, options, expected in scenarios:
                with self.subTest(shell=shell, pipeline=pipeline, options=options):
                    (root / "config" / "pipeline.yaml").write_text(yaml.safe_dump({
                        "source_root": "sources", "include": ["**/*.CBL"], "pipeline": pipeline,
                    }), encoding="utf-8")
                    command = (
                        [executable, "-NoProfile", "-File", "scripts/run-pipeline.ps1"]
                        if shell == "ps1" else [executable, "scripts/run-pipeline.sh"]
                    )
                    result = subprocess.run(
                        [*command, "-From", "D", "-To", "M", "-Throttle", "3",
                         "-MaxPhaseRetries", "0", *options],
                        cwd=root, env=environment, capture_output=True, text=True, timeout=180,
                    )
                    output = result.stdout + result.stderr
                    received = dict(re.findall(r"^LIMIT:([D-M]):([\d,]+)\s*$", result.stdout, re.MULTILINE))
                    if expected is None:
                        self.assertNotEqual(result.returncode, 0, output)
                        self.assertEqual(received, {}, output)
                        continue
                    self.assertEqual(result.returncode, 0, output)
                    shared, sections, finalizer, diagrams = expected
                    self.assertEqual(received["D"], f"{sections},0,0,0", output)
                    self.assertEqual(received["E"], f"3,0,{finalizer},0", output)
                    self.assertEqual(received["H"], f"3,0,0,{diagrams}", output)
                    for phase in "FG":
                        self.assertEqual(received[phase], f"3,{shared},{shared},0", output)
                    for phase in "JK":
                        self.assertEqual(received[phase].split(",")[1:3], [str(shared)] * 2, output)
                    for phase in "ILM":
                        self.assertEqual(received[phase].split(",")[2], str(shared), output)

    @unittest.skipUnless(POWERSHELL, "PowerShell not installed")
    def test_powershell_forwarding(self) -> None:
        self.check_runner(POWERSHELL, "ps1")

    @unittest.skipUnless(BASH, "Bash not installed")
    def test_bash_forwarding(self) -> None:
        self.check_runner(BASH, "sh")


@unittest.skipUnless(BASH, "Bash not installed")
class NativeDispatchParallelismTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        language_tests.PipelineLanguageTests().make_repository(self.root, "sh", ["en"])
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        shim = bin_dir / "python3"
        shim.write_text(
            f'#!/usr/bin/env bash\nexec {shlex.quote(Path(sys.executable).as_posix())} "$@"\n',
            encoding="utf-8", newline="\n",
        )
        shim.chmod(0o755)
        self.environment = os.environ.copy()
        self.environment["PATH"] = str(bin_dir) + os.pathsep + self.environment["PATH"]

    def test_real_native_phases_forward_all_dispatch_limits(self) -> None:
        native_phase = self.root / "scripts" / "lib" / "native-phase.sh"
        paths = set(re.findall(
            r"(?:\.github/skills|scripts/dispatchers)/[\w./-]+\.sh",
            native_phase.read_text(encoding="utf-8"),
        ))
        for relative in paths:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(
                '#!/usr/bin/env bash\nset -euo pipefail\n'
                'while (($#)); do\n'
                'if [[ "$1" == -Throttle ]]; then\n'
                f'printf "DISPATCH:{target.name}:%s\\n" "$2"; exit 0\n'
                'fi\nshift\ndone\nexit 9\n',
                encoding="utf-8", newline="\n",
            )
            target.chmod(0o755)
        for phase in "DEFGHIJKLM":
            with self.subTest(phase=phase):
                result = subprocess.run(
                    [BASH, str(native_phase), phase, "-Files", "sources/PROG.CBL",
                     "-DryRun", "-Throttle", "2", "-SectionThrottle", "7",
                     "-FinalizerThrottle", "11", "-DocsThrottle", "3", "-DiagramsThrottle", "3"],
                    cwd=self.root, env=self.environment, capture_output=True, text=True, timeout=180,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                dispatched = re.findall(r"^DISPATCH:(run-docs-[\w-]+\.sh):(\d+)$", result.stdout, re.MULTILINE)
                self.assertEqual(len(dispatched), 2 if phase in "FGJK" else 1, result.stdout)
                for name, limit in dispatched:
                    expected = 3 if phase in "DH" else (7 if "-section-" in name else 11)
                    self.assertEqual(int(limit), expected, result.stdout)

    def test_native_workers_are_concurrent_and_bounded(self) -> None:
        worker = self.root / "worker.py"
        worker.write_text(
            "import json, pathlib, sys, time\n"
            "start = time.monotonic()\n"
            "time.sleep(0.5)\n"
            "pathlib.Path(f'timing-{sys.argv[1]}.json').write_text("
            "json.dumps([start, time.monotonic()]))\n",
            encoding="utf-8",
        )
        command = (
            'source scripts/lib/native-common.sh\n'
            'worker() { "$(native_python)" worker.py "$1"; }\n'
            'inputs=(0 1 2 3 4 5)\n'
            'native_run_python_batch 2 results.xml worker inputs\n'
        )
        result = subprocess.run(
            [BASH, "-c", command], cwd=self.root, env=self.environment,
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        results = ET.parse(self.root / "results.xml").getroot()
        self.assertEqual(len(results), 6)
        self.assertTrue(all(item.findtext("exit") == "0" for item in results))
        events = []
        for index in range(6):
            start, end = json.loads((self.root / f"timing-{index}.json").read_text())
            events.extend(((start, 1), (end, -1)))
        active = peak = 0
        for _, delta in sorted(events):
            active += delta
            peak = max(peak, active)
        self.assertEqual(peak, 2)


if __name__ == "__main__":
    unittest.main()
