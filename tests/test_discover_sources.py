from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "tools" / "discover-sources.py"
SPEC = importlib.util.spec_from_file_location("discover_sources", SCRIPT_PATH)
assert SPEC and SPEC.loader
DISCOVER_SOURCES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DISCOVER_SOURCES)


class DiscoverSourcesTests(unittest.TestCase):
    def test_discovers_included_files_and_applies_exclusions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "COBOL").mkdir()
            (root / "Copy").mkdir()
            (root / "COBOL" / "archive").mkdir()
            (root / "COBOL" / "nested" / "Backup").mkdir(parents=True)
            included = root / "COBOL" / "ORDER.CBL"
            included.write_text("IDENTIFICATION DIVISION.", encoding="utf-8")
            (root / "COBOL" / "archive" / "OLD.CBL").write_text("OLD", encoding="utf-8")
            (root / "COBOL" / "nested" / "Backup" / "ORDER.CBL").write_text(
                "BACKUP", encoding="utf-8"
            )
            (root / "COBOL" / "README.txt").write_text("ignored", encoding="utf-8")
            (root / "Copy" / "COPIED.CBL").write_text("COPY", encoding="utf-8")
            config_path = root / "pipeline.yaml"
            config_path.write_text(
                "source_root: .\n"
                "include:\n"
                "  - 'COBOL'\n"
                "exclude:\n"
                "  - '**/archive/**'\n"
                "  - '**/Backup/**'\n"
                "  - '**/Copy/**'\n",
                encoding="utf-8",
            )

            resolved_root, files = DISCOVER_SOURCES.discover_sources(config_path, str(root))

            self.assertEqual(resolved_root, root.resolve())
            self.assertEqual(files, [included.resolve()])

    def test_filters_explicit_candidates_using_rules_below_source_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "Current").mkdir()
            (root / "Copy").mkdir()
            included = root / "Current" / "MAIN.CBL"
            excluded = root / "Copy" / "MAIN.CBL"
            outside = root.parent / "EXTERNAL.CBL"
            included.write_text("CURRENT", encoding="utf-8")
            excluded.write_text("COPY", encoding="utf-8")
            config_path = root / "pipeline.yaml"
            config_path.write_text(
                "source_root: .\n"
                "include:\n"
                "  - '**/*.cbl'\n"
                "exclude:\n"
                "  - '**/Copy/**'\n",
                encoding="utf-8",
            )

            files = DISCOVER_SOURCES.filter_candidates(
                config_path, str(root), [str(included), str(excluded), str(outside)]
            )

            self.assertEqual(files, sorted([included.resolve(), outside.resolve()]))

    @unittest.skipUnless(os.name == "nt", "MSYS drive paths are Windows-specific")
    def test_filters_msys_style_candidate_paths_on_windows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "Current").mkdir()
            (root / "Copy").mkdir()
            included = root / "Current" / "MAIN.CBL"
            excluded = root / "Copy" / "COPIED.CBL"
            included.write_text("CURRENT", encoding="utf-8")
            excluded.write_text("COPY", encoding="utf-8")
            config_path = root / "pipeline.yaml"
            config_path.write_text(
                "source_root: .\n"
                "include:\n"
                "  - '**/*.cbl'\n"
                "exclude:\n"
                "  - '**/Copy/**'\n",
                encoding="utf-8",
            )
            as_msys = lambda path: f"/{path.drive[0].lower()}{path.as_posix()[2:]}"

            files = DISCOVER_SOURCES.filter_candidates(
                config_path,
                str(root),
                [as_msys(included), as_msys(excluded)],
            )

            self.assertEqual(files, [included.resolve()])

    def test_rejects_duplicate_basenames(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "Current").mkdir()
            (root / "Backup").mkdir()
            (root / "Current" / "MAIN.CBL").write_text("       01 CURRENT PIC X.", encoding="utf-8")
            (root / "Backup" / "main.cbl").write_text("       01 BACKUP PIC X.", encoding="utf-8")
            config_path = root / "pipeline.yaml"
            config_path.write_text(
                "source_root: .\n"
                "include:\n"
                "  - '**/*.cbl'\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "duplicate source basenames"):
                DISCOVER_SOURCES.discover_sources(config_path, str(root))


if __name__ == "__main__":
    unittest.main()