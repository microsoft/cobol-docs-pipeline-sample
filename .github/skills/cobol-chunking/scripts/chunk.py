#!/usr/bin/env python3
"""Deterministic COBOL/CL/JCL/copybook/BMS/PROC chunker.

Implements the 12-step algorithm in SKILL.md and
emits a ChunkManifest validated against
schemas/outputs.schema.json.

Usage:
    py -3 chunk.py --source <rel-path> \
        [--output <path>] [--source-root <root>] [--kind-hint auto]
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parent.parent      # .github/skills/cobol-chunking
# SKILL_ROOT.parents: [scripts/..]=skills, [..]=.github, [..]=repo root.
REPO_ROOT = SKILL_ROOT.parent.parent.parent
SCHEMA_PATH = SKILL_ROOT / "schemas" / "outputs.schema.json"


# ---------- encoding -----------------------------------------------------

def detect_encoding(raw: bytes) -> str:
    """Heuristic: EBCDIC has many bytes >= 0x80 with very few ASCII; UTF-8
    decodes cleanly; otherwise fall back to latin-1."""
    sample = raw[:4096]
    # EBCDIC fingerprint: presence of 0x40 (space) and lots of
    # 0xC1-0xC9 / 0xD1-0xD9 (A-I, J-R) and few 0x20.
    if sample and sum(1 for b in sample if b == 0x40) > len(sample) * 0.05 \
            and sum(1 for b in sample if b == 0x20) < len(sample) * 0.01 \
            and sum(1 for b in sample if 0xC1 <= b <= 0xE9) > len(sample) * 0.1:
        # Python ships cp037 on every supported platform, but not cp1047.
        return "cp037"
    try:
        sample.decode("utf-8")
        # If it's ASCII-only or valid UTF-8, prefer utf-8.
        raw.decode("utf-8")
        return "utf-8"
    except UnicodeDecodeError:
        pass
    return "latin-1"


def normalize_encoding(encoding: str) -> str:
    """Map configured IBM codec names to codecs available in Python."""
    return "cp037" if encoding.lower() == "cp1047" else encoding.lower()


def configured_encoding(cfg: dict, source_path: str) -> str:
    for pattern, encoding in (cfg.get("encodings") or {}).items():
        if fnmatch.fnmatch(source_path.lower(), pattern.lower()):
            return encoding
    return "auto"


# ---------- kind detection ----------------------------------------------

def detect_kind(lines: list[str], hint: str, ext: str) -> str:
    if hint and hint != "auto":
        return hint
    ext = ext.lower().lstrip(".")
    if ext in ("jcl",):
        return "jcl"
    if ext in ("prc",):
        return "proc"
    if ext in ("cl", "clp", "clle"):
        return "cl"
    if ext in ("bms",):
        return "bms"
    if ext in ("cpy",):
        return "copybook"
    for raw in lines[:200]:
        s = raw.strip()
        if not s:
            continue
        u = s.upper()
        if u.startswith("//") and "JOB" in u.split()[0:2] + (u.split()[1:2] or []):
            return "jcl"
        if u.startswith("//"):
            return "jcl"
        if "DFHMSD" in u:
            return "bms"
        if "IDENTIFICATION DIVISION" in u or u.startswith("CBL "):
            return "cobol"
        if u.startswith("PROC ") or " PROC " in u or u.endswith(" PEND"):
            return "proc"
    if ext in ("cbl", "cob", "cblle", "sqlcblle"):
        return "cobol"
    return "copybook"


def detect_platform(lines: list[str], hint: str, ext: str) -> str:
    """Resolve the source runtime without changing the COBOL source kind."""
    if hint and hint != "auto":
        return hint
    if ext.lower().lstrip(".") in ("cblle", "sqlcblle", "cl", "clp", "clle"):
        return "ibmi"
    source = "\n".join(lines[:500]).upper()
    ibmi_markers = (
        "EXEC SQL SET OPTION",
        "ASSIGN TO DATABASE-",
        "ORGANIZATION IS TRANSACTION",
    )
    return "ibmi" if any(marker in source for marker in ibmi_markers) else "mainframe"


def configured_platform(cfg: dict, source_path: str) -> str:
    for pattern, platform in (cfg.get("platforms") or {}).items():
        if fnmatch.fnmatch(source_path.lower(), pattern.lower()):
            return platform
    return cfg.get("platform", "auto")


# ---------- COBOL area extraction ---------------------------------------

def cobol_area(line: str) -> tuple[str, str]:
    """Return (indicator_char, area_a_b_text) for a fixed-format line.

    Columns 1-6 = sequence/change-tag area (ignored), column 7 = indicator,
    columns 8-72 = source. Lines shorter than 7 chars are treated as blank.
    """
    if len(line) < 7:
        return " ", ""
    ind = line[6]
    body = line[7:72] if len(line) > 7 else ""
    return ind, body


COMMENT_INDICATORS = set("*/Dd")


def is_comment(ind: str) -> bool:
    return ind in COMMENT_INDICATORS or ind == "$"


# ---------- COBOL outline -----------------------------------------------

DIVISION_RE = re.compile(
    r"^\s*(IDENTIFICATION|ENVIRONMENT|DATA|PROCEDURE)\s+DIVISION"
    r"(?:(?=\s+(?:USING|CHAINING)\b)\s+[^.]*)?\s*\.",
    re.I,
)
SECTION_RE = re.compile(
    r"^\s*([A-Z0-9][A-Z0-9-]*)\s+SECTION\s*(?:\.|$)", re.I,
)
PARA_RE = re.compile(
    r"^\s{0,4}([A-Z0-9][A-Z0-9-]*)\s*\.\s*(?:\*.*)?$", re.I,
)
PROGRAM_ID_RE = re.compile(r"^\s*PROGRAM-ID\s*\.\s*([A-Z0-9-]+)", re.I)
EXEC_OPEN_RE = re.compile(r"^\s*EXEC\s+(SQL|CICS)\b", re.I)
EXEC_CLOSE_RE = re.compile(r"\bEND-EXEC\b", re.I)
DATA_01_RE = re.compile(r"^\s*0?1\s+([A-Z0-9][A-Z0-9-]*)", re.I)

# Tokens that look like paragraphs but are really verbs/clauses we must
# never treat as paragraph headers.
RESERVED_PARA = {
    "ELSE", "END-IF", "END-EVALUATE", "END-PERFORM", "END-READ", "END-WRITE",
    "END-CALL", "END-SEARCH", "END-START", "END-STRING", "END-UNSTRING",
    "END-COMPUTE", "END-ADD", "END-SUBTRACT", "END-MULTIPLY", "END-DIVIDE",
    "WHEN", "OTHERWISE", "EXIT",
}


def chunk_cobol(lines: list[str], source_path: str) -> list[dict]:
    program_id = Path(source_path).stem.upper()
    for raw in lines[:200]:
        ind, body = cobol_area(raw)
        if is_comment(ind):
            continue
        m = PROGRAM_ID_RE.match(body)
        if m:
            program_id = m.group(1).upper()
            break

    chunks: list[dict] = []
    n = len(lines)

    # Pass 1: locate divisions.
    divisions: list[tuple[int, str]] = []  # (line, name)
    for i, raw in enumerate(lines, start=1):
        ind, body = cobol_area(raw)
        if is_comment(ind) or not body.strip():
            continue
        m = DIVISION_RE.match(body)
        if m:
            divisions.append((i, m.group(1).upper()))

    # Map each division to its end line (start of next division - 1, or EOF).
    # Extend the first division back to line 1 so the file prologue
    # (comment header) is covered by the IDENTIFICATION DIVISION chunk.
    div_ranges: list[tuple[int, int, str]] = []
    for idx, (ln, name) in enumerate(divisions):
        start = 1 if idx == 0 else ln
        end = divisions[idx + 1][0] - 1 if idx + 1 < len(divisions) else n
        div_ranges.append((start, end, name))
        chunks.append({
            "id": f"{program_id}/{name.lower()}-division",
            "kind": "division",
            "name": f"{name} DIVISION",
            "start_line": start,
            "end_line": end,
            "parent_id": None,
        })

    # Pass 2: within PROCEDURE DIVISION, find SECTIONs and paragraphs.
    proc = next((r for r in div_ranges if r[2] == "PROCEDURE"), None)
    data = next((r for r in div_ranges if r[2] == "DATA"), None)

    if proc:
        proc_start, proc_end, _ = proc
        proc_parent = f"{program_id}/procedure-division"

        # First: scan for SECTION headers.
        sections: list[tuple[int, str]] = []
        for i in range(proc_start + 1, proc_end + 1):
            ind, body = cobol_area(lines[i - 1])
            if is_comment(ind) or not body.strip():
                continue
            m = SECTION_RE.match(body)
            if m and m.group(1).upper() not in {"DECLARATIVES"}:
                sections.append((i, m.group(1).upper()))

        # Compute section ranges.
        section_ranges: list[tuple[int, int, str]] = []
        for idx, (ln, name) in enumerate(sections):
            end = sections[idx + 1][0] - 1 if idx + 1 < len(sections) else proc_end
            section_ranges.append((ln, end, name))
            chunks.append({
                "id": f"{proc_parent}/{name}",
                "kind": "section",
                "name": name,
                "start_line": ln,
                "end_line": end,
                "parent_id": proc_parent,
            })

        # Paragraphs: header in area A (col 8-11). Treat any non-section,
        # single-word-followed-by-period line in area A as paragraph header.
        para_scan_ranges = section_ranges or [(proc_start + 1, proc_end, None)]
        for sec_start, sec_end, sec_name in para_scan_ranges:
            section_id = (f"{proc_parent}/{sec_name}" if sec_name else proc_parent)
            paras: list[tuple[int, str]] = []
            for i in range(sec_start, sec_end + 1):
                raw = lines[i - 1]
                if len(raw) < 8:
                    continue
                ind, body = cobol_area(raw)
                if is_comment(ind) or not body.strip():
                    continue
                # Paragraph header must start in Area A: cols 8-11.
                # body is cols 8-72; Area A is body[0:4].
                area_a = body[:4]
                if not area_a.strip():
                    continue
                # Skip SECTION headers (already captured).
                if SECTION_RE.match(body):
                    continue
                # Skip DIVISION headers.
                if DIVISION_RE.match(body):
                    continue
                m = PARA_RE.match(body)
                if not m:
                    continue
                name = m.group(1).upper()
                if name in RESERVED_PARA:
                    continue
                # Avoid mis-matching things like "01 NAME." (data items in
                # PROCEDURE? not possible, but be safe).
                if name.isdigit():
                    continue
                paras.append((i, name))

            for idx, (ln, name) in enumerate(paras):
                end = paras[idx + 1][0] - 1 if idx + 1 < len(paras) else sec_end
                chunks.append({
                    "id": f"{section_id}/{name}",
                    "kind": "paragraph",
                    "name": name,
                    "start_line": ln,
                    "end_line": end,
                    "parent_id": section_id,
                })

        # Pass 3: EXEC SQL / EXEC CICS blocks within PROCEDURE.
        exec_chunks = []
        i = proc_start
        while i <= proc_end:
            raw = lines[i - 1]
            ind, body = cobol_area(raw)
            if not is_comment(ind):
                m = EXEC_OPEN_RE.match(body)
                if m:
                    kind = m.group(1).upper()
                    start = i
                    j = i
                    while j <= proc_end:
                        ind2, body2 = cobol_area(lines[j - 1])
                        if not is_comment(ind2) and EXEC_CLOSE_RE.search(body2):
                            break
                        j += 1
                    end = min(j, proc_end)
                    parent_id = _find_enclosing_paragraph(chunks, start)
                    exec_chunks.append({
                        "id": f"{parent_id}/exec-{kind.lower()}-L{start}",
                        "kind": "exec-sql" if kind == "SQL" else "exec-cics",
                        "name": f"EXEC {kind} @ L{start}",
                        "start_line": start,
                        "end_line": end,
                        "parent_id": parent_id,
                    })
                    i = end + 1
                    continue
            i += 1
        chunks.extend(exec_chunks)

    # Pass 4: DATA DIVISION top-level 01 records.
    if data:
        data_start, data_end, _ = data
        data_parent = f"{program_id}/data-division"
        records: list[tuple[int, str]] = []
        for i in range(data_start + 1, data_end + 1):
            ind, body = cobol_area(lines[i - 1])
            if is_comment(ind) or not body.strip():
                continue
            # 01-level must start in Area A.
            area_a = body[:4]
            if not area_a.strip():
                continue
            # Must literally start with "01 " (or "01" followed by space).
            stripped = body.lstrip()
            if not re.match(r"^0?1\s+[A-Z][A-Z0-9-]*", stripped, re.I):
                continue
            m = DATA_01_RE.match(body)
            if m:
                records.append((i, m.group(1).upper()))
        for idx, (ln, name) in enumerate(records):
            end = records[idx + 1][0] - 1 if idx + 1 < len(records) else data_end
            chunks.append({
                "id": f"{data_parent}/{name}",
                "kind": "data-record",
                "name": name,
                "start_line": ln,
                "end_line": end,
                "parent_id": data_parent,
            })

    return chunks


def _dedupe_chunk_ids(chunks: list[dict], errors: list[dict]) -> None:
    """Make `chunks[].id` globally unique by appending `__L<start_line>` to
    the 2nd+ occurrence of any collision (and `_<n>` if even that collides).

    Phase A *should* produce unique ids, but data-division `FILLER` and
    re-defined records can legitimately appear multiple times. Records each
    rename as a `DUPLICATE_CHUNK_ID_RENAMED` entry on `errors` and rewrites
    `parent_id` references downstream so the tree stays consistent.
    """
    seen: dict[str, int] = {}
    rename: dict[int, str] = {}  # index_in_chunks -> new_id
    for i, c in enumerate(chunks):
        cid = c["id"]
        if cid not in seen:
            seen[cid] = 1
            continue
        seen[cid] += 1
        suffix = f"__L{c.get('start_line', 'X')}"
        new_id = cid + suffix
        # In the unlikely event two collisions share the same start_line.
        if new_id in seen or new_id in rename.values():
            new_id = f"{cid}{suffix}_{seen[cid]}"
        rename[i] = new_id
        seen[new_id] = 1

    if not rename:
        return

    # Build old -> new lookup; a chunk id can only be renamed once because
    # only the 2nd+ occurrence is touched, so the first occurrence keeps
    # its original id and stays a valid parent target.
    id_map_by_index: dict[int, tuple[str, str]] = {
        i: (chunks[i]["id"], new) for i, new in rename.items()
    }
    # Apply id rewrites.
    for i, (old, new) in id_map_by_index.items():
        chunks[i]["id"] = new
        errors.append({
            "code": "DUPLICATE_CHUNK_ID_RENAMED",
            "message": f"id collision: {old!r} renamed to {new!r}",
            "line": chunks[i].get("start_line") or 0,
        })

    # Rewrite parent_id references that may target a renamed chunk.
    # NOTE: only renamed chunks could be referenced by exactly their old id,
    # and the first occurrence (which kept the old id) remains a valid
    # target — so we only need to rewrite when a child's parent_id matches
    # a renamed id AND the child sits between the original and the
    # renamed chunk in the chunk list. In practice no current emitter
    # depends on duplicate-name parents, so this is a defensive pass.
    renamed_old_ids = {old for old, _ in id_map_by_index.values()}
    if not renamed_old_ids:
        return
    # Map (old_id, child_index) -> new_id by nearest renamed ancestor that
    # encloses the child by line range.
    for child in chunks:
        pid = child.get("parent_id")
        if pid not in renamed_old_ids:
            continue
        cs = child.get("start_line") or 0
        best: tuple[int, str] | None = None  # (start_line, new_id)
        for i, (old, new) in id_map_by_index.items():
            if old != pid:
                continue
            ps = chunks[i].get("start_line") or 0
            pe = chunks[i].get("end_line") or 0
            if ps <= cs <= pe and (best is None or ps > best[0]):
                best = (ps, new)
        if best is not None:
            child["parent_id"] = best[1]


def _find_enclosing_paragraph(chunks: list[dict], line: int) -> str | None:
    enclosing = None
    for c in chunks:
        if c["kind"] == "paragraph" and c["start_line"] <= line <= c["end_line"]:
            enclosing = c["id"]
    if enclosing:
        return enclosing
    for c in chunks:
        if c["kind"] == "section" and c["start_line"] <= line <= c["end_line"]:
            return c["id"]
    return None


# ---------- JCL ---------------------------------------------------------

JCL_JOB_RE = re.compile(r"^//(\S+)\s+JOB\b", re.I)
JCL_STEP_RE = re.compile(r"^//(\S*)\s+EXEC\b", re.I)
JCL_DD_RE = re.compile(r"^//(\S+)\s+DD\b", re.I)
JCL_PROC_RE = re.compile(r"^//(\S+)\s+PROC\b", re.I)
JCL_PEND_RE = re.compile(r"^//\s*PEND\b", re.I)


def chunk_jcl(lines: list[str], source_path: str) -> list[dict]:
    chunks: list[dict] = []
    n = len(lines)
    job_name = Path(source_path).stem.upper()

    # Find JOB card.
    job_line = None
    for i, raw in enumerate(lines, start=1):
        m = JCL_JOB_RE.match(raw)
        if m:
            job_name = m.group(1).upper()
            job_line = i
            break

    if job_line:
        chunks.append({
            "id": f"{job_name}",
            "kind": "jcl-job",
            "name": job_name,
            "start_line": job_line,
            "end_line": n,
            "parent_id": None,
        })
        job_parent = job_name
    else:
        job_parent = None

    # Steps.
    steps: list[tuple[int, str]] = []
    for i, raw in enumerate(lines, start=1):
        if job_line and i <= job_line:
            continue
        if raw.startswith("//*"):
            continue
        m = JCL_STEP_RE.match(raw)
        if m:
            name = m.group(1).upper()
            if not name:
                name = f"STEP{len(steps) + 1}"
            steps.append((i, name))
    for idx, (ln, name) in enumerate(steps):
        end = steps[idx + 1][0] - 1 if idx + 1 < len(steps) else n
        chunks.append({
            "id": f"{job_parent}/{name}" if job_parent else name,
            "kind": "jcl-step",
            "name": name,
            "start_line": ln,
            "end_line": end,
            "parent_id": job_parent,
        })

    # PROC definitions (inline).
    procs: list[tuple[int, str]] = []
    proc_ends: dict[int, int] = {}
    open_proc = None
    for i, raw in enumerate(lines, start=1):
        m = JCL_PROC_RE.match(raw)
        if m:
            procs.append((i, m.group(1).upper()))
            open_proc = i
            continue
        if open_proc and JCL_PEND_RE.match(raw):
            proc_ends[open_proc] = i
            open_proc = None
    for ln, name in procs:
        end = proc_ends.get(ln, n)
        chunks.append({
            "id": f"{job_parent}/{name}" if job_parent else name,
            "kind": "jcl-proc",
            "name": name,
            "start_line": ln,
            "end_line": end,
            "parent_id": job_parent,
        })

    return chunks


# ---------- IBM i CL ----------------------------------------------------

CL_COMMAND_RE = re.compile(r"^(?:[A-Z0-9_$#@]+:\s*)?([A-Z][A-Z0-9]*)\b", re.I)


def chunk_cl(lines: list[str], source_path: str) -> list[dict]:
    """Emit one CL program plus deterministic logical-command children."""
    program_name = Path(source_path).stem.upper()
    command_spans: list[tuple[int, int, str]] = []
    start_line: int | None = None
    command_parts: list[str] = []
    in_comment = False

    for line_no, raw in enumerate(lines, start=1):
        text = raw.strip()
        if in_comment:
            if "*/" in text:
                text = text.split("*/", 1)[1].strip()
                in_comment = False
            else:
                continue
        while "/*" in text:
            before, after = text.split("/*", 1)
            if "*/" in after:
                text = (before + " " + after.split("*/", 1)[1]).strip()
            else:
                text = before.strip()
                in_comment = True
                break
        if not text:
            continue
        if start_line is None:
            start_line = line_no
        continued = text.endswith(("+", "-"))
        command_parts.append(text[:-1].rstrip() if continued else text)
        if continued:
            continue
        command_text = " ".join(command_parts)
        match = CL_COMMAND_RE.match(command_text)
        command = match.group(1).upper() if match else "UNKNOWN"
        command_spans.append((start_line, line_no, command))
        start_line = None
        command_parts = []

    if start_line is not None:
        command_text = " ".join(command_parts)
        match = CL_COMMAND_RE.match(command_text)
        command = match.group(1).upper() if match else "UNKNOWN"
        command_spans.append((start_line, len(lines), command))

    program_start = next((start for start, _, cmd in command_spans if cmd == "PGM"), 1)
    program_end = next((end for _, end, cmd in reversed(command_spans) if cmd == "ENDPGM"), len(lines))
    chunks = [{
        "id": program_name,
        "kind": "cl-program",
        "name": program_name,
        "start_line": program_start,
        "end_line": program_end,
        "parent_id": None,
    }]
    for index, (start, end, command) in enumerate(command_spans, start=1):
        chunks.append({
            "id": f"{program_name}/{command}-{index:04d}",
            "kind": "cl-command",
            "name": command,
            "start_line": start,
            "end_line": end,
            "parent_id": program_name,
        })
    return chunks


# ---------- Copybook ----------------------------------------------------

def chunk_copybook(lines: list[str], source_path: str) -> list[dict]:
    chunks: list[dict] = []
    n = len(lines)
    records: list[tuple[int, str]] = []
    for i, raw in enumerate(lines, start=1):
        ind, body = cobol_area(raw)
        if is_comment(ind) or not body.strip():
            continue
        m = DATA_01_RE.match(body)
        if m and body[:4].strip():
            records.append((i, m.group(1).upper()))
    for idx, (ln, name) in enumerate(records):
        end = records[idx + 1][0] - 1 if idx + 1 < len(records) else n
        chunks.append({
            "id": f"{Path(source_path).stem.upper()}/{name}",
            "kind": "copybook-record",
            "name": name,
            "start_line": ln,
            "end_line": end,
            "parent_id": None,
        })
    return chunks


# ---------- BMS ---------------------------------------------------------

BMS_MAPSET_RE = re.compile(r"^\s*([A-Z0-9]+)\s+DFHMSD", re.I)
BMS_MAP_RE = re.compile(r"^\s*([A-Z0-9]+)\s+DFHMDI", re.I)
BMS_FIELD_RE = re.compile(r"^\s*([A-Z0-9]+)\s+DFHMDF", re.I)


def chunk_bms(lines: list[str], source_path: str) -> list[dict]:
    chunks: list[dict] = []
    n = len(lines)
    mapsets, maps, fields = [], [], []
    for i, raw in enumerate(lines, start=1):
        if BMS_MAPSET_RE.match(raw):
            mapsets.append((i, BMS_MAPSET_RE.match(raw).group(1).upper()))
        elif BMS_MAP_RE.match(raw):
            maps.append((i, BMS_MAP_RE.match(raw).group(1).upper()))
        elif BMS_FIELD_RE.match(raw):
            fields.append((i, BMS_FIELD_RE.match(raw).group(1).upper()))

    parent_set = None
    for idx, (ln, name) in enumerate(mapsets):
        end = mapsets[idx + 1][0] - 1 if idx + 1 < len(mapsets) else n
        chunks.append({
            "id": name, "kind": "bms-mapset", "name": name,
            "start_line": ln, "end_line": end, "parent_id": None,
        })
        parent_set = name
    parent_map = None
    for idx, (ln, name) in enumerate(maps):
        end = maps[idx + 1][0] - 1 if idx + 1 < len(maps) else n
        chunks.append({
            "id": f"{parent_set}/{name}" if parent_set else name,
            "kind": "bms-map", "name": name,
            "start_line": ln, "end_line": end, "parent_id": parent_set,
        })
        parent_map = name
    for ln, name in fields:
        chunks.append({
            "id": f"{parent_set}/{parent_map}/{name}" if parent_set and parent_map else name,
            "kind": "bms-field", "name": name,
            "start_line": ln, "end_line": ln, "parent_id": parent_map,
        })
    return chunks


# ---------- main --------------------------------------------------------

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--source", required=True, help="path relative to source_root or absolute")
    p.add_argument("--source-root", default=None)
    p.add_argument("--output", default=None)
    p.add_argument("--kind-hint", default="auto",
                   choices=["auto", "cobol", "cl", "jcl", "copybook", "bms", "proc"])
    p.add_argument("--platform-hint", default=None,
                   choices=["auto", "mainframe", "ibmi"])
    p.add_argument("--encoding-hint", default=None,
                   choices=["auto", "utf-8", "cp037", "cp1047", "cp1140", "cp1252", "latin-1"])
    args = p.parse_args()

    cfg = yaml.safe_load((REPO_ROOT / "config" / "sources.yaml").read_text(encoding="utf-8"))
    source_root = Path(args.source_root or cfg.get("source_root", "./samples"))
    if not source_root.is_absolute():
        source_root = (REPO_ROOT / source_root).resolve()

    src_arg = Path(args.source)
    if src_arg.is_absolute():
        abs_path = src_arg
    else:
        # Try as-is relative to repo, then relative to source_root.
        cand1 = (REPO_ROOT / src_arg).resolve()
        cand2 = (source_root / src_arg).resolve()
        abs_path = cand1 if cand1.exists() else cand2

    if not abs_path.exists():
        print(f"ERROR: source not found: {abs_path}", file=sys.stderr)
        return 2

    try:
        reported = str(abs_path.relative_to(source_root)).replace("\\", "/")
    except ValueError:
        reported = str(abs_path).replace("\\", "/")

    raw = abs_path.read_bytes()
    encoding_hint = args.encoding_hint or configured_encoding(cfg, reported)
    encoding = detect_encoding(raw) if encoding_hint == "auto" else normalize_encoding(encoding_hint)
    text = raw.decode(encoding, errors="replace")
    # Preserve original line count: splitlines drops the trailing newline
    # but keeps blank lines.
    lines = text.splitlines()
    line_count = len(lines)
    sha = hashlib.sha256(raw).hexdigest()

    ext = abs_path.suffix
    kind = detect_kind(lines, args.kind_hint, ext)
    platform_hint = args.platform_hint or configured_platform(cfg, reported)
    platform = detect_platform(lines, platform_hint, ext)

    errors: list[dict] = []
    if line_count == 0:
        errors.append({"code": "EMPTY_SOURCE", "message": "source has no lines", "line": 0})
        chunks: list[dict] = []
    elif kind == "cobol":
        chunks = chunk_cobol(lines, args.source)
    elif kind == "jcl" or kind == "proc":
        chunks = chunk_jcl(lines, args.source)
        if kind == "proc":
            # treat as proc library — already handled by jcl_proc
            pass
    elif kind == "cl":
        chunks = chunk_cl(lines, args.source)
    elif kind == "copybook":
        chunks = chunk_copybook(lines, args.source)
    elif kind == "bms":
        chunks = chunk_bms(lines, args.source)
    else:
        chunks = []

    # Phase-A invariant: chunk ids must be globally unique within a file.
    # See `_dedupe_chunk_ids` — disambiguates collisions in-place and
    # records each rename on `errors[]`.
    _dedupe_chunk_ids(chunks, errors)

    manifest = {
        "manifest_version": "1.0",
        "source_path": reported,
        "source_kind": kind,
        "source_platform": platform,
        "encoding_detected": encoding,
        "sha256": sha,
        "line_count": line_count,
        "copybooks_expanded": [],
        "chunks": chunks,
        "errors": errors,
    }

    # Validate against schema if jsonschema is available.
    try:
        import jsonschema  # type: ignore
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        jsonschema.validate(manifest, schema)
    except ImportError:
        print("WARN: jsonschema not installed, skipping validation", file=sys.stderr)
    except Exception as e:  # noqa: BLE001
        print(f"SCHEMA VALIDATION FAILED: {e}", file=sys.stderr)
        return 3

    if args.output:
        out = Path(args.output)
    else:
        # Default: docs/_shared/<basename>/chunk-manifest.json where
        # basename = abs_path.name (preserves extension to satisfy the
        # explicit per-file slug used by the orchestrator).
        out = REPO_ROOT / "docs" / "_shared" / abs_path.name / "chunk-manifest.json"
    if not out.is_absolute():
        out = (REPO_ROOT / out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                   encoding="utf-8")

    # Summary by kind.
    by_kind: dict[str, int] = {}
    for c in chunks:
        by_kind[c["kind"]] = by_kind.get(c["kind"], 0) + 1
    summary = ", ".join(f"{k}={v}" for k, v in sorted(by_kind.items()))
    print(f"OK: wrote {out}")
    print(f"chunks: {len(chunks)} ({summary})")
    print(f"lines: {line_count}  encoding: {encoding}  kind: {kind}  "
          f"platform: {platform}  sha: {sha[:12]}…")
    if errors:
        print(f"warnings/errors: {len(errors)}")
        for e in errors:
            print(f"  - [{e['code']}] L{e['line']}: {e['message']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
