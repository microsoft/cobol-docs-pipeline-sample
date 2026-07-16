#!/usr/bin/env python3
"""Build a self-contained portal that can be browsed directly from disk
(``file://``) without a web server.

The standard portal (``scripts/portal/build-portal-static.py``) renders HTML that
loads two kinds of resources lazily with ``fetch()``:

  * the raw source text for the slide-out source panel
    (``_sources/<slug>.txt``), and
  * the per-chunk documentation HTML shown in the two-column source viewer
    (``../<lang>/<bundle>/sections/<...>.html``).

Browsers block ``fetch()`` of local files under the ``file://`` protocol
(CORS / opaque-origin rules), so those features silently break when the
site is opened by double-clicking ``index.html``.

This script produces an *offline* copy of the site in which every page
that needs a fetched resource carries that resource inline, plus a tiny
``fetch`` shim that resolves the request against an embedded store before
falling back to the network. Nothing else about the markup or styling
changes, so the offline copy behaves identically to the served portal.

Usage:
    python ./scripts/portal/build-portal-offline.py
    python ./scripts/portal/build-portal-offline.py --source-root repos/sample1
    python ./scripts/portal/build-portal-offline.py --skip-build   # patch existing site

Output: docs/_portal/site-offline/
  Open docs/_portal/site-offline/index.html in any browser — no server.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DOCS_ROOT = REPO_ROOT / "docs"
PORTAL_ROOT = DOCS_ROOT / "_portal"
DEFAULT_SITE_ROOT = PORTAL_ROOT / "site"
DEFAULT_OUT_ROOT = PORTAL_ROOT / "site-offline"
BUILD_SCRIPT = REPO_ROOT / "scripts" / "portal" / "build-portal-static.py"

PAGE_SOURCES_RE = re.compile(
    r'<script type="application/json" id="page-sources">(.*?)</script>',
    re.DOTALL,
)
SV_DATA_RE = re.compile(
    r'<script type="application/json" id="sv-data">(.*?)</script>',
    re.DOTALL,
)
BODY_OPEN_RE = re.compile(r"(<body\b[^>]*>)", re.IGNORECASE)

# Inline shim installed before the deferred page scripts run. It intercepts
# fetch() of bundled local files and serves them from an embedded store so
# the source panel and source viewer work under file://. The store is keyed
# by site-root-relative posix paths and matched against the resolved request
# pathname by suffix, so the offline folder can be moved or renamed freely.
FETCH_SHIM = """
(function () {
  var dataEl = document.getElementById('__offline_store__');
  if (!dataEl) return;
  var STORE;
  try { STORE = JSON.parse(dataEl.textContent || '{}'); } catch (e) { return; }
  var KEYS = Object.keys(STORE);
  if (!KEYS.length || typeof window.fetch !== 'function') return;
  var orig = window.fetch.bind(window);
  window.fetch = function (input, init) {
    var url = (typeof input === 'string') ? input : (input && input.url) || '';
    try {
      var abs = new URL(url, document.baseURI);
      if (abs.protocol === 'file:') {
        var path = decodeURIComponent(abs.pathname);
        for (var i = 0; i < KEYS.length; i++) {
          var k = KEYS[i];
          if (path === k || path === '/' + k || path.endsWith('/' + k)) {
            var ct = k.slice(-5) === '.html' ? 'text/html' : 'text/plain';
            return Promise.resolve(new Response(STORE[k], {
              status: 200,
              headers: { 'Content-Type': ct + ';charset=utf-8' }
            }));
          }
        }
        return Promise.reject(new Error('offline: resource not bundled (' + path + ')'));
      }
    } catch (e) { /* fall through to network */ }
    return orig(input, init);
  };
})();
"""


def _log(task: str, msg: str = "", t0: float | None = None) -> None:
    elapsed = f" ({time.time() - t0:.1f}s)" if t0 is not None else ""
    suffix = f" — {msg}" if msg else ""
    print(f"[offline] {task}{suffix}{elapsed}", flush=True)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a file://-browsable offline copy of the static portal."
    )
    parser.add_argument(
        "--source-root",
        help="Source tree passed through to build-portal-static.py.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Do not re-run build-portal-static.py; patch the existing site.",
    )
    parser.add_argument(
        "--site",
        default=str(DEFAULT_SITE_ROOT),
        help="Input static site directory (default: docs/_portal/site).",
    )
    parser.add_argument(
        "--out",
        default=str(DEFAULT_OUT_ROOT),
        help="Offline output directory (default: docs/_portal/site-offline).",
    )
    return parser.parse_args(argv)


def run_build(source_root: str | None, t0: float) -> int:
    cmd = [sys.executable, str(BUILD_SCRIPT)]
    if source_root:
        cmd += ["--source-root", source_root]
    _log("task=build", " ".join(cmd[1:]), t0)
    proc = subprocess.run(cmd, cwd=str(REPO_ROOT))
    return proc.returncode


class ResourceStore:
    """Reads and caches site files keyed by their site-root-relative path."""

    def __init__(self, site_root: Path) -> None:
        self.site_root = site_root
        self._cache: dict[str, str | None] = {}

    def read(self, key: str) -> str | None:
        """Return file content for a site-root-relative posix key, or None."""
        if key in self._cache:
            return self._cache[key]
        path = self.site_root / Path(key)
        text: str | None = None
        if path.is_file():
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                text = None
        self._cache[key] = text
        return text


def _rel_key(site_root: Path, page_path: Path, rel_url: str) -> str | None:
    """Resolve a page-relative URL to a site-root-relative posix key."""
    rel_url = rel_url.split("#", 1)[0].split("?", 1)[0]
    if not rel_url:
        return None
    target = (page_path.parent / rel_url).resolve()
    try:
        return target.relative_to(site_root.resolve()).as_posix()
    except ValueError:
        return None


def collect_page_resources(page_path: Path, text: str, site_root: Path,
                           store: ResourceStore) -> dict[str, str]:
    """Return {site_rel_key: content} for every fetchable resource the page
    needs: source-panel text files and source-viewer source + per-chunk docs."""
    bundle: dict[str, str] = {}

    def _add(key: str | None) -> None:
        if not key or key in bundle:
            return
        content = store.read(key)
        if content is not None:
            bundle[key] = content

    # --- Slide-out source panel (per-page citations) --------------------
    m = PAGE_SOURCES_RE.search(text)
    if m:
        try:
            data = json.loads(m.group(1) or "{}")
        except json.JSONDecodeError:
            data = {}
        for cite in data.values():
            slug = cite.get("slug") if isinstance(cite, dict) else None
            if slug:
                _add(f"_sources/{slug}.txt")

    # --- Two-column source viewer --------------------------------------
    m = SV_DATA_RE.search(text)
    if m:
        try:
            data = json.loads(m.group(1) or "{}")
        except json.JSONDecodeError:
            data = {}
        slug = data.get("slug")
        if slug:
            _add(f"_sources/{slug}.txt")
        for chunk in data.get("chunks") or []:
            for url in (chunk.get("docUrls") or {}).values():
                _add(_rel_key(site_root, page_path, url))
        for entries in (data.get("bundleDocs") or {}).values():
            for url in (entries or {}).values():
                _add(_rel_key(site_root, page_path, url))

    return bundle


def patch_page(page_path: Path, site_root: Path, store: ResourceStore) -> bool:
    """Embed needed resources + fetch shim into a single page. Returns True
    when the page was modified."""
    text = page_path.read_text(encoding="utf-8", errors="replace")
    if "__offline_store__" in text:
        return False  # already patched
    bundle = collect_page_resources(page_path, text, site_root, store)
    if not bundle:
        return False

    payload = json.dumps(bundle, ensure_ascii=False).replace("<", "\\u003c")
    injection = (
        f'<script type="application/json" id="__offline_store__">{payload}</script>'
        f"<script>{FETCH_SHIM}</script>"
    )

    def _inject(m: re.Match) -> str:
        return m.group(1) + injection

    new_text, n = BODY_OPEN_RE.subn(_inject, text, count=1)
    if not n:
        new_text = injection + text
    page_path.write_text(new_text, encoding="utf-8")
    return True


def check_mermaid_asset(site_root: Path) -> None:
    """Warn when the bundled Mermaid asset is just a CDN loader stub, which
    would leave diagrams unrendered while fully offline."""
    asset = site_root / "assets" / "mermaid.min.js"
    if asset.is_file() and asset.stat().st_size < 4096:
        _log("task=mermaid",
             "WARNING: assets/mermaid.min.js looks like a CDN loader stub; "
             "diagrams will need internet. Run `npm i mermaid` then rebuild "
             "for fully offline diagrams.")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    t0 = time.time()

    if not args.skip_build:
        rc = run_build(args.source_root, t0)
        if rc != 0:
            _log("task=build", f"FAILED (exit {rc})", t0)
            return rc

    site_root = Path(args.site).resolve()
    out_root = Path(args.out).resolve()
    if not site_root.is_dir():
        _log("task=error", f"site not found: {site_root}")
        return 1
    if out_root == site_root:
        _log("task=error", "--out must differ from --site")
        return 1

    _log("task=copy", f"{site_root} -> {out_root}", t0)
    if out_root.exists():
        shutil.rmtree(out_root, ignore_errors=True)
    shutil.copytree(site_root, out_root)

    check_mermaid_asset(out_root)

    store = ResourceStore(out_root)
    pages = sorted(out_root.rglob("*.html"))
    _log("task=patch", f"scanning {len(pages)} pages", t0)
    patched = 0
    for page in pages:
        try:
            if patch_page(page, out_root, store):
                patched += 1
        except OSError as e:
            _log("task=patch", f"warn: {page.name}: {e}")
        if patched and patched % 200 == 0:
            _log("task=patch", f"progress {patched} patched", t0)
    _log("task=patch", f"patched {patched} of {len(pages)} pages", t0)

    manifest = {
        "offline_root": out_root.relative_to(REPO_ROOT).as_posix()
        if out_root.is_relative_to(REPO_ROOT) else str(out_root),
        "source_site": site_root.relative_to(REPO_ROOT).as_posix()
        if site_root.is_relative_to(REPO_ROOT) else str(site_root),
        "pages_total": len(pages),
        "pages_patched": patched,
        "elapsed_seconds": round(time.time() - t0, 2),
    }
    (out_root / "offline-manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8")

    entry = out_root / "index.html"
    _log("task=DONE", f"open {entry}", t0)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
