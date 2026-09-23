from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class FunctionalAnalysisProfileTests(unittest.TestCase):
    def test_default_profile_is_complete_and_resolvable(self) -> None:
        resolver = load_module(
            "fa_profile_resolver_test",
            REPO_ROOT / "scripts" / "lib" / "fa_profile_resolver.py",
        )

        profile_dir = resolver.FA_ROOT / "default"
        profile_path = profile_dir / "profile.yaml"
        template_path = profile_dir / "template.md"

        self.assertTrue(profile_path.is_file())
        self.assertTrue(template_path.is_file())

        profile = yaml.safe_load(profile_path.read_text(encoding="utf-8"))
        sections = resolver.flatten_sections(profile)
        section_ids = {section["id"] for section in sections}

        self.assertEqual(profile["document_type"], "functional-analysis")
        self.assertTrue(profile["require_citations"])
        self.assertIn("header", section_ids)
        self.assertIn("scopo-ambito", section_ids)
        self.assertIn("processi-business", section_ids)
        self.assertTrue(
            all(section.get("title") for section in sections),
            "Every functional-analysis section must have a title.",
        )

        resolution = resolver.resolve(Path("PROGRAM.COB"), {})
        self.assertEqual(resolution.profile, "default")
        self.assertEqual(resolution.profile_dir, profile_dir)


if __name__ == "__main__":
    unittest.main()
