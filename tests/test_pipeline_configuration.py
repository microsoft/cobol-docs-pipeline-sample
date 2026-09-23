from __future__ import annotations

import importlib.util
import itertools
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

import jsonschema
import yaml

import test_output_languages as language_tests


REPO_ROOT = Path(__file__).resolve().parents[1]
RESOLVER = REPO_ROOT / "scripts" / "tools" / "resolve-output-phases.py"
spec = importlib.util.spec_from_file_location("output_phases", RESOLVER)
assert spec and spec.loader
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)
KEYS = ("docs", "functional_analysis", "requirements", "technical_analysis")


def expected_phases(switches: dict[str, bool]) -> str:
    if not any(switches.values()):
        return ""
    phases = set("ABCDEIN")
    if switches["docs"]:
        phases.add("H")
    if switches["requirements"] or switches["functional_analysis"]:
        phases.update("FJ")
    if switches["functional_analysis"]:
        phases.update("GK")
    if switches["technical_analysis"]:
        phases.update("LM")
    return "".join(sorted(phases))


class OutputPhaseTests(unittest.TestCase):
    def test_all_output_combinations_and_schema(self) -> None:
        schema = json.loads((REPO_ROOT / "config" / "pipeline.schema.json").read_text())
        config = yaml.safe_load((REPO_ROOT / "config" / "pipeline.yaml").read_text())
        jsonschema.validate(config, schema)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pipeline.yaml"
            for values in itertools.product((False, True), repeat=4):
                switches = dict(zip(KEYS, values))
                with self.subTest(switches=switches):
                    config["output"]["generate"] = switches
                    jsonschema.validate(config, schema)
                    path.write_text(yaml.safe_dump(config), encoding="utf-8")
                    self.assertEqual("".join(resolver.resolve_phases(path)), expected_phases(switches))

    def test_omitted_switches_keep_full_generation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pipeline.yaml"
            for config in ({}, {"output": {}}, {"output": {"generate": {}}},
                           {"output": {"generate": {"docs": False}}}):
                with self.subTest(config=config):
                    path.write_text(yaml.safe_dump(config), encoding="utf-8")
                    expected = "ABCDEFGHIJKLMN"
                    if config.get("output", {}).get("generate", {}).get("docs") is False:
                        expected = expected.replace("H", "")
                    self.assertEqual("".join(resolver.resolve_phases(path)), expected)

    def test_invalid_generation_fails_runtime_and_schema(self) -> None:
        schema = json.loads((REPO_ROOT / "config" / "pipeline.schema.json").read_text())
        config = yaml.safe_load((REPO_ROOT / "config" / "pipeline.yaml").read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pipeline.yaml"
            for invalid in (None, [], "docs", {"unknown": True}, {"docs": "false"},
                            {"docs": 0}, {"docs": None}, {"requirements": 1}):
                with self.subTest(invalid=invalid):
                    config["output"]["generate"] = invalid
                    with self.assertRaises(jsonschema.ValidationError):
                        jsonschema.validate(config, schema)
                    path.write_text(yaml.safe_dump(config), encoding="utf-8")
                    result = subprocess.run(
                        [sys.executable, str(RESOLVER), "--config", str(path)],
                        capture_output=True, text=True, timeout=30,
                    )
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("output.generate", result.stderr)

    def test_invalid_or_missing_config_fails_explicitly(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pipeline.yaml"
            with self.assertRaises(OSError):
                resolver.resolve_phases(path)
            for content in ("", "[]", "output: null", "output: []"):
                with self.subTest(content=content), self.assertRaises(ValueError):
                    path.write_text(content, encoding="utf-8")
                    resolver.resolve_phases(path)


class PipelineGenerationTests(unittest.TestCase):
    def check_runner(self, executable: str, shell: str) -> None:
        disabled = dict.fromkeys(KEYS, False)
        scenarios = [
            ({}, [], "ABCDEFGHIJKLMN", False, False),
            (disabled, [], "", True, False),
            *[(disabled | {key: True}, [], expected_phases(disabled | {key: True}), False, False)
              for key in KEYS],
            (disabled, ["-From", "F", "-To", "G"], "FG", False, False),
            (disabled, ["-From", "M"], "MN", False, False),
            (disabled, ["-To", "B"], "AB", False, False),
            (disabled, ["-Phases", "L", "-From", "A", "-To", "B"], "L", False, False),
            ({}, ["-Skip", "H", "-RunPortal:false"], "ABCDEFGIJKLM", False, False),
            (disabled | {"technical_analysis": True}, ["-RunSectionFinalizer:false"],
             "ABCDILMN", False, False),
            ({"docs": "false"}, ["-Phases", "A"], "", True, True),
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            language_tests.PipelineLanguageTests().make_repository(root, shell, ["it"])
            for phase in "ABCDEFGHIJKLMN":
                original = next((REPO_ROOT / "scripts" / "phases").glob(f"phase-{phase}-*.{shell}"))
                target = root / "scripts" / "phases" / original.name
                if shell == "ps1":
                    probe = f'param([string]$Languages)\nWrite-Host "PHASE:{phase}:$Languages"\nexit 0\n'
                else:
                    probe = (
                        "#!/usr/bin/env bash\nset -euo pipefail\nlanguage=''\n"
                        'while (($#)); do\n'
                        '  if [[ "$1" == -Languages ]]; then language="$2"; fi\n'
                        '  shift\ndone\n'
                        f'printf "PHASE:{phase}:%s\\n" "$language"\n'
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
            for switches, options, expected, missing_sources, fails in scenarios:
                with self.subTest(shell=shell, switches=switches, options=options):
                    config = {
                        "source_root": "missing" if missing_sources else "sources",
                        "include": ["**/*.CBL"],
                        "output": {"languages": ["it"], "generate": switches},
                    }
                    (root / "config" / "pipeline.yaml").write_text(
                        yaml.safe_dump(config), encoding="utf-8",
                    )
                    # -Command accepts Boolean switch values on Windows PowerShell 5.1 too.
                    if shell == "ps1":
                        arguments = " ".join(
                            option.replace(":false", ":$false") if option.startswith("-")
                            else "'" + option.replace("'", "''") + "'" for option in options
                        )
                        command = [executable, "-NoProfile", "-Command",
                                   f"& ./scripts/run-pipeline.ps1 -MaxPhaseRetries 0 {arguments}"]
                    else:
                        command = [executable, "scripts/run-pipeline.sh",
                                   "-MaxPhaseRetries", "0", *options]
                    result = subprocess.run(
                        command, cwd=root, env=environment,
                        capture_output=True, text=True, timeout=60,
                    )
                    output = result.stdout + result.stderr
                    received = re.findall(r"^PHASE:([A-N]):([a-z,]*)\s*$", result.stdout, re.MULTILINE)
                    self.assertEqual("".join(phase for phase, _ in received), expected, output)
                    if fails:
                        self.assertNotEqual(result.returncode, 0, output)
                        self.assertIn("output.generate", output)
                    else:
                        self.assertEqual(result.returncode, 0, output)
                        self.assertIn(
                            "Output languages: sections=it; requirements=it; functional=it; "
                            "technical=it; groups=it",
                            result.stdout,
                        )
                        if not expected:
                            self.assertIn("No phases selected", output)
                        for phase, language in received:
                            if phase in "DEFGIJKLM":
                                self.assertEqual(language, "it", output)

    @unittest.skipUnless(language_tests.POWERSHELL, "PowerShell is required")
    def test_powershell_generation_selection(self) -> None:
        self.check_runner(language_tests.POWERSHELL, "ps1")

    @unittest.skipUnless(language_tests.BASH, "Bash is required")
    def test_bash_generation_selection(self) -> None:
        self.check_runner(language_tests.BASH, "sh")


if __name__ == "__main__":
    unittest.main()
