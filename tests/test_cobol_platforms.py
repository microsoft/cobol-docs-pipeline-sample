"""Regression tests for mainframe and IBM i COBOL ingestion."""

from __future__ import annotations

import json
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
CHUNKER = REPO_ROOT / "scripts" / "tools" / "chunk.py"
FACTS_EXTRACTOR = REPO_ROOT / "scripts" / "tools" / "extract-facts.py"
XREF_EXTRACTOR = REPO_ROOT / "scripts" / "tools" / "xref-incoming-pass.py"
DIAGRAM_ASSEMBLER = (
    REPO_ROOT / ".github" / "skills" / "diagram-renderer" / "scripts" / "assemble-inputs.py"
)
FINALIZER_ASSEMBLER = (
    REPO_ROOT / ".github" / "skills" / "section-doc-finalizer" / "scripts" / "assemble-inputs.py"
)
MAINFRAME_FIXTURE = (
    REPO_ROOT / ".github" / "skills" / "cobol-chunking" / "samples" / "DEMO100.sample.cbl"
)
IBMI_FIXTURE = REPO_ROOT / "tests" / "fixtures" / "ibmi" / "ORDENTRY.SQLCBLLE"
IBMI_CL_FIXTURE = REPO_ROOT / "tests" / "fixtures" / "ibmi" / "ORDJOB.CLLE"
AS400_SAMPLE = REPO_ROOT / "repos" / "sample-as400"


