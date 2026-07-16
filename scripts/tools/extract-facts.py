#!/usr/bin/env python3
"""Deterministic COBOL/CL/JCL/copybook/BMS/PROC facts extractor.

Consumes a phase-A chunk-manifest.json + its source file and emits a
facts.json validated against schemas/outputs.schema.json.

Usage:
    py -3 extract-facts.py --source <rel-path> \
        [--manifest <chunk-manifest.json>] \
        [--output <facts.json>] \
        [--source-root <root>]
    py -3 extract-facts.py --xref-pass         # workspace-scope pass
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml

SCRIPT_ROOT = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_ROOT.parent.parent
SCHEMA_PATH = SCRIPT_ROOT.parent / "schemas" / "facts.schema.json"
DEFAULT_DOC_ROOT = REPO_ROOT / "docs" / "_shared"
SOURCES_YAML = REPO_ROOT / "config" / "sources.yaml"


# ---------- helpers ------------------------------------------------------

def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def load_sources_yaml() -> dict:
    if not SOURCES_YAML.exists():
        return {}
    with SOURCES_YAML.open("rb") as f:
        return yaml.safe_load(f) or {}


def resolve_source(source: str, source_root: str | None) -> Path:
    p = Path(source)
    if p.is_absolute() and p.exists():
        return p
    cand = (REPO_ROOT / source).resolve()
    if cand.exists():
        return cand
    root = source_root or load_sources_yaml().get("source_root")
    if root:
        cand = (REPO_ROOT / root / source).resolve()
        if cand.exists():
            return cand
    raise FileNotFoundError(f"source not found: {source}")


def default_doc_dir(source_path: Path) -> Path:
    return DEFAULT_DOC_ROOT / source_path.name


def read_text(path: Path, encoding_hint: str | None = None) -> tuple[str, str]:
    raw = path.read_bytes()
    enc = encoding_hint or "utf-8"
    try:
        return raw.decode(enc), enc
    except (LookupError, UnicodeDecodeError):
        for fallback in ("utf-8", "cp1252", "latin-1"):
            try:
                return raw.decode(fallback), fallback
            except UnicodeDecodeError:
                continue
        return raw.decode("latin-1", errors="replace"), "latin-1"


# ---------- COBOL area --------------------------------------------------

COMMENT_INDICATORS = set("*/Dd$")


def is_cobol_comment(line: str) -> bool:
    return len(line) >= 7 and line[6] in COMMENT_INDICATORS


def is_cobol_continuation(line: str) -> bool:
    return len(line) >= 7 and line[6] == "-"


def cobol_body(line: str) -> str:
    """Return columns 8-72 (Area A/B) for a fixed-format COBOL line."""
    if len(line) < 7:
        return ""
    return (line[7:72] if len(line) > 7 else "").rstrip()


def fold_continuations(lines: list[str]) -> list[tuple[int, str]]:
    """Return [(orig_line_no, logical_text)] with comments dropped and
    continuation lines folded into the preceding non-comment line. Each
    tuple's line_no refers to the *first* line of the logical statement.
    """
    out: list[list] = []
    for i, raw in enumerate(lines, start=1):
        if is_cobol_comment(raw):
            continue
        body = cobol_body(raw)
        if is_cobol_continuation(raw) and out:
            # strip leading whitespace + a single leading quote if any
            body = body.lstrip()
            if body.startswith(("'", '"')):
                body = body[1:]
            out[-1][1] += body
            continue
        out.append([i, body])
    return [(ln, txt) for ln, txt in out]


# ---------- chunk lookup ------------------------------------------------

def build_chunk_index(manifest: dict) -> dict:
    by_id = {c["id"]: c for c in manifest.get("chunks", [])}
    # paragraph/section lookup: which chunk_id covers a given line?
    procedure_chunks = [
        c for c in manifest.get("chunks", [])
        if c.get("kind") in ("paragraph", "section")
    ]
    procedure_chunks.sort(key=lambda c: (c["start_line"], -(c["end_line"] - c["start_line"])))
    exec_sql_chunks = [c for c in manifest.get("chunks", []) if c.get("kind") == "exec-sql"]
    exec_cics_chunks = [c for c in manifest.get("chunks", []) if c.get("kind") == "exec-cics"]
    data_chunks = [c for c in manifest.get("chunks", []) if c.get("kind") in ("data-record", "copybook-record")]
    division_chunks = {c["name"].split()[0].lower(): c for c in manifest.get("chunks", []) if c.get("kind") == "division"}
    return {
        "by_id": by_id,
        "procedure": procedure_chunks,
        "exec_sql": exec_sql_chunks,
        "exec_cics": exec_cics_chunks,
        "data": data_chunks,
        "divisions": division_chunks,
    }


def chunk_for_line(line_no: int, candidates: list[dict]) -> dict | None:
    """Innermost (smallest range) chunk whose [start_line, end_line] covers line_no."""
    best = None
    best_span = None
    for c in candidates:
        if c["start_line"] <= line_no <= c["end_line"]:
            span = c["end_line"] - c["start_line"]
            if best is None or span < best_span:
                best, best_span = c, span
    return best


# ---------- COBOL extraction --------------------------------------------

PROGRAM_ID_RE = re.compile(r"\bPROGRAM-ID\s*\.\s*([A-Z0-9][A-Z0-9-]*)", re.I)
COPY_RE = re.compile(
    r"\bCOPY\s+([A-Z0-9][A-Z0-9-]*)(?:\s+OF\s+([A-Z0-9-]+))?"
    r"(?:\s+REPLACING\s+(.*?))?\s*\.",
    re.I | re.S,
)
PERFORM_RE = re.compile(
    r"\bPERFORM\s+([A-Z0-9][A-Z0-9-]*)(?:\s+THRU\s+([A-Z0-9][A-Z0-9-]*))?"
    r"(?:\s+(\d+)\s+TIMES)?"
    r"(?:\s+(UNTIL|VARYING)\b)?",
    re.I,
)
GO_TO_RE = re.compile(
    r"\bGO\s+TO\s+([A-Z0-9][A-Z0-9-]*(?:\s+[A-Z0-9][A-Z0-9-]*)*)"
    r"(?:\s+DEPENDING\s+ON\s+([A-Z0-9][A-Z0-9-]*))?",
    re.I,
)
CALL_RE = re.compile(
    r"\bCALL\s+(?:'([^']+)'|\"([^\"]+)\"|([A-Z0-9][A-Z0-9-]*))"
    r"(?:\s+USING\s+([A-Z0-9][A-Z0-9-]*(?:\s*,?\s*[A-Z0-9][A-Z0-9-]*)*))?",
    re.I,
)
CICS_CMD_RE = re.compile(r"EXEC\s+CICS\s+([A-Z]+)", re.I)
CICS_PROGRAM_RE = re.compile(r"PROGRAM\s*\(\s*'?([A-Z0-9-]+)'?\s*\)", re.I)
SQL_VERB_RE = re.compile(r"EXEC\s+SQL\s+([A-Z]+)", re.I)
SQL_TABLE_RE = re.compile(r"\bFROM\s+([A-Z0-9_][A-Z0-9_.]*)|\bINTO\s+([A-Z0-9_][A-Z0-9_.]*)|\bUPDATE\s+([A-Z0-9_][A-Z0-9_.]*)|\bINSERT\s+INTO\s+([A-Z0-9_][A-Z0-9_.]*)", re.I)
SQL_CURSOR_RE = re.compile(r"\bCURSOR\s+([A-Z0-9_][A-Z0-9_-]*)|\b(?:OPEN|CLOSE|FETCH)\s+([A-Z0-9_][A-Z0-9_-]*)", re.I)
SQL_HOSTVAR_RE = re.compile(r":\s*([A-Z0-9][A-Z0-9-]*)", re.I)
SELECT_RE = re.compile(r"\bSELECT\s+([A-Z0-9][A-Z0-9-]*)\s+ASSIGN\s+TO\s+([A-Z0-9][A-Z0-9-]*(?:\.[A-Z0-9-]+)*)", re.I)
FD_RE = re.compile(r"^\s*FD\s+([A-Z0-9][A-Z0-9-]*)", re.I)
LEVEL_01_RE = re.compile(r"^\s*(0?1|77)\s+([A-Z0-9][A-Z0-9-]*)\s*(.*?)\s*\.?\s*$", re.I)
PIC_RE = re.compile(r"\bPIC(?:TURE)?(?:\s+IS)?\s+([X9SVA0-9()VP+./,$*-]+)", re.I)
USAGE_RE = re.compile(r"\bUSAGE(?:\s+IS)?\s+(COMP(?:-[0-9X])?|BINARY|DISPLAY|PACKED-DECIMAL|POINTER|PROCEDURE-POINTER|INDEX)", re.I)
REDEF_RE = re.compile(r"\bREDEFINES\s+([A-Z0-9][A-Z0-9-]*)", re.I)
OCCURS_RE = re.compile(r"\bOCCURS\s+(\d+)\b", re.I)
# Any COBOL level number (01-49, 66, 77, 88) followed by a data name.
LEVEL_ANY_RE = re.compile(r"^\s*(\d{1,2})\s+([A-Z0-9][A-Z0-9-]*)\s*(.*?)\s*\.?\s*$", re.I)


def extract_record_fields(logical: list[tuple[int, str]],
                          start_line: int, end_line: int) -> list[dict]:
    """Enumerate nested data items (levels 02-49) inside a 01-level record's
    span. The record header line (start_line) and any trailing FD / new 01-77
    boundary that an over-reaching span may include are skipped.
    """
    fields: list[dict] = []
    for ln, txt in logical:
        if ln <= start_line or ln > end_line:
            continue
        m = LEVEL_ANY_RE.match(txt)
        if not m:
            continue
        level = int(m.group(1))
        if level in (1, 77):  # a new top-level record ends this group
            break
        if not (2 <= level <= 49):  # skip 66 (RENAMES) / 88 (condition names)
            continue
        rest = m.group(3) or ""
        field = {
            "level": level, "name": m.group(2).upper(), "picture": None,
            "usage": None, "redefines": None, "occurs": None, "line": ln,
        }
        if (pm := PIC_RE.search(rest)): field["picture"] = pm.group(1)
        if (um := USAGE_RE.search(rest)): field["usage"] = um.group(1).upper()
        if (rm := REDEF_RE.search(rest)): field["redefines"] = rm.group(1).upper()
        if (om := OCCURS_RE.search(rest)): field["occurs"] = int(om.group(1))
        fields.append(field)
    return fields


def parse_paragraphs(chunk_index: dict) -> list[dict]:
    out: list[dict] = []
    sections_by_id = {c["id"]: c for c in chunk_index["procedure"] if c["kind"] == "section"}
    for c in chunk_index["procedure"]:
        section = None
        if c["kind"] == "paragraph":
            parent = sections_by_id.get(c.get("parent_id") or "")
            section = parent["name"] if parent else None
        out.append({
            "chunk_id": c["id"],
            "name": c["name"],
            "section": section,
            "start_line": c["start_line"],
            "end_line": c["end_line"],
        })
    return out


def extract_cobol_facts(lines: list[str], chunk_index: dict) -> dict:
    logical = fold_continuations(lines)
    facts = {
        "program_id": None,
        "paragraphs": parse_paragraphs(chunk_index),
        "performs": [], "go_tos": [], "calls": [], "copybooks": [],
        "exec_sql": [], "exec_cics": [],
        "data_records": [], "files": [], "jcl_steps": [], "cl_commands": [], "bms_maps": [],
        "errors": [],
    }

    # PROGRAM-ID
    for ln, txt in logical[:50]:
        m = PROGRAM_ID_RE.search(txt)
        if m:
            facts["program_id"] = m.group(1).upper()
            break

    # SELECT statements -> files
    selects: dict[str, dict] = {}
    for ln, txt in logical:
        m = SELECT_RE.search(txt)
        if m:
            name = m.group(1).upper()
            selects[name] = {
                "name": name, "assign_to": m.group(2).upper(),
                "organization": None, "access_mode": None, "record_name": None,
                "line": ln,
            }
    # FD + following 01 -> record_name
    current_fd = None
    for ln, txt in logical:
        m = FD_RE.match(txt)
        if m:
            current_fd = m.group(1).upper()
            if current_fd not in selects:
                selects[current_fd] = {
                    "name": current_fd, "assign_to": None, "organization": None,
                    "access_mode": None, "record_name": None, "line": ln,
                }
            continue
        if current_fd:
            lm = LEVEL_01_RE.match(txt)
            if lm and lm.group(1) in ("1", "01"):
                selects[current_fd]["record_name"] = lm.group(2).upper()
                current_fd = None
    facts["files"] = sorted(selects.values(), key=lambda f: (f["line"], f["name"]))

    # 01-level data records (DATA DIVISION only) — keyed off chunk manifest
    for c in chunk_index["data"]:
        facts["data_records"].append({
            "chunk_id": c["id"], "name": c["name"], "level": 1,
            "picture": None, "usage": None, "redefines": None, "occurs": None,
            "start_line": c["start_line"], "end_line": c["end_line"],
            "fields": [],
        })
    # back-fill picture/usage/redefines/occurs from the source
    rec_by_name = {r["name"]: r for r in facts["data_records"]}
    for ln, txt in logical:
        lm = LEVEL_01_RE.match(txt)
        if not lm:
            continue
        name = lm.group(2).upper()
        rec = rec_by_name.get(name)
        if not rec:
            continue
        rest = lm.group(3) or ""
        if (m := PIC_RE.search(rest)): rec["picture"] = m.group(1)
        if (m := USAGE_RE.search(rest)): rec["usage"] = m.group(1).upper()
        if (m := REDEF_RE.search(rest)): rec["redefines"] = m.group(1).upper()
        if (m := OCCURS_RE.search(rest)): rec["occurs"] = int(m.group(1))
    # enumerate nested fields (levels 02-49) within each record's span
    for rec in facts["data_records"]:
        rec["fields"] = extract_record_fields(logical, rec["start_line"], rec["end_line"])

    # COPY statements
    for ln, txt in logical:
        for m in COPY_RE.finditer(txt):
            name = m.group(1).upper()
            chunk = (chunk_for_line(ln, chunk_index["procedure"])
                     or chunk_for_line(ln, chunk_index["data"]))
            entry = {
                "name": name,
                "library": (m.group(2) or "").upper() or None,
                "replacing": [],  # TODO: parse REPLACING pairs
                "line": ln,
            }
            if chunk:
                entry["chunk_id"] = chunk["id"]
            else:
                div = chunk_index["divisions"].get("data") or chunk_index["divisions"].get("procedure")
                if div: entry["chunk_id"] = div["id"]
            facts["copybooks"].append(entry)

    # PERFORM / GO TO / CALL — only within paragraphs/sections
    for ln, txt in logical:
        chunk = chunk_for_line(ln, chunk_index["procedure"])
        if not chunk:
            continue
        from_name = chunk["name"]

        for m in PERFORM_RE.finditer(txt):
            kind = "simple"
            thru_to = None
            if m.group(2):
                kind, thru_to = "thru", m.group(2).upper()
            elif m.group(3):
                kind = "times"
            elif m.group(4):
                kind = m.group(4).lower()
            facts["performs"].append({
                "from": from_name, "to": m.group(1).upper(),
                "thru_to": thru_to, "kind": kind, "line": ln,
                "chunk_id": chunk["id"],
            })

        for m in GO_TO_RE.finditer(txt):
            targets = [t.upper() for t in re.split(r"\s+", m.group(1).strip()) if t]
            to_field = targets[0] if len(targets) == 1 else targets
            entry = {
                "from": from_name, "to": to_field,
                "depending_on": (m.group(2).upper() if m.group(2) else None),
                "line": ln, "chunk_id": chunk["id"],
            }
            facts["go_tos"].append(entry)

        for m in CALL_RE.finditer(txt):
            literal = m.group(1) or m.group(2)
            ident = m.group(3)
            target = (literal or ident or "").upper()
            if not target:
                continue
            using = []
            if m.group(4):
                using = [u.strip().upper() for u in re.split(r"\s*,?\s+", m.group(4).strip()) if u.strip()]
            facts["calls"].append({
                "from": from_name, "target": target, "kind": "call",
                "dynamic": literal is None and ident is not None,
                "using": using, "line": ln, "chunk_id": chunk["id"],
            })
            if literal is None and ident is not None:
                facts["errors"].append({
                    "code": "DYNAMIC_CALL_UNRESOLVED",
                    "message": f"dynamic CALL via variable {target!r}; xref pass cannot resolve",
                    "line": ln,
                })

    # EXEC SQL — read from chunk manifest, parse from source
    for c in chunk_index["exec_sql"]:
        block_lines = lines[c["start_line"] - 1 : c["end_line"]]
        # fold continuations within the block
        block_text = " ".join(cobol_body(b) for b in block_lines if not is_cobol_comment(b)).strip()
        block_text = re.sub(r"\s+", " ", block_text)
        verb_m = SQL_VERB_RE.search(block_text)
        verb = verb_m.group(1).upper() if verb_m else "UNKNOWN"
        tables: list[str] = []
        for tm in SQL_TABLE_RE.finditer(block_text):
            for g in tm.groups():
                if g:
                    tables.append(g.upper())
        cursors: list[str] = []
        for cm in SQL_CURSOR_RE.finditer(block_text):
            for g in cm.groups():
                if g:
                    cursors.append(g.upper())
        host_vars = [hm.group(1).upper() for hm in SQL_HOSTVAR_RE.finditer(block_text)]
        facts["exec_sql"].append({
            "chunk_id": c["id"], "statement": verb, "statement_text": block_text,
            "tables": sorted(set(tables)), "cursors": sorted(set(cursors)),
            "host_vars": list(dict.fromkeys(host_vars)),
            "start_line": c["start_line"], "end_line": c["end_line"],
        })

    # EXEC CICS — read from chunk manifest
    for c in chunk_index["exec_cics"]:
        block_lines = lines[c["start_line"] - 1 : c["end_line"]]
        block_text = " ".join(cobol_body(b) for b in block_lines if not is_cobol_comment(b)).strip()
        block_text = re.sub(r"\s+", " ", block_text)
        cmd_m = CICS_CMD_RE.search(block_text)
        command = cmd_m.group(1).upper() if cmd_m else "UNKNOWN"
        args: dict[str, str] = {}
        for am in re.finditer(r"([A-Z]+)\s*\(\s*([^)]+?)\s*\)", block_text, re.I):
            args[am.group(1).upper()] = am.group(2).strip().strip("'\"")
        facts["exec_cics"].append({
            "chunk_id": c["id"], "command": command, "args": args,
            "start_line": c["start_line"], "end_line": c["end_line"],
        })
        if command in ("LINK", "XCTL"):
            pm = CICS_PROGRAM_RE.search(block_text)
            if pm:
                from_chunk = chunk_for_line(c["start_line"], chunk_index["procedure"])
                facts["calls"].append({
                    "from": (from_chunk["name"] if from_chunk else "?"),
                    "target": pm.group(1).upper(),
                    "kind": "cics-link" if command == "LINK" else "cics-xctl",
                    "dynamic": False, "using": [], "line": c["start_line"],
                    "chunk_id": (from_chunk["id"] if from_chunk else c["id"]),
                })
    return facts


# ---------- JCL extraction ----------------------------------------------

JOB_RE = re.compile(r"^//(?P<name>[A-Z0-9$#@]+)\s+JOB\b", re.I)
STEP_RE = re.compile(r"^//(?P<name>[A-Z0-9$#@]+)\s+EXEC\s+(?:PGM=(?P<pgm>[A-Z0-9$#@]+)|(?P<proc>[A-Z0-9$#@]+))", re.I)
DD_RE = re.compile(r"^//(?P<name>[A-Z0-9$#@]+)\s+DD\s+(?P<rest>.+?)\s*$", re.I)
DSN_RE = re.compile(r"DSN=([A-Z0-9$#@.()&]+)", re.I)
DISP_RE = re.compile(r"DISP=\(?([A-Z0-9,]+)\)?", re.I)
INLINE_DD_RE = re.compile(r"DD\s+(?:\*|DATA)\b", re.I)


def extract_jcl_facts(lines: list[str], chunk_index: dict) -> dict:
    facts = {
        "program_id": None, "paragraphs": [], "performs": [], "go_tos": [],
        "calls": [], "copybooks": [], "exec_sql": [], "exec_cics": [],
        "data_records": [], "files": [],
        "jcl_steps": [], "cl_commands": [], "bms_maps": [], "errors": [],
    }
    step_chunks = [c for c in chunk_index["by_id"].values() if c.get("kind") == "jcl-step"]
    for c in step_chunks:
        block = lines[c["start_line"] - 1 : c["end_line"]]
        program = None
        proc = None
        dds: list[dict] = []
        current_dd: dict | None = None
        for offset, raw in enumerate(block):
            line_no = c["start_line"] + offset
            if raw.startswith("//*"):
                continue
            m = STEP_RE.match(raw)
            if m and offset == 0:
                program = (m.group("pgm") or "").upper() or None
                proc = (m.group("proc") or "").upper() or None
                continue
            dm = DD_RE.match(raw)
            if dm:
                current_dd = {
                    "name": dm.group("name").upper(),
                    "dsn": None, "disp": None, "inline": False,
                }
                rest = dm.group("rest")
                if (dsn := DSN_RE.search(rest)): current_dd["dsn"] = dsn.group(1).upper()
                if (di := DISP_RE.search(rest)): current_dd["disp"] = di.group(1).upper()
                if INLINE_DD_RE.search(raw): current_dd["inline"] = True
                dds.append(current_dd)
                continue
            # continuation of last DD
            if current_dd and raw.startswith("//") and not re.match(r"^//[A-Z0-9$#@]+\s", raw):
                rest = raw[2:]
                if (dsn := DSN_RE.search(rest)) and not current_dd["dsn"]:
                    current_dd["dsn"] = dsn.group(1).upper()
                if (di := DISP_RE.search(rest)) and not current_dd["disp"]:
                    current_dd["disp"] = di.group(1).upper()
        facts["jcl_steps"].append({
            "chunk_id": c["id"], "name": c["name"], "program": program,
            "proc": proc, "dds": dds,
            "start_line": c["start_line"], "end_line": c["end_line"],
        })
        if program:
            facts["calls"].append({
                "from": c["name"], "target": program, "kind": "exec-program",
                "dynamic": False, "using": [], "line": c["start_line"],
                "chunk_id": c["id"],
            })
    return facts


# ---------- IBM i CL extraction ----------------------------------------

CL_PARAMETER_RE = re.compile(r"\b([A-Z][A-Z0-9]*)\s*\(([^()]*)\)", re.I)
CL_NESTED_CALL_RE = re.compile(r"\bCALL\s+PGM\s*\(\s*([A-Z0-9_$#@&/-]+)\s*\)", re.I)


def extract_cl_facts(lines: list[str], chunk_index: dict) -> dict:
    program_chunks = [
        chunk for chunk in chunk_index["by_id"].values()
        if chunk.get("kind") == "cl-program"
    ]
    command_chunks = sorted(
        (
            chunk for chunk in chunk_index["by_id"].values()
            if chunk.get("kind") == "cl-command"
        ),
        key=lambda chunk: chunk["start_line"],
    )
    program_id = program_chunks[0]["name"] if program_chunks else None
    facts = {
        "program_id": program_id, "paragraphs": [], "performs": [], "go_tos": [],
        "calls": [], "copybooks": [], "exec_sql": [], "exec_cics": [],
        "data_records": [], "files": [], "jcl_steps": [], "cl_commands": [],
        "bms_maps": [], "errors": [],
    }
    for chunk in command_chunks:
        source_lines = lines[chunk["start_line"] - 1:chunk["end_line"]]
        text = " ".join(line.strip().rstrip("+-").rstrip() for line in source_lines)
        text = re.sub(r"\s+", " ", text).strip()
        command = chunk["name"].upper()
        parameters = {
            match.group(1).upper(): match.group(2).strip()
            for match in CL_PARAMETER_RE.finditer(text)
        }
        facts["cl_commands"].append({
            "chunk_id": chunk["id"],
            "command": command,
            "text": text,
            "parameters": parameters,
            "start_line": chunk["start_line"],
            "end_line": chunk["end_line"],
        })

        target = None
        call_kind = None
        if command == "CALL":
            target = parameters.get("PGM")
            call_kind = "cl-call"
        elif command == "CALLPRC":
            target = parameters.get("PRC")
            call_kind = "cl-callprc"
        elif command == "SBMJOB":
            nested_call = CL_NESTED_CALL_RE.search(text)
            if nested_call:
                target = nested_call.group(1)
                call_kind = "cl-submit-job"
        if target and call_kind:
            target = target.strip("'\"").upper()
            facts["calls"].append({
                "from": program_id or chunk["name"],
                "target": target,
                "kind": call_kind,
                "dynamic": "&" in target,
                "using": [],
                "line": chunk["start_line"],
                "chunk_id": chunk["id"],
            })
    return facts


# ---------- BMS / copybook ----------------------------------------------

def extract_bms_facts(lines: list[str], chunk_index: dict) -> dict:
    facts = {
        "program_id": None, "paragraphs": [], "performs": [], "go_tos": [],
        "calls": [], "copybooks": [], "exec_sql": [], "exec_cics": [],
        "data_records": [], "files": [], "jcl_steps": [], "cl_commands": [],
        "bms_maps": [], "errors": [],
    }
    map_chunks = [c for c in chunk_index["by_id"].values() if c.get("kind") == "bms-map"]
    for c in map_chunks:
        mapset = (c.get("parent_id") or "").split("/")[-1] or "UNKNOWN"
        facts["bms_maps"].append({
            "chunk_id": c["id"], "mapset": mapset.upper(), "map": c["name"].upper(),
            "fields": [],
            "start_line": c["start_line"], "end_line": c["end_line"],
        })
    return facts


def extract_copybook_facts(lines: list[str], chunk_index: dict) -> dict:
    facts = {
        "program_id": None, "paragraphs": [], "performs": [], "go_tos": [],
        "calls": [], "copybooks": [], "exec_sql": [], "exec_cics": [],
        "data_records": [], "files": [], "jcl_steps": [], "cl_commands": [],
        "bms_maps": [], "errors": [],
    }
    logical = fold_continuations(lines)
    for c in chunk_index["by_id"].values():
        if c.get("kind") != "copybook-record":
            continue
        facts["data_records"].append({
            "chunk_id": c["id"], "name": c["name"], "level": 1,
            "picture": None, "usage": None, "redefines": None, "occurs": None,
            "start_line": c["start_line"], "end_line": c["end_line"],
            "fields": extract_record_fields(logical, c["start_line"], c["end_line"]),
        })
    return facts


# ---------- driver ------------------------------------------------------

def write_facts(out_path: Path, payload: dict) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=False)
    out_path.write_text(text + "\n", encoding="utf-8")


def validate(payload: dict) -> None:
    try:
        import jsonschema  # type: ignore
    except ImportError:
        return
    with SCHEMA_PATH.open("rb") as f:
        schema = json.loads(f.read().decode("utf-8"))
    jsonschema.validate(payload, schema)


def report(payload: dict, out_path: Path) -> None:
    counts = {k: len(payload[k]) for k in (
        "paragraphs", "performs", "go_tos", "calls", "copybooks",
        "exec_sql", "exec_cics", "data_records", "files", "jcl_steps", "cl_commands", "bms_maps",
    )}
    summary = " ".join(f"{k}={v}" for k, v in counts.items())
    print(f"OK: wrote {out_path}")
    print(f"  kind={payload['source_kind']} program_id={payload['program_id']} "
          f"src_sha={payload['source_sha256'][:8]} man_sha={payload['manifest_sha256'][:8]}")
    print(f"  {summary}")
    if payload["errors"]:
        print(f"  errors={len(payload['errors'])}:")
        for e in payload["errors"]:
            print(f"    [{e['code']}] line {e.get('line')}: {e['message']}")


EXTRACTORS = {
    "cobol":    extract_cobol_facts,
    "cl":       extract_cl_facts,
    "jcl":      extract_jcl_facts,
    "proc":     extract_jcl_facts,
    "copybook": extract_copybook_facts,
    "bms":      extract_bms_facts,
}


def run_one(args: argparse.Namespace) -> int:
    source_path = resolve_source(args.source, args.source_root)
    doc_dir = default_doc_dir(source_path)
    manifest_path = Path(args.manifest) if args.manifest else doc_dir / "chunk-manifest.json"
    output_path = Path(args.output) if args.output else doc_dir / "facts.json"

    if not manifest_path.exists():
        print(f"ERROR: chunk-manifest.json not found: {manifest_path}", file=sys.stderr)
        return 2

    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes.decode("utf-8"))
    source_bytes = source_path.read_bytes()
    text, _enc = read_text(source_path, manifest.get("encoding_detected"))
    lines = text.splitlines()

    source_kind = manifest.get("source_kind", "cobol")
    chunk_index = build_chunk_index(manifest)
    extractor = EXTRACTORS.get(source_kind)
    if not extractor:
        print(f"ERROR: unsupported source_kind {source_kind!r}", file=sys.stderr)
        return 2
    parsed = extractor(lines, chunk_index)

    payload = {
        "facts_version": "1.0",
        "source_path": manifest.get("source_path") or str(source_path).replace("\\", "/"),
        "source_kind": source_kind,
        "source_platform": manifest.get("source_platform", "mainframe"),
        "manifest_sha256": sha256_bytes(manifest_bytes),
        "source_sha256": sha256_bytes(source_bytes),
        "program_id": parsed["program_id"],
        "paragraphs": parsed["paragraphs"],
        "performs": parsed["performs"],
        "go_tos": parsed["go_tos"],
        "calls": parsed["calls"],
        "copybooks": parsed["copybooks"],
        "exec_sql": parsed["exec_sql"],
        "exec_cics": parsed["exec_cics"],
        "data_records": parsed["data_records"],
        "files": parsed["files"],
        "jcl_steps": parsed["jcl_steps"],
        "cl_commands": parsed.get("cl_commands", []),
        "bms_maps": parsed["bms_maps"],
        "incoming_xref": [],
        "errors": parsed["errors"],
    }

    try:
        validate(payload)
    except Exception as e:  # jsonschema.ValidationError or others
        print(f"ERROR: schema validation failed: {e}", file=sys.stderr)
        return 3

    write_facts(output_path, payload)
    report(payload, output_path)
    return 0


def run_xref(_args: argparse.Namespace) -> int:
    # Delegate to the dedicated workspace pass so behaviour stays single-sourced.
    from importlib import util as _u
    spec = _u.spec_from_file_location("xref_pass", Path(__file__).with_name("xref-incoming-pass.py"))
    mod = _u.module_from_spec(spec)  # type: ignore[arg-type]
    assert spec and spec.loader
    spec.loader.exec_module(mod)  # type: ignore[attr-defined]
    return int(mod.main([]))


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="COBOL/CL/JCL facts extractor (phase B).")
    p.add_argument("--source")
    p.add_argument("--manifest")
    p.add_argument("--output")
    p.add_argument("--source-root", dest="source_root")
    p.add_argument("--xref-pass", action="store_true",
                   help="Run the workspace-scope incoming-xref pass and exit.")
    args = p.parse_args(argv)
    if args.xref_pass:
        return run_xref(args)
    if not args.source:
        p.error("--source is required unless --xref-pass is given")
    return run_one(args)


if __name__ == "__main__":
    sys.exit(main())
