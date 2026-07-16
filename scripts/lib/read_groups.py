"""Read top-level groups from a YAML manifest and emit JSON to stdout.

Used by run-docs-group-*-batch.ps1 to avoid embedding Python via string
interpolation. The manifest path is passed as argv[1].
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import yaml  # type: ignore[import-not-found]
except ImportError:  # pragma: no cover
    sys.stderr.write("PyYAML is required: pip install pyyaml\n")
    sys.exit(2)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        sys.stderr.write("usage: read_groups.py <manifest.yaml>\n")
        return 2
    manifest = Path(argv[1])
    if not manifest.is_file():
        sys.stderr.write(f"manifest not found: {manifest}\n")
        return 2
    data = yaml.safe_load(manifest.read_text(encoding="utf-8")) or {}
    out = []
    for group in data.get("groups") or []:
        gid = group.get("id")
        if gid is None:
            continue
        gid = str(gid).strip()
        if not gid:
            continue
        out.append({
            "id": gid,
            "description": group.get("description") or "",
            "members": group.get("members") or [],
        })
    sys.stdout.write(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
