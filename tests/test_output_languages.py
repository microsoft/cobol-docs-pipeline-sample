from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

import jsonschema
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
RESOLVER = REPO_ROOT / "scripts" / "tools" / "resolve-output-languages.py"
spec = importlib.util.spec_from_file_location("output_languages", RESOLVER)
assert spec and spec.loader
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)
POWERSHELL = shutil.which("pwsh") or shutil.which("powershell")
BASH = shutil.which("bash")
if os.name == "nt" and (git := shutil.which("git")):
    git_bash = Path(git).parent.parent / "bin" / "bash.exe"
    if git_bash.is_file():
        BASH = str(git_bash)


class OutputLanguageTests(unittest.TestCase):
    def test_defaults_normalization_and_precedence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "pipeline.yaml"
            config.write_text("source_root: .\n", encoding="utf-8")
            self.assertEqual(resolver.resolve_languages(config), ["en"] * 5)
            config.write_text("output:\n  languages: [IT, en, it]\n", encoding="utf-8")
            self.assertEqual(resolver.resolve_languages(config), ["it,en"] * 5)
            self.assertEqual(
                resolver.resolve_languages(config, "en", sections=" IT, it "),
                ["it", "en", "en", "en", "en"],
            )
            self.assertEqual(
                resolver.resolve_languages(config, "fr-CA", groups="it"),
                ["fr-ca"] * 4 + ["it"],
            )

    def test_invalid_configuration_and_cli_fail_explicitly(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "pipeline.yaml"
            for content in (
                "[]", "output: null", "output: []",
                "output:\n  languages: []", "output:\n  languages: en,it",
                "output:\n  languages: [null]", "output:\n  languages: ['../it']",
            ):
                with self.subTest(content=content):
                    config.write_text(content, encoding="utf-8")
                    result = subprocess.run(
                        [sys.executable, str(RESOLVER), "--config", str(config)],
                        capture_output=True, text=True, timeout=30,
                    )
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("error:", result.stderr)
            config.write_text("output: {}\n", encoding="utf-8")
            for value in ("", "en,,it", "../it", "english", "en/it"):
                with self.subTest(value=value), self.assertRaises(ValueError):
                    resolver.resolve_languages(config, value)

    def test_schema_accepts_output_languages_and_rejects_bad_values(self) -> None:
        schema = json.loads((REPO_ROOT / "config" / "pipeline.schema.json").read_text())
        config = yaml.safe_load((REPO_ROOT / "config" / "pipeline.yaml").read_text())
        jsonschema.validate(config, schema)
        config["output"] = {"languages": ["en", "it"]}
        jsonschema.validate(config, schema)
        for invalid in ([], "en,it", ["../it"], ["en", "en"], [None]):
            with self.subTest(invalid=invalid), self.assertRaises(jsonschema.ValidationError):
                config["output"] = {"languages": invalid}
                jsonschema.validate(config, schema)


class PipelineLanguageTests(unittest.TestCase):
    def make_repository(self, root: Path, shell: str, config_languages: list[str] | None) -> None:
        copies = [
            f"scripts/run-pipeline.{shell}",
            "scripts/tools/resolve-output-languages.py",
            "scripts/tools/resolve-output-phases.py",
            "scripts/tools/resolve-copilot-parallelism.py",
            "scripts/tools/resolve-copilot-model.py",
            "scripts/tools/discover-sources.py",
            "scripts/lib/Resolve-PhaseInputs.ps1",
            "scripts/lib/native-common.sh",
            "scripts/lib/native-phase.sh",
            f"scripts/phases/phase-D-section-docs.{shell}",
        ]
        for relative in copies:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(
                (REPO_ROOT / relative).read_text(encoding="utf-8"),
                encoding="utf-8", newline="\n",
            )
            target.chmod(0o755)
        (root / ".github" / "skills").mkdir(parents=True)
        (root / "config").mkdir()
        (root / "sources").mkdir()
        (root / "sources" / "PROG.CBL").write_text("       STOP RUN.\n", encoding="utf-8")
        config = {"source_root": "sources", "include": ["**/*.CBL"]}
        if config_languages is not None:
            config["output"] = {"languages": config_languages}
        (root / "config" / "pipeline.yaml").write_text(yaml.safe_dump(config), encoding="utf-8")
        for relative in ("chunk-manifest.json", "facts.json", "chunks/one.txt"):
            path = root / "docs" / "_shared" / "PROG.CBL" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("{}", encoding="utf-8")
        dispatcher = root / "scripts" / "dispatchers" / f"run-docs-copilot-batch.{shell}"
        dispatcher.parent.mkdir()
        dispatcher.write_text(self.probe(shell, "D"), encoding="utf-8", newline="\n")
        dispatcher.chmod(0o755)
        for phase in ("E", "F", "G", "I", "J", "K", "L", "M"):
            original = next((REPO_ROOT / "scripts" / "phases").glob(f"phase-{phase}-*.{shell}"))
            target = root / "scripts" / "phases" / original.name
            target.write_text(self.probe(shell, phase), encoding="utf-8", newline="\n")
            target.chmod(0o755)

    @staticmethod
    def probe(shell: str, phase: str) -> str:
        if shell == "ps1":
            return f'param([string]$Languages)\nWrite-Host "LANG:{phase}:$Languages"\nexit 0\n'
        return (
            "#!/usr/bin/env bash\nset -euo pipefail\n"
            'while (($#)); do\n'
            f'  if [[ "$1" == -Languages ]]; then printf "LANG:{phase}:%s\\n" "$2"; exit 0; fi\n'
            '  shift\n'
            "done\nexit 7\n"
        )

    def check_runner(self, executable: str, shell: str) -> None:
        scenarios = [
            (None, [], ["en"] * 9),
            (["it"], [], ["it"] * 9),
            (["en", "it"], [], ["en,it"] * 9),
            (["en"], ["-Languages", "it"], ["it"] * 9),
            (["it"], ["-Languages", "en"], ["en"] * 9),
            (["en"], ["-Languages", "it", "-SectionFinalizerLanguages", "en",
                      "-RequirementsLanguages", "en", "-FunctionalAnalysisLanguages", "en",
                      "-TechnicalAnalysisLanguages", "en", "-GroupLanguages", "en"],
             ["en"] * 9),
            (["en"], ["-SectionFinalizerLanguages", "it"],
             ["it", "it"] + ["en"] * 7),
        ]
        for configured, options, expected in scenarios:
            with self.subTest(shell=shell, configured=configured, options=options):
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    self.make_repository(root, shell, configured)
                    environment = os.environ.copy()
                    environment["PATH"] = str(Path(sys.executable).parent) + os.pathsep + environment["PATH"]
                    if shell == "sh":
                        # Ensure Bash and PowerShell exercise the same Python environment.
                        bin_dir = root / "bin"
                        bin_dir.mkdir()
                        shim = bin_dir / "python3"
                        shim.write_text(
                            f"#!/usr/bin/env bash\nexec {shlex.quote(Path(sys.executable).as_posix())} \"$@\"\n",
                            encoding="utf-8", newline="\n",
                        )
                        shim.chmod(0o755)
                        environment["PATH"] = str(bin_dir) + os.pathsep + environment["PATH"]
                    command = [executable]
                    if shell == "ps1":
                        command += ["-NoProfile", "-File"]
                    command += [
                        f"scripts/run-pipeline.{shell}", "-From", "D", "-To", "M", "-Skip", "H",
                        "-MaxPhaseRetries", "0", *options,
                    ]
                    result = subprocess.run(
                        command, cwd=root, env=environment,
                        capture_output=True, text=True, timeout=60,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    received = re.findall(r"^LANG:([A-Z]):([a-z,-]+)\s*$", result.stdout, re.MULTILINE)
                    self.assertEqual(
                        received, list(zip(("D", "E", "F", "G", "I", "J", "K", "L", "M"), expected)),
                        result.stdout,
                    )

    @unittest.skipUnless(POWERSHELL, "PowerShell is required")
    def test_powershell_pipeline_forwards_languages_through_phase_d(self) -> None:
        self.check_runner(POWERSHELL, "ps1")

    @unittest.skipUnless(BASH, "Bash is required")
    def test_bash_pipeline_forwards_languages_through_phase_d(self) -> None:
        self.check_runner(BASH, "sh")


class BundleLanguageTests(unittest.TestCase):
    skills = (
        "section-doc-writer", "section-doc-finalizer",
        "requirements-writer", "requirements-finalizer",
        "functional-analysis-writer", "functional-analysis-finalizer",
        "group-doc-finalizer", "requirements-group-writer",
        "functional-analysis-group-writer", "technical-analysis-writer",
    )

    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        for skill in self.skills:
            source = REPO_ROOT / ".github" / "skills" / skill / "scripts"
            target = self.root / ".github" / "skills" / skill / "scripts"
            target.mkdir(parents=True)
            for script in source.glob("*.py"):
                shutil.copy2(script, target / script.name)
        lib = self.root / "scripts" / "lib"
        lib.mkdir(parents=True)
        for script in (REPO_ROOT / "scripts" / "lib").glob("*.py"):
            shutil.copy2(script, lib / script.name)

        self.write("sources/PROG.CBL", "       STOP RUN.\n")
        self.write("config/pipeline.yaml", "source_root: sources\n")
        self.write("config/grouping.yaml", "groups:\n- id: demo\n  members: [sources/PROG.CBL]\n")
        self.write("config/templates/section-doc.profile.yaml", "{}")
        self.write("config/templates/procedure-section-doc.template.md", "# Section\n")
        for profile in ("requirements", "functional-analysis", "technical-analysis"):
            base = f"config/templates/docs/{profile}/default"
            self.write(f"{base}/profile.yaml", yaml.safe_dump({
                "sections": [{"id": "overview", "number": "1", "title": "Overview", "required": True}],
            }))
            self.write(f"{base}/template.md", "## 1 Overview\n")
        shared = "docs/_shared/PROG.CBL"
        self.write(f"{shared}/facts.json", '{"source_kind": "cobol", "program_id": "PROG"}')
        self.write(f"{shared}/chunk-manifest.json", json.dumps({
            "sha256": hashlib.sha256((self.root / "sources" / "PROG.CBL").read_bytes()).hexdigest(),
            "chunks": [{"id": "main", "kind": "paragraph", "name": "MAIN", "start_line": 1, "end_line": 1}],
        }))
        self.write(f"{shared}/chunks/index.json", '{"chunks": [{"id": "main", "file": "main.txt"}]}')
        self.write(f"{shared}/chunks/main.txt", "       STOP RUN.\n")
        self.write(f"{shared}/facts-slices/main.json", "{}")
        self.write("docs/it/PROG.CBL/sections/main.md", "# MAIN\n\n## Sintesi\n\nTesto italiano.\n")
        for name in ("index", "complete", "requirements", "functional-analysis"):
            self.write(f"docs/it/PROG.CBL/{name}.md", "## 1 Overview\n\nTesto italiano.\n")
        for scope in ("req", "fa"):
            self.write(f"{shared}/_{scope}-sections/it/overview.md", "## 1 Overview\n\nTesto italiano.\n")
        self.write("docs/it/_groups/demo/complete.md", "# Gruppo\n\nTesto italiano.\n")
        self.write("docs/it/_groups/demo/requirements.md", "# Requisiti\n\nTesto italiano.\n")

    def write(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def run_script(self, skill: str, script: str, *args: str) -> None:
        result = subprocess.run(
            [sys.executable, str(self.root / ".github" / "skills" / skill / "scripts" / script), *args],
            cwd=self.root, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_all_bundles_support_italian_without_english_documents(self) -> None:
        cases = [
            ("section-doc-writer", "assemble-inputs.py", ["--source", "sources/PROG.CBL", "--chunk-id", "main"]),
            ("section-doc-finalizer", "assemble-inputs.py", ["--source", "sources/PROG.CBL"]),
            ("requirements-writer", "assemble-inputs.py", ["--source", "sources/PROG.CBL", "--section-id", "overview"]),
            ("requirements-finalizer", "assemble-inputs.py", ["--source", "sources/PROG.CBL"]),
            ("functional-analysis-writer", "assemble-inputs.py", ["--source", "sources/PROG.CBL", "--section-id", "overview"]),
            ("functional-analysis-finalizer", "assemble-inputs.py", ["--source", "sources/PROG.CBL"]),
            ("group-doc-finalizer", "assemble-inputs.py", ["--group-id", "demo"]),
            ("requirements-group-writer", "assemble-inputs.py", ["--group-id", "demo"]),
            ("functional-analysis-group-writer", "assemble-inputs.py", ["--group-id", "demo"]),
            ("technical-analysis-writer", "assemble-inputs.py", ["--source", "sources/PROG.CBL"]),
            ("technical-analysis-writer", "assemble-group-inputs.py", ["--group-id", "demo"]),
        ]
        for skill, script, args in cases:
            with self.subTest(skill=skill, script=script):
                out = self.root / "bundles" / f"{skill}-{script}.json"
                self.run_script(skill, script, *args, "--languages", "it", "--out", str(out))
                bundle = json.loads(out.read_text(encoding="utf-8"))
                self.assertEqual(bundle["languages"], ["it"])
                self.assertEqual(set(bundle["output_paths"]) - {"diagram"}, {"it"})
                self.assertNotIn("docs/en/", out.read_text(encoding="utf-8"))
                if "chunk_excerpt" in bundle:
                    self.assertIn("Testo italiano", bundle["chunk_excerpt"])
                if "complete_md" in bundle:
                    self.assertIn("Testo italiano", bundle["complete_md"])
                    self.assertTrue(bundle["complete_md_path"].startswith("docs/it/"))
                if skill == "section-doc-finalizer":
                    self.assertEqual(bundle["toc"][0]["summaries"], {"it": "Testo italiano."})
                if skill.endswith("group-writer") or skill == "group-doc-finalizer":
                    self.assertIn("Testo italiano", out.with_suffix(".md").read_text(encoding="utf-8"))
        self.assertFalse((self.root / "docs" / "en").exists())

    def test_staging_invalidates_bilingual_cache_then_reuses_italian_cache(self) -> None:
        for skill in ("section-doc-writer", "requirements-writer", "functional-analysis-writer"):
            with self.subTest(skill=skill):
                directory = self.root / "bundles" / skill
                args = ("--source", "sources/PROG.CBL", "--bundles-dir", str(directory))
                self.run_script(skill, "stage-bundles.py", *args, "--languages", "en,it")
                paths = list(directory.glob("*.bundle.json"))
                self.assertTrue(paths)
                for path in paths:
                    self.assertEqual(json.loads(path.read_text())["languages"], ["en", "it"])
                self.run_script(skill, "stage-bundles.py", *args, "--languages", "it")
                for path in paths:
                    self.assertEqual(json.loads(path.read_text())["languages"], ["it"])
                timestamps = {p: p.stat().st_mtime_ns for p in paths}
                self.run_script(skill, "stage-bundles.py", *args, "--languages", "it")
                self.assertEqual(timestamps, {p: p.stat().st_mtime_ns for p in paths})

    def test_group_technical_fallback_stays_in_requested_language(self) -> None:
        (self.root / "docs" / "it" / "_groups" / "demo" / "complete.md").unlink()
        out = self.root / "bundles" / "ta-fallback.json"
        self.run_script(
            "technical-analysis-writer", "assemble-group-inputs.py",
            "--group-id", "demo", "--languages", "it", "--out", str(out),
        )
        bundle = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(bundle["languages"], ["it"])
        self.assertIn("Testo italiano", bundle["complete_md"])
        self.assertTrue((self.root / "docs" / "it" / "_groups" / "demo" / "complete.md").exists())
        self.assertFalse((self.root / "docs" / "en").exists())

    @unittest.skipUnless(POWERSHELL, "PowerShell is not installed")
    def test_phase_prerequisites_use_first_requested_language(self) -> None:
        for helper in ("Resolve-PhaseInputs.ps1", "Convert-MdToDocx.ps1"):
            shutil.copy2(REPO_ROOT / "scripts" / "lib" / helper, self.root / "scripts" / "lib" / helper)
        for phase in ("E", "F", "G", "L"):
            original = next((REPO_ROOT / "scripts" / "phases").glob(f"phase-{phase}-*.ps1"))
            content = original.read_text(encoding="utf-8")
            target = self.write(f"scripts/phases/{original.name}", content)
            delegates = re.findall(r"Join-Path \$repoRoot '([^']+\.ps1)'", content)
            for delegate in delegates:
                self.write(delegate, 'param([string]$Languages)\nWrite-Host "DELEGATE:$Languages"\nexit 0\n')
            for languages, expected_exit in (("it", 0), ("it,en", 0), ("en,it", 4)):
                with self.subTest(phase=phase, languages=languages):
                    result = subprocess.run(
                        [POWERSHELL, "-NoProfile", "-File", str(target),
                         "-Files", str(self.root / "sources" / "PROG.CBL"),
                         "-Languages", languages, "-DryRun"],
                        cwd=self.root, capture_output=True, text=True, timeout=30,
                    )
                    self.assertEqual(result.returncode, expected_exit, result.stdout + result.stderr)
                    if expected_exit == 0:
                        self.assertIn(f"DELEGATE:{languages}", result.stdout)
                    else:
                        self.assertIn("missing", result.stderr)
        self.assertFalse((self.root / "docs" / "en").exists())


if __name__ == "__main__":
    unittest.main()
