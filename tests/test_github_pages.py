"""Contract tests for the tracked pipeline user documentation portal."""
from __future__ import annotations

import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parent.parent
MKDOCS_CONFIG = REPO_ROOT / "mkdocs.yml"
PAGES_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "pages.yml"


def nav_paths(items: list) -> list[str]:
    paths: list[str] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        value = next(iter(item.values()))
        if isinstance(value, str):
            paths.append(value)
        elif isinstance(value, list):
            paths.extend(nav_paths(value))
    return paths


class GitHubPagesTests(unittest.TestCase):
    def test_every_navigation_page_exists(self) -> None:
        config = yaml.load(MKDOCS_CONFIG.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
        docs_dir = REPO_ROOT / config["docs_dir"]

        missing = [path for path in nav_paths(config["nav"]) if not (docs_dir / path).is_file()]

        self.assertEqual([], missing)

    def test_pages_workflow_builds_tracked_mkdocs_portal(self) -> None:
        workflow = PAGES_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("mkdocs build --strict --clean", workflow)
        self.assertIn("actions/configure-pages@v5", workflow)
        self.assertIn("actions/upload-pages-artifact@v3", workflow)
        self.assertIn("actions/deploy-pages@v4", workflow)
        self.assertIn("path: site", workflow)
        self.assertNotIn("build-portal-static.py", workflow)
        self.assertNotIn("docs.zip", workflow)

    def test_portal_explains_execution_portal_boundary(self) -> None:
        home = (REPO_ROOT / "site-docs" / "index.md").read_text(encoding="utf-8")

        self.assertIn("It documents the pipeline itself", home)
        self.assertIn("phase-N execution result", home)
        self.assertIn("docs/_portal/", home)


if __name__ == "__main__":
    unittest.main()