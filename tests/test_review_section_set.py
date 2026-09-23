from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
QA_SCRIPTS = Path(".github") / "skills" / "qa-reviewer" / "scripts"


class ReviewSectionSetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="qa-section-set-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        for relative in (
            QA_SCRIPTS / "review-section-set.py",
            QA_SCRIPTS / "check-section-doc.py",
            Path("scripts") / "tools" / "resolve-output-languages.py",
        ):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO_ROOT / relative, target)
        self.config = self.root / "config" / "pipeline.yaml"
        self.profile = self.root / "config" / "templates" / "section-doc.profile.yaml"
        self.profile.parent.mkdir(parents=True)
        self.profile.write_text(
            "min_total_words: 0\nmin_purpose_sentences: 1\n"
            "min_purpose_words: 1\nrequire_citations: false\n",
            encoding="utf-8",
        )
        self.config.write_text("source_root: samples\noutput:\n  languages: [it]\n", encoding="utf-8")
        self.source = self.root / "samples" / "DEMO.CBL"
        self.source.parent.mkdir()
        self.source.write_text("       STOP RUN.\n", encoding="utf-8")
        self.shared = self.root / "docs" / "_shared" / self.source.name
        (self.shared / "chunks").mkdir(parents=True)
        (self.shared / "_bundles").mkdir()
        self.chunks = [
            {"id": "DEMO/procedure/one", "file": "DEMO__procedure__one.txt"},
            {"id": "DEMO/procedure/two", "file": "DEMO__procedure__two.txt"},
        ]
        self.index = self.shared / "chunks" / "index.json"
        self.write_json(self.index, {"chunks": self.chunks})
        self.manifest = self.shared / "chunk-manifest.json"
        self.write_json(self.manifest, {
            "sha256": hashlib.sha256(self.source.read_bytes()).hexdigest(),
            "chunks": self.chunks,
        })
        self.text = "## Summary\nChecks customer balances.\n\n## Purpose\nEnsures consistent balances.\n"
        self.prepare_languages("it")

    @staticmethod
    def write_json(path: Path, value: object) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def section(self, language: str, position: int = 0) -> Path:
        return (
            self.root / "docs" / language / self.source.name / "sections"
            / Path(self.chunks[position]["file"]).with_suffix(".md")
        )

    def bundle(self, position: int = 0) -> Path:
        return self.shared / "_bundles" / f"{Path(self.chunks[position]['file']).stem}.bundle.json"

    def prepare_languages(self, *languages: str) -> None:
        for position, chunk in enumerate(self.chunks):
            outputs = {}
            for language in languages:
                md = self.section(language, position)
                md.parent.mkdir(parents=True, exist_ok=True)
                md.write_text(self.text, encoding="utf-8")
                outputs[language] = str(md.relative_to(self.root))
            self.write_json(self.bundle(position), {
                "source_path": str(self.source.relative_to(self.root)),
                "chunk": chunk,
                "chunk_text": self.source.read_bytes().decode("utf-8"),
                "chunk_text_sha": hashlib.sha256(self.source.read_bytes()).hexdigest(),
                "facts_slice": {"incoming_xref": []},
                "output_paths": outputs,
            })

    def run_sweep(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(self.root / QA_SCRIPTS / "review-section-set.py"),
             "--source", str(self.source), *args],
            cwd=self.root, capture_output=True, text=True, encoding="utf-8", timeout=30,
            env={**os.environ, "PYTHONIOENCODING": "utf-8"},
        )

    def assert_exit(self, result: subprocess.CompletedProcess[str], expected: int) -> None:
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def test_yaml_languages_and_normalized_cli_review_only_requested_outputs(self) -> None:
        for args in ((), ("--languages", " IT,it ")):
            with self.subTest(args=args):
                result = self.run_sweep(*args)
                self.assert_exit(result, 0)
                self.assertIn("reviewed=2 ok=2 fail=0", result.stdout)
                self.assertIn("languages=it", result.stdout)
                reviews = list((self.root / "docs" / "_reviews" / "section-doc").glob("*.json"))
                self.assertEqual(len(reviews), 2)
                self.assertEqual({json.loads(p.read_text())["language"] for p in reviews}, {"it"})

    def test_english_fallback_and_cli_override(self) -> None:
        self.prepare_languages("en", "fr-ca")
        self.config.write_text("source_root: samples\n", encoding="utf-8")
        result = self.run_sweep()
        self.assert_exit(result, 0)
        self.assertIn("languages=en", result.stdout)
        result = self.run_sweep("--languages", " FR-ca ")
        self.assert_exit(result, 0)
        self.assertIn("languages=fr-ca", result.stdout)

    def test_bilingual_review_and_unrequested_outputs(self) -> None:
        self.prepare_languages("en", "it")
        self.section("en").write_text("invalid unrequested document", encoding="utf-8")
        result = self.run_sweep()
        self.assert_exit(result, 0)
        self.assertIn("reviewed=2 ok=2 fail=0", result.stdout)
        self.assertEqual(self.section("en").read_text(), "invalid unrequested document")
        self.prepare_languages("en", "it")
        result = self.run_sweep("--languages", "IT,en,it")
        self.assert_exit(result, 0)
        self.assertIn("reviewed=4 ok=4 fail=0", result.stdout)
        self.assertIn("languages=it,en", result.stdout)
        reviews = list((self.root / "docs" / "_reviews" / "section-doc").glob("*.json"))
        self.assertEqual(len(reviews), 4)

    def test_invalid_cli_languages_fail_without_review(self) -> None:
        for value in ("", " , ", "en,,it", "../it", "english", "en/it"):
            with self.subTest(value=value):
                result = self.run_sweep("--languages", value)
                self.assert_exit(result, 2)
                self.assertIn("error:", result.stderr)
        self.assertFalse((self.root / "docs" / "_reviews").exists())

    def test_invalid_config_fails_even_with_cli_override(self) -> None:
        for config in (
            [], {"output": None}, {"output": {"languages": []}},
            {"output": {"languages": "it"}}, {"output": {"languages": [None]}},
            {"source_root": []},
        ):
            with self.subTest(config=config):
                self.config.write_text(yaml.safe_dump(config), encoding="utf-8")
                result = self.run_sweep("--languages", "it")
                self.assert_exit(result, 2)
                self.assertIn("error:", result.stderr)

    def test_missing_language_directory_blocks_review(self) -> None:
        result = self.run_sweep("--languages", "it,en")
        self.assert_exit(result, 4)
        self.assertIn("en", result.stderr)
        self.assertFalse((self.root / "docs" / "_reviews").exists())

    def test_missing_one_or_all_indexed_documents_blocks_review(self) -> None:
        for position in range(2):
            self.section("it", position).unlink()
            result = self.run_sweep()
            self.assert_exit(result, 4)
            self.assertIn("missing section markdown", result.stderr)
        self.assertFalse((self.root / "docs" / "_reviews").exists())

    def test_orphan_document_is_not_silently_ignored(self) -> None:
        orphan = self.section("it").parent / "orphan.md"
        orphan.write_text("unreviewed", encoding="utf-8")
        result = self.run_sweep()
        self.assert_exit(result, 4)
        self.assertIn("orphan.md", result.stderr)
        self.assertFalse((self.root / "docs" / "_reviews").exists())

    def test_empty_malformed_and_ambiguous_indexes_fail_explicitly(self) -> None:
        for index in (
            {}, [], {"chunks": []}, {"chunks": [{}]}, {"chunks": [None]},
            {"chunks": [self.chunks[0], self.chunks[0]]},
            {"chunks": [self.chunks[0], {**self.chunks[1], "file": self.chunks[0]["file"]}]},
        ):
            with self.subTest(index=index):
                self.write_json(self.index, index)
                result = self.run_sweep()
                self.assert_exit(result, 4)
                self.assertIn("ERROR:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_missing_bundle_is_required(self) -> None:
        self.bundle().unlink()
        result = self.run_sweep()
        self.assert_exit(result, 4)
        self.assertIn(".bundle.json", result.stderr)

    def test_bundle_incoming_references_are_enforced(self) -> None:
        bundle = json.loads(self.bundle().read_text(encoding="utf-8"))
        bundle["facts_slice"]["incoming_xref"] = [{"from": "CALLER", "to": "DEMO"}]
        self.write_json(self.bundle(), bundle)
        result = self.run_sweep()
        self.assert_exit(result, 1)
        self.assertIn("XREF_IN_MISSING_BLOCK", result.stdout)
        self.assertIn("reviewed=2 ok=1 fail=1", result.stdout)
        review_path = (
            self.root / "docs" / "_reviews" / "section-doc"
            / "DEMO.CBL__DEMO__procedure__one__it.json"
        )
        self.assertFalse(json.loads(review_path.read_text())["ok"])

    def test_bundle_must_match_expected_source_chunk_and_output(self) -> None:
        original = json.loads(self.bundle().read_text(encoding="utf-8"))
        for replacement in (
            {"source_path": "samples/OTHER.CBL"},
            {"chunk": {"id": "wrong"}},
            {"facts_slice": None},
            {"output_paths": {"it": str(self.section("it", 1).relative_to(self.root))}},
            {"output_paths": {}},
        ):
            with self.subTest(replacement=replacement):
                self.write_json(self.bundle(), {**original, **replacement})
                result = self.run_sweep()
                self.assert_exit(result, 4)
                self.assertIn("ERROR:", result.stderr)

    def test_source_and_bundle_staleness_remain_blocking(self) -> None:
        original = self.source.read_bytes()
        self.source.write_bytes(original + b"changed")
        result = self.run_sweep()
        self.assert_exit(result, 5)
        self.assertIn("STALE:", result.stderr)
        self.source.write_bytes(original)
        bundle = json.loads(self.bundle().read_text(encoding="utf-8"))
        bundle["chunk_text_sha"] = "0" * 64
        self.write_json(self.bundle(), bundle)
        result = self.run_sweep()
        self.assert_exit(result, 5)
        self.assertIn("STALE:", result.stderr)
        self.assertIn("chunk_text_sha", result.stderr)

    def test_missing_and_invalid_prerequisites_have_actionable_errors(self) -> None:
        for path in (self.source, self.manifest, self.index, self.bundle()):
            original = path.read_bytes()
            path.unlink()
            result = self.run_sweep()
            self.assert_exit(result, 4)
            self.assertIn(path.name, result.stderr)
            path.write_bytes(original)
        for path in (self.manifest, self.index, self.bundle()):
            original = path.read_bytes()
            path.write_text("{broken", encoding="utf-8")
            result = self.run_sweep()
            self.assert_exit(result, 4)
            self.assertIn(path.name, result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            path.write_bytes(original)

    def test_child_diagnostics_and_exit_codes_do_not_use_old_sidecars(self) -> None:
        review_path = (
            self.root / "docs" / "_reviews" / "section-doc"
            / "DEMO.CBL__DEMO__procedure__one__it.json"
        )
        self.write_json(review_path, {
            "ok": False,
            "findings": [{"severity": "error", "code": "OLD_FINDING", "message": "obsolete"}],
        })
        checker = self.root / QA_SCRIPTS / "check-section-doc.py"
        for child_code, expected in ((1, 1), (4, 4), (5, 5), (7, 1)):
            with self.subTest(child_code=child_code):
                checker.write_text(
                    "import sys\n"
                    "print('current checker output')\n"
                    "print('current checker error: \\u00e8', file=sys.stderr)\n"
                    f"sys.exit({child_code})\n",
                    encoding="utf-8",
                )
                result = self.run_sweep()
                self.assert_exit(result, expected)
                self.assertIn("current checker output", result.stdout)
                self.assertIn("current checker error: \u00e8", result.stderr)
                self.assertNotIn("OLD_FINDING", result.stdout + result.stderr)
                self.assertIn(f"exit={child_code}", result.stdout + result.stderr)

    def test_mixed_child_failures_prioritize_missing_then_stale(self) -> None:
        self.prepare_languages("en", "it", "fr")
        checker = self.root / QA_SCRIPTS / "check-section-doc.py"
        checker.write_text(
            "import sys\n"
            "lang = sys.argv[sys.argv.index('--language') + 1]\n"
            "sys.exit({'en': 1, 'it': 4, 'fr': 5}[lang])\n",
            encoding="utf-8",
        )
        self.assert_exit(self.run_sweep("--languages", "en,it,fr"), 4)
        self.assert_exit(self.run_sweep("--languages", "en,fr"), 5)

    def test_explicit_profile_is_forwarded(self) -> None:
        override = self.root / "strict-profile.yaml"
        override.write_text("min_purpose_words: 100\n", encoding="utf-8")
        result = self.run_sweep("--profile", str(override))
        self.assert_exit(result, 1)
        self.assertIn("PURPOSE_TOO_SHORT_WORDS", result.stdout)


if __name__ == "__main__":
    unittest.main()
