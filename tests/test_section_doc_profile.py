from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SectionDocProfileTests(unittest.TestCase):
    def test_bundle_assembler_and_reviewer_share_existing_profile(self) -> None:
        assembler = load_module(
            "section_doc_assembler",
            REPO_ROOT
            / ".github"
            / "skills"
            / "section-doc-writer"
            / "scripts"
            / "assemble-inputs.py",
        )
        reviewer = load_module(
            "section_doc_reviewer",
            REPO_ROOT
            / ".github"
            / "skills"
            / "qa-reviewer"
            / "scripts"
            / "check-section-doc.py",
        )

        self.assertEqual(assembler.DEFAULT_PROFILE, reviewer.DEFAULT_PROFILE)
        self.assertTrue(assembler.DEFAULT_PROFILE.is_file())

        profile = yaml.safe_load(assembler.DEFAULT_PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(profile["min_purpose_sentences"], 4)
        self.assertEqual(profile["min_purpose_words"], 80)
        self.assertTrue(profile["require_citations"])


if __name__ == "__main__":
    unittest.main()