from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

import jsonschema
import yaml

import test_output_languages as language_tests
from test_output_languages import BASH, POWERSHELL, REPO_ROOT


RESOLVER = REPO_ROOT / "scripts" / "tools" / "resolve-copilot-model.py"
spec = importlib.util.spec_from_file_location("copilot_model", RESOLVER)
assert spec and spec.loader
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


class CopilotModelTests(unittest.TestCase):
    def test_precedence_and_explicit_auto(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, agent = root / "pipeline.yaml", root / "test.agent.md"
            self.assertEqual(
                resolver.resolve_model(config, agent_file=agent),
                {"model": "auto", "source": "auto", "cli_model": "auto"},
            )
            agent.write_text(
                "---\nname: Test\nmodel: 'MAI-Code-1-Flash (copilot)'\n---\nmodel: ignored\n",
                encoding="utf-8",
            )
            self.assertEqual(
                resolver.resolve_model(config, agent_file=agent),
                {"model": "MAI-Code-1-Flash (copilot)", "source": "agent", "cli_model": ""},
            )
            config.write_text("copilot:\n  default_model: claude-sonnet-4.5\n", encoding="utf-8")
            self.assertEqual(
                resolver.resolve_model(config, agent_file=agent),
                {"model": "claude-sonnet-4.5", "source": "config", "cli_model": "claude-sonnet-4.5"},
            )
            self.assertEqual(
                resolver.resolve_model(config, "auto", agent),
                {"model": "auto", "source": "cli", "cli_model": "auto"},
            )
            self.assertEqual(resolver.resolve_model(config, "gpt-5", agent)["model"], "gpt-5")

    def test_frontmatter_not_markdown_body(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, agent = root / "pipeline.yaml", root / "test.agent.md"
            config.write_text("copilot: {}\n", encoding="utf-8")
            for body in ("model: ignored\n", "---\nname: Test\n---\nmodel: ignored\n"):
                agent.write_text(body, encoding="utf-8")
                self.assertEqual(resolver.resolve_model(config, agent_file=agent)["source"], "auto")

    def test_invalid_configuration_and_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "pipeline.yaml"
            for content in ("[]", "copilot: null", "copilot: []", *(
                f"copilot:\n  default_model: {value}\n"
                for value in ("null", "true", "42", "[]", "''", "' '", "'--bad'", "'a b'")
            )):
                config.write_text(content, encoding="utf-8")
                with self.subTest(content=content), self.assertRaises(ValueError):
                    resolver.resolve_model(config, "auto")
            config.write_text("copilot: {}\n", encoding="utf-8")
            for model in ("", " ", "--bad", "a\nb", "a b"):
                with self.subTest(model=model), self.assertRaises(ValueError):
                    resolver.resolve_model(config, model)
            result = subprocess.run(
                [sys.executable, str(RESOLVER), "--config", str(config), "--model="],
                text=True, capture_output=True, timeout=30,
            )
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(result.stdout, "")

    def test_schema(self) -> None:
        schema = json.loads((REPO_ROOT / "config" / "pipeline.schema.json").read_text())
        config = yaml.safe_load((REPO_ROOT / "config" / "pipeline.yaml").read_text())
        for model in ("claude-sonnet-4.5", "auto"):
            config["copilot"] = {"default_model": model}
            jsonschema.validate(config, schema)
        for model in (None, "", " ", "--bad", "a b", True, [], 42):
            config["copilot"] = {"default_model": model}
            with self.subTest(model=model), self.assertRaises(jsonschema.ValidationError):
                jsonschema.validate(config, schema)


def environment_for(root: Path, shell: str) -> dict[str, str]:
    environment = os.environ.copy()
    environment["PATH"] = str(Path(sys.executable).parent) + os.pathsep + environment["PATH"]
    if shell == "sh":
        bin_dir = root / "bin"
        bin_dir.mkdir(exist_ok=True)
        shim = bin_dir / "python3"
        shim.write_text(
            f'#!/usr/bin/env bash\nexec {shlex.quote(Path(sys.executable).as_posix())} "$@"\n',
            encoding="utf-8", newline="\n",
        )
        shim.chmod(0o755)
        environment["PATH"] = str(bin_dir) + os.pathsep + environment["PATH"]
    return environment


class PipelineModelTests(unittest.TestCase):
    def check_runner(self, executable: str, shell: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            language_tests.PipelineLanguageTests().make_repository(root, shell, ["en"])
            for phase in "DEFGHIJKLM":
                original = next((REPO_ROOT / "scripts" / "phases").glob(f"phase-{phase}-*.{shell}"))
                target = root / "scripts" / "phases" / original.name
                probe = (
                    f'Write-Host "MODEL:{phase}:$env:COBOL_DOCS_COPILOT_MODEL"\nexit 0\n'
                    if shell == "ps1" else
                    f'#!/usr/bin/env bash\nprintf "MODEL:{phase}:%s\\n" "${{COBOL_DOCS_COPILOT_MODEL:-}}"\n'
                )
                target.write_text(probe, encoding="utf-8", newline="\n")
                target.chmod(0o755)
            environment = environment_for(root, shell)
            environment["COBOL_DOCS_COPILOT_MODEL"] = "stale-parent-value"
            for configured, options, expected in (
                ("claude-sonnet-4.5", [], "claude-sonnet-4.5"),
                ("claude-sonnet-4.5", ["-CopilotModel", "auto"], "auto"),
                (None, [], ""),
            ):
                config = {"source_root": "sources", "include": ["**/*.CBL"]}
                if configured:
                    config["copilot"] = {"default_model": configured}
                (root / "config" / "pipeline.yaml").write_text(yaml.safe_dump(config), encoding="utf-8")
                arguments = ["-From", "D", "-To", "M", "-MaxPhaseRetries", "0", *options]
                if shell == "ps1":
                    command = [
                        executable, "-NoProfile", "-Command",
                        "& ./scripts/run-pipeline.ps1 "
                        + " ".join("'" + value.replace("'", "''") + "'" if not value.startswith("-") else value for value in arguments)
                        + "; $code = $LASTEXITCODE; Write-Host \"RESTORED:$env:COBOL_DOCS_COPILOT_MODEL\"; exit $code",
                    ]
                else:
                    command = [executable, "scripts/run-pipeline.sh", *arguments]
                result = subprocess.run(
                    command,
                    cwd=root, env=environment, text=True, capture_output=True, timeout=180,
                )
                with self.subTest(shell=shell, configured=configured, options=options):
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(
                        [line for line in result.stdout.splitlines() if line.startswith("MODEL:")],
                        [f"MODEL:{phase}:{expected}" for phase in "DEFGHIJKLM"],
                    )
                    if shell == "ps1":
                        self.assertIn("RESTORED:stale-parent-value", result.stdout)
            if shell == "ps1":
                phase_d = root / "scripts" / "phases" / "phase-D-section-docs.ps1"
                phase_d.write_text("throw 'Expected model-scope test failure'\n", encoding="utf-8")
                failed = subprocess.run(
                    command, cwd=root, env=environment, text=True, capture_output=True, timeout=180,
                )
                self.assertNotEqual(failed.returncode, 0, failed.stdout + failed.stderr)
                self.assertIn("Expected model-scope test failure", failed.stdout + failed.stderr)
                self.assertIn("RESTORED:stale-parent-value", failed.stdout)

    @unittest.skipUnless(POWERSHELL, "PowerShell unavailable")
    def test_powershell_runner(self) -> None:
        self.check_runner(POWERSHELL, "ps1")

    @unittest.skipUnless(BASH, "Bash unavailable")
    def test_bash_runner(self) -> None:
        self.check_runner(BASH, "sh")


@unittest.skipUnless(BASH, "Bash unavailable")
class NativeModelDispatchTests(unittest.TestCase):
    def test_cli_arguments_and_model_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in (
                "scripts/lib/native-common.sh", "scripts/lib/native-copilot-dispatch.sh",
                "scripts/tools/resolve-copilot-model.py", "scripts/lib/read_groups.py",
            ):
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text((REPO_ROOT / relative).read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
            (root / ".github" / "skills").mkdir(parents=True)
            agents = root / ".github" / "agents"
            agents.mkdir()
            agent = agents / "test.agent.md"
            (root / "config").mkdir()
            config = root / "config" / "pipeline.yaml"
            (root / "config" / "grouping.yaml").write_text(
                "groups:\n  - id: daily\n    members: []\n", encoding="utf-8",
            )
            for parent in ("PROG.CBL", "_groups/daily/_doc-bundles"):
                bundle = root / "docs" / "_shared" / parent / "_finalize.bundle.json"
                bundle.parent.mkdir(parents=True)
                bundle.write_text("{}", encoding="utf-8")
            environment = environment_for(root, "sh")
            probe = root / "bin" / "fake-copilot"
            argv_file = root / "argv.json"
            probe.write_text(
                "#!/usr/bin/env bash\n"
                "python3 - \"$@\" <<'PY'\n"
                "import json, os, pathlib, sys\n"
                "pathlib.Path(os.environ['ARGV_FILE']).write_text(json.dumps(sys.argv[1:]), encoding='utf-8')\n"
                "PY\n",
                encoding="utf-8", newline="\n",
            )
            probe.chmod(0o755)
            environment["ARGV_FILE"] = str(argv_file)
            scenarios = (
                ("finalize", "claude-sonnet-4.5", "agent-choice", None, "claude-sonnet-4.5"),
                ("group-doc-finalize", "claude-sonnet-4.5", "agent-choice", "cli-choice", "cli-choice"),
                ("finalize", None, "agent-choice", None, None),
                ("finalize", None, None, None, "auto"),
                ("finalize", "claude-sonnet-4.5", "agent-choice", "auto", "auto"),
            )
            for mode, configured, frontmatter, override, expected_cli in scenarios:
                with self.subTest(mode=mode, configured=configured, override=override):
                    config.write_text(yaml.safe_dump(
                        {"copilot": {"default_model": configured}} if configured else {}
                    ), encoding="utf-8")
                    agent.write_text(
                        "---\n" + yaml.safe_dump({"model": frontmatter} if frontmatter else {"name": "Test"}) + "---\n",
                        encoding="utf-8",
                    )
                    environment.pop("COBOL_DOCS_COPILOT_MODEL", None)
                    if override:
                        environment["COBOL_DOCS_COPILOT_MODEL"] = override
                    result = subprocess.run(
                        [BASH, "scripts/lib/native-copilot-dispatch.sh", mode,
                         "-Files", "PROG.CBL", "-Agent", "test", "-CopilotCli", "fake-copilot",
                         "-Throttle", "1", "-MaxRetries", "0"],
                        cwd=root, env=environment, capture_output=True, text=True, timeout=180,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    argv = json.loads(argv_file.read_text(encoding="utf-8"))
                    self.assertEqual(argv[argv.index("--agent") + 1], "test")
                    if expected_cli:
                        self.assertEqual(argv.count("--model"), 1)
                        self.assertEqual(argv[argv.index("--model") + 1], expected_cli)
                    else:
                        self.assertNotIn("--model", argv)
                    selected = expected_cli or frontmatter
                    plan = json.loads((root / "logs" / f"{mode}_plan.json").read_text())
                    self.assertEqual(plan["model"], selected)
                    journal = (root / "logs" / f"{mode}_state.jsonl").read_text().splitlines()
                    self.assertEqual(json.loads(journal[-1])["model"], selected)
