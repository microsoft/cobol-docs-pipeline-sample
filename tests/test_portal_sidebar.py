from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_portal_module():
    path = REPO_ROOT / "scripts" / "portal" / "build-portal-static.py"
    spec = importlib.util.spec_from_file_location("build_portal_static_test", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PortalSidebarTests(unittest.TestCase):
    def test_active_link_uses_full_page_path(self) -> None:
        portal = load_portal_module()
        script = portal.SCRIPT_JS

        self.assertIn("target.pathname === here.pathname", script)
        self.assertIn("target.origin === here.origin", script)
        self.assertIn("a.setAttribute('aria-current', 'page')", script)
        self.assertNotIn("location.pathname.split('/').pop()", script)


if __name__ == "__main__":
    unittest.main()