class CobolPlatformTests(unittest.TestCase):
    @staticmethod
    def load_script(name: str, path: Path):
        spec = importlib.util.spec_from_file_location(name, path)
        if spec is None or spec.loader is None:
            raise AssertionError(f"Unable to load {path}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def run_pipeline(
        self,
        source: Path,
        platform_hint: str | None = None,
        source_root: Path | None = None,
    ) -> tuple[dict, dict]:
        with tempfile.TemporaryDirectory() as temp_dir:
            manifest_path = Path(temp_dir) / "chunk-manifest.json"
            facts_path = Path(temp_dir) / "facts.json"
            chunk_command = [
                sys.executable,
                str(CHUNKER),
                "--source",
                str(source),
                "--output",
                str(manifest_path),
            ]
            if platform_hint:
                chunk_command.extend(["--platform-hint", platform_hint])
            if source_root:
                chunk_command.extend(["--source-root", str(source_root)])
            subprocess.run(
                chunk_command,
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                [
                    sys.executable,
                    str(FACTS_EXTRACTOR),
                    "--source",
                    str(source),
                    "--manifest",
                    str(manifest_path),
                    "--output",
                    str(facts_path),
                ],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            return (
                json.loads(manifest_path.read_text(encoding="utf-8")),
                json.loads(facts_path.read_text(encoding="utf-8")),
            )

    def test_mainframe_cobol_remains_mainframe(self) -> None:
        manifest, facts = self.run_pipeline(MAINFRAME_FIXTURE)

        self.assertEqual("cobol", manifest["source_kind"])
        self.assertEqual("mainframe", manifest["source_platform"])
        self.assertEqual("mainframe", facts["source_platform"])

    def test_sqlcblle_is_detected_as_ibmi_cobol(self) -> None:
        manifest, facts = self.run_pipeline(IBMI_FIXTURE)

        self.assertEqual("cobol", manifest["source_kind"])
        self.assertEqual("ibmi", manifest["source_platform"])
        self.assertEqual("ibmi", facts["source_platform"])
        self.assertEqual("ORDENTRY", facts["program_id"])
        self.assertTrue(facts["exec_sql"])
        self.assertTrue(any(item["assign_to"] == "DATABASE-ORDERS" for item in facts["files"]))

    def test_clle_is_chunked_as_ibmi_cl(self) -> None:
        manifest, facts = self.run_pipeline(IBMI_CL_FIXTURE)

        self.assertEqual("cl", manifest["source_kind"])
        self.assertEqual("ibmi", manifest["source_platform"])
        self.assertEqual("cl-program", manifest["chunks"][0]["kind"])
        commands = [chunk["name"] for chunk in manifest["chunks"] if chunk["kind"] == "cl-command"]
        self.assertIn("CALL", commands)
        self.assertIn("OVRDBF", commands)
        self.assertIn("MONMSG", commands)
        self.assertEqual("ORDJOB", facts["program_id"])
        self.assertTrue(any(call["kind"] == "cl-call" for call in facts["calls"]))
        self.assertTrue(any(call["target"] == "DEMOLIB/ORDENTRY" for call in facts["calls"]))
        self.assertTrue(any(item["command"] == "OVRDBF" for item in facts["cl_commands"]))

    def test_as400_sample_exposes_sql_and_cross_program_calls(self) -> None:
        cl_manifest, cl_facts = self.run_pipeline(AS400_SAMPLE / "QCLSRC" / "ORDRJOB.CLLE")
        update_manifest, update_facts = self.run_pipeline(
            AS400_SAMPLE / "QCBLSRC" / "ORDRUPD.SQLCBLLE"
        )

        self.assertEqual("ibmi", cl_manifest["source_platform"])
        self.assertEqual("cl", cl_manifest["source_kind"])
        self.assertEqual("ibmi", update_manifest["source_platform"])
        self.assertTrue(any(chunk["kind"] == "exec-sql" for chunk in update_manifest["chunks"]))
        self.assertTrue(any(call["target"] == "DEMOLIB/ORDRUPD" for call in cl_facts["calls"]))
        self.assertTrue(any(call["target"] == "ORDRAUD" for call in update_facts["calls"]))

    def test_as400_sample_manifest_and_copybook_are_ibmi(self) -> None:
        entries = json.loads((AS400_SAMPLE / "sources.json").read_text(encoding="utf-8"))

        self.assertEqual(5, len(entries))
        self.assertTrue(all(entry["platform"] == "ibmi" for entry in entries))
        self.assertTrue(all(entry["sourceRoot"] == "repos/sample-as400" for entry in entries))
        self.assertTrue(all((REPO_ROOT / entry["path"]).is_file() for entry in entries))

        manifest, facts = self.run_pipeline(
            AS400_SAMPLE / "QCPYSRC" / "ORDAUDR.CPY",
            platform_hint="ibmi",
            source_root=AS400_SAMPLE,
        )

        self.assertEqual("ibmi", manifest["source_platform"])
        self.assertEqual("copybook", facts["source_kind"])
        self.assertTrue(any(chunk["kind"] == "copybook-record" for chunk in manifest["chunks"]))

    def test_ebcdic_mainframe_source_uses_supported_codec(self) -> None:
        source_text = MAINFRAME_FIXTURE.read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "DEMO100.CBL"
            source.write_bytes(source_text.encode("cp037"))
            manifest, facts = self.run_pipeline(source)

        self.assertEqual("cp037", manifest["encoding_detected"])
        self.assertEqual("mainframe", manifest["source_platform"])
        self.assertEqual("DEMO100", facts["program_id"])

    def test_cl_library_qualified_call_resolves_in_xref(self) -> None:
        module = self.load_script("xref_incoming_pass", XREF_EXTRACTOR)
        files = [
            (
                Path("ORDJOB.CLLE/facts.json"),
                {
                    "source_path": "ibmi/ORDJOB.CLLE",
                    "source_kind": "cl",
                    "program_id": "ORDJOB",
                    "calls": [{"target": "DEMOLIB/ORDENTRY", "kind": "cl-call", "line": 4}],
                },
            ),
            (
                Path("ORDENTRY.SQLCBLLE/facts.json"),
                {
                    "source_path": "ibmi/ORDENTRY.SQLCBLLE",
                    "source_kind": "cobol",
                    "program_id": "ORDENTRY",
                },
            ),
        ]

        edges = module.build_xref(files)

        self.assertEqual("cl-call", edges["ibmi/ORDENTRY.SQLCBLLE"][0]["via"])
        self.assertEqual("ibmi/ORDJOB.CLLE", edges["ibmi/ORDENTRY.SQLCBLLE"][0]["caller_source"])

    def test_cl_commands_create_command_flow_diagram_entry(self) -> None:
        module = self.load_script("diagram_assembler", DIAGRAM_ASSEMBLER)
        facts = {
            "cl_commands": [
                {
                    "chunk_id": "ORDJOB/CALL-0001",
                    "command": "CALL",
                    "text": "CALL PGM(DEMOLIB/ORDENTRY)",
                    "parameters": {"PGM": "DEMOLIB/ORDENTRY"},
                    "start_line": 1,
                    "end_line": 1,
                }
            ]
        }

        diagrams = module.build_diagram_entries(facts, IBMI_CL_FIXTURE)

        self.assertEqual("cl-command-flow", diagrams[0]["kind"])
        self.assertTrue(diagrams[0]["output_path"].endswith("cl-command-flow.mmd"))

    def test_finalizer_normalizes_internal_and_inter_program_calls(self) -> None:
        module = self.load_script("section_finalizer_assembler", FINALIZER_ASSEMBLER)
        facts = {
            "program_id": "DEMO100",
            "performs": [{"from": "MAIN", "to": "VALIDATE", "thru_to": None, "line": 10}],
            "go_tos": [{"from": "VALIDATE", "to": ["OK", "ERROR"], "line": 20}],
            "calls": [{"from": "MAIN", "target": "DEMO200", "kind": "call", "line": 30}],
            "incoming_xref": [
                {"caller_source": "BATCH.JCL", "via": "jcl-step", "line": 5},
                {"caller_source": "COMMON.CPY", "via": "copy", "line": 1},
            ],
        }

        internal = module.build_internal_calls(facts)
        between = module.build_inter_program_calls(facts)

        self.assertEqual(["VALIDATE", "OK", "ERROR"], [row["target"] for row in internal])
        self.assertEqual(["inbound", "outbound"], [row["direction"] for row in between])
        self.assertNotIn("COMMON.CPY", [row["source"] for row in between])

    def test_calls_create_inter_program_diagram_entry(self) -> None:
        module = self.load_script("diagram_assembler_inter_program", DIAGRAM_ASSEMBLER)
        facts = {
            "program_id": "DEMO100",
            "calls": [{"target": "DEMO200", "kind": "call", "line": 30}],
            "incoming_xref": [{"caller_source": "BATCH.JCL", "via": "jcl-step", "line": 5}],
        }

        diagrams = module.build_diagram_entries(facts, MAINFRAME_FIXTURE)
        entry = next(item for item in diagrams if item["kind"] == "inter-program-call-graph")

        self.assertTrue(entry["output_path"].endswith("inter-program-call-graph.mmd"))
        self.assertEqual(2, entry["item_count"])

    def test_finalizer_predicts_phase_h_call_diagram_links(self) -> None:
        module = self.load_script("section_finalizer_diagrams", FINALIZER_ASSEMBLER)
        facts = {
            "program_id": "DEMO100",
            "performs": [{"from": "MAIN", "to": "VALIDATE", "line": 10}],
            "calls": [{"from": "MAIN", "target": "DEMO200", "kind": "call", "line": 30}],
        }

        diagrams = module.list_diagrams("NOT-YET-GENERATED.CBL", facts)

        self.assertIn("docs/_shared/NOT-YET-GENERATED.CBL/diagrams/call-graph.mmd", diagrams)
        self.assertIn(
            "docs/_shared/NOT-YET-GENERATED.CBL/diagrams/inter-program-call-graph.mmd",
            diagrams,
        )


if __name__ == "__main__":
    unittest.main()
