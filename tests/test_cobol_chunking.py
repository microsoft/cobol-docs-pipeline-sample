from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CHUNK_SCRIPT = REPO_ROOT / ".github" / "skills" / "cobol-chunking" / "scripts" / "chunk.py"
SPEC = importlib.util.spec_from_file_location("cobol_chunk", CHUNK_SCRIPT)
assert SPEC and SPEC.loader
COBOL_CHUNK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COBOL_CHUNK)


class CobolChunkingTests(unittest.TestCase):
    def test_encoding_detection_prefers_cp1252_for_windows_characters(self) -> None:
        self.assertEqual(COBOL_CHUNK.detect_encoding(b'VALUE "\x80".'), "cp1252")
        self.assertEqual(COBOL_CHUNK.detect_encoding(b'VALUE "\x81".'), "latin-1")

    def test_cbl_with_fixed_format_records_is_detected_as_copybook(self) -> None:
        lines = [
            "      * DECLARE SALDI",
            "       01 V-SOCIETA PIC X(4).",
            "040624*01 V-OLD-AMOUNT PIC S9(15)V99 COMP-3.",
            "040624 01 V-AMOUNT PIC S9(15)V999 COMP-3.",
        ]

        kind = COBOL_CHUNK.detect_kind(lines, "auto", ".cbl")
        chunks = COBOL_CHUNK.chunk_copybook(lines, "Copy/p2dcsalv.cbl")

        self.assertEqual(kind, "copybook")
        self.assertEqual(
            [chunk["name"] for chunk in chunks],
            ["V-SOCIETA", "V-AMOUNT"],
        )

    def test_cbl_with_identification_division_remains_cobol(self) -> None:
        lines = [
            "       IDENTIFICATION DIVISION.",
            "       PROGRAM-ID. EXAMPLE.",
            "       DATA DIVISION.",
            "       01 EXAMPLE-RECORD PIC X.",
        ]

        self.assertEqual(COBOL_CHUNK.detect_kind(lines, "auto", ".cbl"), "cobol")

    def test_copybook_fragment_uses_its_minimum_data_level(self) -> None:
        lines = [
            "             05 I0901.",
            "                10 I0901-CODE PIC X(4).",
            "             05 O0901.",
        ]

        kind = COBOL_CHUNK.detect_kind(lines, "auto", ".cbl")
        chunks = COBOL_CHUNK.chunk_copybook(lines, "Copy/p20901.cbl")

        self.assertEqual(kind, "copybook")
        self.assertEqual([chunk["name"] for chunk in chunks], ["I0901", "O0901"])

    def test_procedural_copybook_falls_back_to_whole_file_chunk(self) -> None:
        lines = [
            "           IF O-COBBASE = NULL",
            "               SET O-COBBASE TO NEW COBBASE",
            "           END-IF",
        ]

        kind = COBOL_CHUNK.detect_kind(lines, "auto", ".cbl")
        chunks = COBOL_CHUNK.chunk_copybook(lines, "Copy/P2FJPROC.cbl")

        self.assertEqual(kind, "copybook")
        self.assertEqual(len(chunks), 1)
        self.assertEqual(chunks[0]["start_line"], 1)
        self.assertEqual(chunks[0]["end_line"], 3)


if __name__ == "__main__":
    unittest.main()