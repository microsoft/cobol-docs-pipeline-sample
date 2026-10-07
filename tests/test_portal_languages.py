from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_builder(filename: str):
    spec = importlib.util.spec_from_file_location(
        filename.replace("-", "_"), REPO_ROOT / "scripts" / "portal" / filename
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PortalLanguageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.portal = load_builder("build-portal-static.py")
        self.offline = load_builder("build-portal-offline.py")
        self.docs = self.root / "docs"
        self.site = self.docs / "_portal" / "site"
        self.config = self.root / "config" / "pipeline.yaml"
        self.write(self.config, "source_root: sources\noutput:\n  languages: [it]\n")
        self.write(self.root / "sources" / "PROG.CBL", "       STOP RUN.\n")
        for lang, text in (("en", "English-only narrative"), ("it", "Testo italiano")):
            self.write(self.docs / lang / "PROG.CBL" / "index.md", f"# PROG\n\n{text}")
            self.write(self.docs / lang / "PROG.CBL" / "sections" / "main.md", f"# MAIN\n\n{text}")
        self.write(self.docs / "_glossary.md", "# Glossario\n")
        self.write(self.docs / "_shared" / "PROG.CBL" / "chunk-manifest.json", json.dumps({
            "chunks": [{"id": "PROG/main", "name": "MAIN", "kind": "paragraph",
                        "start_line": 1, "end_line": 1}],
        }))
        settings = {
            "REPO_ROOT": self.root, "DOCS_ROOT": self.docs,
            "PORTAL_ROOT": self.docs / "_portal", "SITE_ROOT": self.site,
            "SHARED_ROOT": self.docs / "_shared", "SOURCE_CONFIG_PATH": self.config,
            "SHARED_GLOSSARY_MD": self.docs / "_glossary.md",
        }
        for name, value in settings.items():
            p = patch.object(self.portal, name, value)
            p.start()
            self.addCleanup(p.stop)
        for name in ("sync_central_glossary", "write_mermaid_asset"):
            p = patch.object(self.portal, name)
            p.start()
            self.addCleanup(p.stop)

    def write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def build(self, languages: str | None = None) -> tuple[str, dict]:
        args = [] if languages is None else ["--languages", languages]
        self.assertEqual(self.portal.main(args), 0)
        viewer = (self.site / "_sources" / "PROG.CBL.html").read_text(encoding="utf-8")
        match = re.search(r'id="sv-data">(.*?)</script>', viewer, re.S)
        assert match
        return viewer, json.loads(match.group(1))

    def test_italian_only_excludes_stale_english_everywhere(self) -> None:
        viewer, data = self.build()
        self.assertEqual(data["langs"], ["it"])
        self.assertEqual(set(data["bundleDocs"]), {"it"})
        self.assertEqual(set(data["chunks"][0]["docUrls"]), {"it"})
        self.assertIn("Indice", data["bundleDocs"]["it"])
        self.assertIn('<html lang="it">', viewer)
        self.assertIn(">Vai a:</label>", viewer)
        self.assertIn(">Apri pagina completa</a>", viewer)
        self.assertIn(">Pagina iniziale (Italiano)</a>", viewer)
        self.assertNotIn('href="../en/index.html"', viewer)
        self.assertFalse((self.site / "en").exists())
        self.assertTrue((self.docs / "en" / "PROG.CBL" / "index.md").is_file())
        landing = (self.site / "index.html").read_text(encoding="utf-8")
        self.assertIn("Portale della documentazione", landing)
        self.assertNotIn('href="en/index.html"', landing)
        page = (self.site / "it" / "PROG.CBL" / "index.html").read_text(encoding="utf-8")
        self.assertIn("Codice sorgente", page)
        self.assertIn("PROG.CBL.html?lang=it", page)
        self.assertNotIn('class="lang-toggle', page)
        shared = (self.site / "_shared_pages" / "_glossary.html").read_text(encoding="utf-8")
        self.assertIn('<html lang="it">', shared)
        manifest = json.loads((self.site / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["languages"], ["it"])

    def test_bilingual_override_preserves_order_and_links(self) -> None:
        viewer, data = self.build("it,en,it")
        self.assertEqual(data["langs"], ["it", "en"])
        self.assertEqual(set(data["chunks"][0]["docUrls"]), {"it", "en"})
        self.assertIn('<html lang="it">', viewer)
        self.assertIn('href="../en/index.html"', viewer)
        self.assertIn("Index", data["bundleDocs"]["en"])
        self.assertTrue((self.site / "en" / "PROG.CBL" / "index.html").is_file())

    def test_english_only_override(self) -> None:
        viewer, data = self.build("en")
        self.assertEqual(data["langs"], ["en"])
        self.assertIn('<html lang="en">', viewer)
        self.assertIn(">Jump to:</label>", viewer)
        self.assertFalse((self.site / "it").exists())

    def test_missing_selected_translation_is_not_replaced_by_english(self) -> None:
        (self.docs / "it" / "PROG.CBL" / "sections" / "main.md").unlink()
        _, data = self.build()
        self.assertEqual(data["chunks"][0]["docUrls"], {})

    def test_offline_resources_include_only_selected_narratives(self) -> None:
        source = self.docs / "it" / "PROG.CBL" / "sections" / "main.md"
        original = "# MAIN\n\n## Summary\n\nTesto italiano\n\n## Purpose\n\nScopo."
        self.write(source, original)
        _, data = self.build()
        page = self.site / "_sources" / "PROG.CBL.html"
        store = self.offline.ResourceStore(self.site)
        self.assertTrue(self.offline.patch_page(page, self.site, store))
        text = page.read_text(encoding="utf-8")
        match = re.search(r'id="__offline_store__">(.*?)</script>', text, re.S)
        assert match
        resources = json.loads(match.group(1))
        self.assertIn("_sources/PROG.CBL.txt", resources)
        self.assertIn("it/PROG.CBL/sections/main.html", resources)
        self.assertFalse(any(key.startswith("en/") for key in resources))
        self.assertIn("Testo italiano", resources["it/PROG.CBL/sections/main.html"])
        self.assertIn('<h2 id="summary">Riepilogo</h2>', resources["it/PROG.CBL/sections/main.html"])
        self.assertIn('<h2 id="purpose">Scopo</h2>', resources["it/PROG.CBL/sections/main.html"])
        self.assertEqual(source.read_text(encoding="utf-8"), original)
        self.assertEqual(data["langs"], ["it"])

    def test_heading_localization_preserves_anchors_code_and_prose(self) -> None:
        raw = """# Summary

[TOC]

## Summary

Summary is a literal in this paragraph. `Purpose`

[Purpose](#purpose)

## Purpose

### 2.1 Entry contract

## Custom heading

## `Summary`

### `EXEC SQL` statements

### File / dataset bindings (`DDNAME` ↔ `FD` / `SELECT` ↔ `DSN`)

```text
## Summary
```
"""
        engine = self.portal.markdown.Markdown(extensions=["extra", "toc"])
        localized = self.portal.render_markdown(raw, engine, "it")
        self.assertIn('<h1 id="summary">Summary</h1>', localized)
        self.assertIn('<h2 id="summary_1">Riepilogo</h2>', localized)
        self.assertIn('<a href="#summary_1">Riepilogo</a>', localized)
        self.assertIn('<h2 id="purpose">Scopo</h2>', localized)
        self.assertIn('<a href="#purpose">Scopo</a>', localized)
        self.assertIn('<h3 id="21-entry-contract">2.1 Contratto di ingresso</h3>', localized)
        self.assertIn("Summary is a literal in this paragraph. <code>Purpose</code>", localized)
        self.assertIn(">Custom heading</h2>", localized)
        self.assertIn("<code>Summary</code></h2>", localized)
        self.assertIn('<h3 id="exec-sql-statements">Istruzioni <code>EXEC SQL</code></h3>', localized)
        self.assertIn("Associazioni di file e dataset (<code>DDNAME</code> ↔ <code>FD</code> / <code>SELECT</code> ↔ <code>DSN</code>)</h3>", localized)
        self.assertIn('<a href="#exec-sql-statements">Istruzioni EXEC SQL</a>', localized)
        self.assertIn('class="language-text">## Summary', localized)
        english = self.portal.render_markdown(raw, engine, "en")
        self.assertIn('<h2 id="summary_1">Summary</h2>', english)
        self.assertIn('<a href="#purpose">Purpose</a>', english)
        self.assertNotIn("Riepilogo", english)

    def test_bilingual_pages_localize_headings_independently(self) -> None:
        for lang in ("en", "it"):
            self.write(self.docs / lang / "PROG.CBL" / "index.md", "# PROG\n\n## Summary\n\nPROG")
        self.build("it,en")
        italian = (self.site / "it" / "PROG.CBL" / "index.html").read_text(encoding="utf-8")
        english = (self.site / "en" / "PROG.CBL" / "index.html").read_text(encoding="utf-8")
        self.assertIn('<h2 id="summary">Riepilogo</h2>', italian)
        self.assertIn('<h2 id="summary">Summary</h2>', english)

    def test_author_verification_sections_are_not_published(self) -> None:
        hidden_headings = (
            "Authoring self-check",
            "Autoverifica",
            "Autoverifica authoring",
            "Autoverifica dell'autore",
            "Autoverifica dell’autore",
            "Autoverifica della stesura",
            "Autoverifica di authoring",
            "Autoverifica di redazione",
            "Verifica dell'autore",
            "Verifica dell’autore",
        )
        checks = "\n".join(
            f"### {heading}\n\nSECRET CHECK {index}\n"
            for index, heading in enumerate(hidden_headings)
        )
        source = self.docs / "it" / "PROG.CBL" / "index.md"
        original = (
            "# PROG\n\n## Summary\n\nTesto pubblicato.\n\n"
            f"{checks}\n## Verifica dell'azienda\n\nControllo applicativo.\n"
        )
        self.write(source, original)

        self.build()

        page = (self.site / "it" / "PROG.CBL" / "index.html").read_text(encoding="utf-8")
        self.assertIn("Testo pubblicato.", page)
        self.assertIn("Verifica dell'azienda", page)
        self.assertIn("Controllo applicativo.", page)
        self.assertNotIn("SECRET CHECK", page)
        for heading in hidden_headings:
            self.assertNotIn(heading, page)
        self.assertEqual(source.read_text(encoding="utf-8"), original)

    def test_author_verification_heading_inside_code_fence_is_preserved(self) -> None:
        raw = """# PROG

```markdown
### Authoring self-check
```

## Summary

Published.
"""
        filtered = self.portal.strip_hidden_sections(raw)
        self.assertIn("### Authoring self-check", filtered)
        self.assertIn("Published.", filtered)

    def test_offline_builder_forwards_override(self) -> None:
        with patch.object(self.offline.subprocess, "run") as run:
            run.return_value.returncode = 0
            self.assertEqual(self.offline.run_build(None, 0, "it"), 0)
            self.assertEqual(run.call_args.args[0][-2:], ["--languages", "it"])

    def test_skip_build_rejects_stale_languages_before_replacing_output(self) -> None:
        self.build("en")
        out = self.docs / "_portal" / "offline"
        self.write(out / "index.html", "existing offline site")
        with patch.object(self.offline, "REPO_ROOT", self.root):
            self.assertEqual(self.offline.main([
                "--skip-build", "--site", str(self.site), "--out", str(out),
            ]), 1)
        self.assertEqual((out / "index.html").read_text(encoding="utf-8"), "existing offline site")

    def test_skip_build_accepts_matching_languages(self) -> None:
        self.build()
        out = self.docs / "_portal" / "offline"
        with patch.object(self.offline, "REPO_ROOT", self.root):
            self.assertEqual(self.offline.main([
                "--skip-build", "--site", str(self.site), "--out", str(out),
            ]), 0)
        self.assertTrue((out / "_sources" / "PROG.CBL.html").is_file())
        self.assertFalse((out / "en").exists())

    def test_invalid_configuration_fails_before_replacing_site(self) -> None:
        self.write(self.config, "output:\n  languages: []\n")
        sentinel = self.site / "index.html"
        self.write(sentinel, "existing site")
        with self.assertRaises(ValueError):
            self.portal.main([])
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "existing site")


if __name__ == "__main__":
    unittest.main()
