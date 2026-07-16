"""Tests for the pipeline DAG integrity checker."""

from __future__ import annotations

import contextlib
import io
import importlib.util
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
CHECKER_PATH = REPO_ROOT / "scripts" / "validation" / "check-dag-integrity.py"


def load_checker():
    spec = importlib.util.spec_from_file_location("check_dag_integrity", CHECKER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load DAG checker from {CHECKER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


checker = load_checker()


class DagIntegrityTests(unittest.TestCase):
    def test_accepts_acyclic_graph(self) -> None:
        phases = [
            {"id": "A", "depends_on": []},
            {"id": "B", "depends_on": ["A"]},
        ]

        self.assertEqual([], checker.check_references(phases))
        self.assertIsNone(checker.find_cycle(phases))

    def test_reports_dangling_and_self_references(self) -> None:
        phases = [
            {"id": "A", "depends_on": ["A"]},
            {"id": "B", "depends_on": ["missing"]},
        ]

        self.assertEqual(
            [
                "phase A: depends on itself",
                "phase B: depends_on 'missing' which is not a declared phase id",
            ],
            checker.check_references(phases),
        )

    def test_reports_duplicate_phase_ids(self) -> None:
        phases = [
            {"id": "A", "depends_on": []},
            {"id": "A", "depends_on": []},
        ]

        self.assertEqual(["duplicate phase id: A"], checker.check_phase_ids(phases))

    def test_reports_cycle_path(self) -> None:
        phases = [
            {"id": "A", "depends_on": ["C"]},
            {"id": "B", "depends_on": ["A"]},
            {"id": "C", "depends_on": ["B"]},
        ]

        self.assertEqual(["A", "C", "B", "A"], checker.find_cycle(phases))

    def test_main_rejects_non_mapping_yaml(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            dag_path = Path(temp_dir) / "pipeline-dag.yaml"
            dag_path.write_text("- not-a-mapping\n", encoding="utf-8")

            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                exit_code = checker.main(["--dag", str(dag_path)])

        self.assertEqual(1, exit_code)
        self.assertIn("must contain a YAML mapping", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()