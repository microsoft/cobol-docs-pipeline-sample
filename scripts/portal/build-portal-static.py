#!/usr/bin/env python3
"""Build a self-contained static HTML portal from the generated
Markdown deliverables under docs/{en,it}/.

This bypasses mkdocs entirely. For a 1700+ page workspace mkdocs is
prohibitively slow (templating + plugin overhead per page). This script
uses the python-markdown library directly and renders each page in a
single Jinja-free template literal — finishing in well under a minute.

Output: docs/_portal/site/
  index.html              — landing page (language picker)
  assets/style.css        — single stylesheet
  assets/script.js        — sidebar toggle + mermaid bootstrap
  en/<file>/<doc>.html    — converted pages (one per .md)
  it/<file>/<doc>.html
  _shared/...             — SVG diagrams copied verbatim

Mermaid blocks are emitted as <pre class="mermaid"> and rendered
client-side by mermaid.js (loaded via CDN).
"""
from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import markdown

try:
  import yaml
except ImportError:  # pragma: no cover - optional when --source-root is provided
  yaml = None

REPO_ROOT = Path(__file__).resolve().parents[2]
DOCS_ROOT = REPO_ROOT / "docs"
PORTAL_ROOT = DOCS_ROOT / "_portal"
SITE_ROOT = PORTAL_ROOT / "site"
SHARED_ROOT = DOCS_ROOT / "_shared"
SOURCE_CONFIG_PATH = REPO_ROOT / "config" / "sources.yaml"
DEFAULT_SOURCE_ROOT = REPO_ROOT / "repos" / "sample1"
SOURCES_SITE_DIR = "_sources"
LANGS = ("en", "it")
LANG_LABELS = {"en": "English", "it": "Italiano"}
SHARED_GLOSSARY_MD = DOCS_ROOT / "_glossary.md"
SHARED_PAGES_DIR = "_shared_pages"

# Map of source-file slug (uppercased filename) -> {path, slug, ext}.
# Populated in main() from the resolved source root.
SOURCE_INDEX: dict[str, dict] = {}

# Map of bundle name (folder under docs/<lang>) -> viewer URL relative to SITE_ROOT.
# Populated by write_source_viewer() so sidebar/index pages can link to it.
VIEWER_BY_BUNDLE: dict[str, str] = {}

# Map docs/*.md shared pages to rendered HTML destinations under site/.
SHARED_PAGE_BY_MD: dict[Path, Path] = {}
MERMAID_CDN = "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"

MD_EXTENSIONS = [
    "extra",          # tables, fenced_code, footnotes, attr_list, def_list, abbr
    "toc",
    "sane_lists",
    "admonition",
    "pymdownx.superfences",
    "pymdownx.tilde",
    "pymdownx.details",
]
MD_EXT_CFG = {
    "toc": {"permalink": False},
    "pymdownx.superfences": {
        "custom_fences": [
            {"name": "mermaid", "class": "mermaid",
             "format": lambda src, *a, **kw: f'<pre class="mermaid">{html.escape(src)}</pre>'},
        ],
    },
}

H1_RE = re.compile(r"^\s*#\s+(.+?)\s*$", re.MULTILINE)

# Citation footnote definition. The path may be wrapped on a new line so
# we tolerate intervening whitespace/newlines between ':' and the backtick.
# Single line: L<n>  ; range: L<a>–L<b> (en dash) or L<a>-L<b> (ascii).
CITATION_DEF_RE = re.compile(
    r"^\[\^(src-[^\]]+)\]:\s*\n?\s*`([^`]+)`\s+L(\d+)(?:[\u2013\-]L?(\d+))?"
    r"(?:\s*[\u00b7\-]\s*confidence:\s*([HML]))?",
    re.MULTILINE,
)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
FENCE_RE = re.compile(r"^\s*```")


def strip_hidden_sections(md_text: str) -> str:
    """Remove authoring-only sections from generated pages.

    Hidden headings (case-insensitive):
    - Authoring self-check

    The matched heading and its body are removed until the next heading
    with a level less-than-or-equal to the matched one.

    `## Summary` (formerly `## TL;DR`) is now a published section and is
    NOT stripped.
    """

    def _norm(text: str) -> str:
        text = text.strip().lower()
        text = re.sub(r"[\s\-_:]+", " ", text)
        return text

    def _is_hidden(heading: str) -> bool:
        h = _norm(heading)
        return "authoring self check" in h

    lines = md_text.split("\n")
    out: list[str] = []
    in_fence = False
    skip_level: int | None = None

    for line in lines:
        if FENCE_RE.match(line):
            in_fence = not in_fence
            if skip_level is None:
                out.append(line)
            continue

        m = HEADING_RE.match(line) if not in_fence else None
        if m:
            level = len(m.group(1))
            heading = m.group(2).strip()

            if skip_level is not None and level <= skip_level:
                skip_level = None

            if skip_level is None and _is_hidden(heading):
                skip_level = level
                continue

        if skip_level is None:
            out.append(line)

    return "\n".join(out)


def discover_sources(root: Path) -> dict[str, dict]:
    """Scan the source tree and build an index keyed by uppercase basename
    AND uppercase stem so docs folder names like ``DEMO100`` or
    ``DEMO1.JCL`` both resolve to a file."""
    if not root.is_dir():
        return {}
    index: dict[str, dict] = {}
    exts = {
        ".cbl", ".cob", ".cblle", ".sqlcblle", ".cl", ".clp", ".clle", ".jcl", ".prc",
        ".cpy", ".bms", ".inp",
    }
    for p in root.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in exts:
            continue
        slug = p.name.upper().replace(" ", "_")
        entry = {
            "path": p,
            "slug": slug,
            "name": p.name,
            "ext": p.suffix.lstrip(".").lower(),
            "rel": p.relative_to(REPO_ROOT).as_posix(),
        }
        index.setdefault(p.name.upper(), entry)
        index.setdefault(p.stem.upper(), entry)
    return index


def _resolve_candidate_path(raw_path: str | os.PathLike[str] | None) -> Path | None:
    if not raw_path:
        return None
    path = Path(raw_path)
    if not path.is_absolute():
        path = (REPO_ROOT / path).resolve()
    return path


def resolve_source_root(cli_source_root: str | None) -> Path:
    """Resolve the source tree from CLI, env, config, then legacy fallbacks."""
    candidates: list[Path] = []

    cli_path = _resolve_candidate_path(cli_source_root)
    if cli_path is not None:
        candidates.append(cli_path)

    env_path = _resolve_candidate_path(os.environ.get("SOURCE_ROOT"))
    if env_path is not None:
        candidates.append(env_path)

    if yaml is not None and SOURCE_CONFIG_PATH.is_file():
        try:
            config = yaml.safe_load(SOURCE_CONFIG_PATH.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError):
            config = {}
        config_path = _resolve_candidate_path(config.get("source_root"))
        if config_path is not None:
            candidates.append(config_path)

    candidates.extend([DEFAULT_SOURCE_ROOT, REPO_ROOT / "samples"])
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    return candidates[0]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a static HTML portal from docs/<lang> markdown deliverables."
    )
    parser.add_argument(
        "--source-root",
        help="Source tree used to populate the side-by-side source viewer.",
    )
    return parser.parse_args(argv)


def copy_sources_to_site() -> None:
    """Copy every indexed source file into site/_sources/<slug>.txt so the
    right-side panel can fetch them with a relative URL."""
    dst_dir = SITE_ROOT / SOURCES_SITE_DIR
    dst_dir.mkdir(parents=True, exist_ok=True)
    seen: set[str] = set()
    for entry in SOURCE_INDEX.values():
        slug = entry["slug"]
        if slug in seen:
            continue
        seen.add(slug)
        try:
            text = entry["path"].read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        (dst_dir / f"{slug}.txt").write_text(text, encoding="utf-8")


def resolve_source_for_path(path: str) -> dict | None:
    """Map a citation path like ``samples/COBOL/DEMO100.CBL`` to a source
    index entry. Falls back to basename lookup if the literal rel-path
    doesn't match."""
    name = Path(path).name.upper()
    return SOURCE_INDEX.get(name)


def parse_citations(md_text: str) -> dict[str, dict]:
    """Return {citation_id -> {path, slug, start, end, conf, source_rel}}."""
    out: dict[str, dict] = {}
    for m in CITATION_DEF_RE.finditer(md_text):
        cid, path, start, end, conf = m.groups()
        entry = resolve_source_for_path(path)
        out[cid] = {
            "id": cid,
            "path": path,
            "slug": entry["slug"] if entry else None,
            "source_rel": entry["rel"] if entry else path,
            "start": int(start),
            "end": int(end) if end else int(start),
            "conf": conf or "M",
        }
    return out


def read_title(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return path.stem
    m = H1_RE.search(text)
    return m.group(1).strip() if m else path.stem


def rel_url(target: Path, base: Path) -> str:
    """Compute a relative URL from `base` (a page) to `target` (an asset)."""
    try:
        return Path(*[".."] * (len(base.parent.relative_to(SITE_ROOT).parts))).joinpath(
            target.relative_to(SITE_ROOT)
        ).as_posix()
    except ValueError:
        return target.as_posix()


def md_to_html_path(md_path: Path, lang: str) -> Path:
    """Map a docs/<lang>/<...>.md to its destination under site/<lang>/<...>.html."""
    rel = md_path.relative_to(DOCS_ROOT / lang)
    return SITE_ROOT / lang / rel.with_suffix(".html")


def shared_md_to_html_path(md_path: Path) -> Path:
    """Map docs/_*.md shared pages to site/_shared_pages/*.html."""
    rel = md_path.relative_to(DOCS_ROOT)
    return SITE_ROOT / SHARED_PAGES_DIR / rel.with_suffix(".html").name


def fixup_links(html_body: str, src_md: Path, dst_html: Path) -> str:
    """Rewrite intra-doc links: .md → .html ; ../../../_shared/... paths
    stay relative because we copy _shared/ wholesale into site/_shared/.
    """
    def _rewrite(m: re.Match) -> str:
        prefix, url, suffix = m.group(1), m.group(2), m.group(3)
        if url.startswith(("http://", "https://", "#", "mailto:", "data:")):
            return m.group(0)
        # Strip optional fragment.
        frag = ""
        if "#" in url:
            url, frag = url.split("#", 1)
            frag = "#" + frag
        # Resolve against source md location.
        if url.endswith(".md"):
            try:
                target_md = (src_md.parent / url).resolve()
                target_md.relative_to(DOCS_ROOT)
                rel = target_md.relative_to(DOCS_ROOT)
                if rel.parts and rel.parts[0] in LANGS:
                    target_html = md_to_html_path(target_md, rel.parts[0])
                else:
                    target_html = shared_md_to_html_path(target_md)
                new = Path(*[".."] * (len(dst_html.parent.relative_to(SITE_ROOT).parts))).joinpath(
                    target_html.relative_to(SITE_ROOT)
                ).as_posix()
                return f"{prefix}{new}{frag}{suffix}"
            except (ValueError, OSError):
                return m.group(0)
        return m.group(0)

    # href="..."  and  src="..."
    html_body = re.sub(r'(href=")([^"]+)(")', _rewrite, html_body)
    html_body = re.sub(r'(src=")([^"]+)(")', _rewrite, html_body)
    return html_body


# Wraps standalone <img> in <figure> + <figcaption> derived from alt text.
# Matches both ``<p><img ...></p>`` and ``<p><img ...>caption text</p>``
# emitted by python-markdown when an image is the only inline content.
FIGURE_RE = re.compile(
    r'<p>(\s*<img\b([^>]*?)\s*/?>)\s*</p>',
    re.IGNORECASE,
)
ALT_RE = re.compile(r'\balt="([^"]*)"', re.IGNORECASE)


def figurize_images(html_body: str) -> str:
    """Replace standalone ``<p><img></p>`` with a captioned ``<figure>``.
    The caption is the image's ``alt`` text with a leading ``Diagram:`` /
    ``Diagramma:`` label stripped so it reads as a real didascalia."""
    def _wrap(m: re.Match) -> str:
        img_html = m.group(1)
        attrs = m.group(2)
        alt_m = ALT_RE.search(attrs)
        caption = (alt_m.group(1).strip() if alt_m else "")
        # Strip generator prefix like "Diagram: foo-flow" / "Diagramma: ...".
        caption = re.sub(r'^(diagram(ma)?\s*:\s*)', '', caption, flags=re.IGNORECASE)
        caption = caption.replace('-', ' ').strip()
        if not caption:
            return f'<figure>{img_html}</figure>'
        return (f'<figure>{img_html}'
                f'<figcaption>{html.escape(caption)}</figcaption></figure>')
    return FIGURE_RE.sub(_wrap, html_body)


FOOTNOTE_REF_RE = re.compile(
    r'(<sup\b[^>]*\bid="fnref:(src-[^"]+)"[^>]*>\s*<a\b[^>]*>[^<]*</a>\s*</sup>)',
    re.IGNORECASE,
)


def inject_title_source_link(html_body: str, viewer_url: str | None,
                             has_sources: bool = False) -> str:
    """Inject a small ``source`` control right after the page's first
    ``<h1>``. On pages with the slide-out source panel (``has_sources``)
    the control is a ``<button>`` that opens the panel anchored on the
    current chunk's first citation; on pages without the panel it falls
    back to an ``<a>`` that navigates to the standalone source viewer."""
    if has_sources:
        link = (' <button type="button" class="sv-source-link header-source"'
                ' data-open-panel="title"'
                ' title="Show source for this chunk">source &#x2630;</button>')
    elif viewer_url:
        link = (f' <a class="sv-source-link header-source" href="{html.escape(viewer_url)}"'
                f' title="Open the side-by-side source viewer">source &#x2630;</a>')
    else:
        return html_body

    def _inject(m: re.Match) -> str:
        return m.group(1) + link + m.group(2)

    new_body, n = re.subn(r'(<h1\b[^>]*>.*?)(</h1>)', _inject, html_body,
                         count=1, flags=re.IGNORECASE | re.DOTALL)
    return new_body if n else html_body


def linkify_citation_refs(html_body: str, citations: dict[str, dict],
                          viewer_url: str | None,
                          has_sources: bool = False) -> str:
    """Append a small ``L<n>`` chip next to every ``[^src-N]`` footnote
    reference. On pages with the slide-out source panel the chip is a
    ``<button>`` that opens the panel scrolled to the cited line range;
    on pages without the panel it falls back to an ``<a>`` to the
    standalone source viewer. Keeps the existing footnote behaviour
    intact in both cases."""
    if not citations:
        return html_body
    if not has_sources and not viewer_url:
        return html_body

    def _augment(m: re.Match) -> str:
        sup_html, cid = m.group(1), m.group(2)
        cite = citations.get(cid)
        if not cite or not cite.get("start"):
            return sup_html
        start = cite["start"]
        end = cite.get("end") or start
        label = f"L{start}" if start == end else f"L{start}-L{end}"
        if has_sources:
            chip = (f'<button type="button" class="sv-line-link"'
                    f' data-open-cid="{html.escape(cid)}"'
                    f' title="Show source for this citation (line {start})">{label}</button>')
        else:
            chip = (f'<a class="sv-line-link" href="{html.escape(viewer_url)}#L{start}"'
                    f' target="_blank" rel="noopener"'
                    f' title="Open source viewer at line {start}">{label}</a>')
        return sup_html + chip

    return FOOTNOTE_REF_RE.sub(_augment, html_body)


def page_template(*, title: str, lang: str, body: str, sidebar: str,
                  rel_root: str, sibling_url: str | None,
                  breadcrumb: str, page_sources_json: str,
                  has_sources: bool) -> str:
    """Render the full HTML page."""
    other_lang = "it" if lang == "en" else "en"
    other_label = LANG_LABELS[other_lang]
    sibling_link = (
        f'<a class="lang-toggle" href="{html.escape(sibling_url)}">{other_label}</a>'
        if sibling_url else
        f'<span class="lang-toggle disabled">{other_label}</span>'
    )
    src_toggle = (
        '<button id="src-toggle" class="src-toggle" title="Show source code">'
        '&#x2630; Source</button>' if has_sources else ''
    )
    src_panel = '''
<aside id="source-panel" class="source-panel" hidden>
  <header class="sp-head">
    <span class="sp-title">Source</span>
    <span class="sp-file" id="sp-file">—</span>
    <button id="sp-close" class="sp-close" title="Close">&times;</button>
  </header>
  <div class="sp-citations" id="sp-citations"></div>
  <div class="sp-codewrap"><pre class="sp-code"><code id="sp-code"></code></pre></div>
</aside>''' if has_sources else ''
    page_data = (
        f'<script type="application/json" id="page-sources">{page_sources_json}</script>'
        if has_sources else ''
    )
    return f"""<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} — DEMO COBOL Modernization</title>
<link rel="stylesheet" href="{rel_root}assets/style.css">
</head>
<body>
<header class="topbar">
  <a class="brand" href="{rel_root}index.html">DEMO COBOL Modernization</a>
  <nav class="topnav">
    <a href="{rel_root}{lang}/index.html">{LANG_LABELS[lang]} home</a>
    {sibling_link}
    {src_toggle}
  </nav>
</header>
<div class="layout">
  <aside class="sidebar"><div class="sidebar-inner">{sidebar}</div></aside>
  <main class="content">
    <nav class="breadcrumb">{breadcrumb}</nav>
    <article class="markdown-body">{body}</article>
  </main>
  {src_panel}
</div>
{page_data}
<script>window.__SOURCES_BASE__ = "{rel_root}{SOURCES_SITE_DIR}/";</script>
<script defer src="{rel_root}assets/mermaid.min.js"
    onerror="(function(){{var s=document.createElement('script');s.src='{MERMAID_CDN}';s.defer=true;document.head.appendChild(s);}})();"></script>
<script defer>
window.addEventListener('DOMContentLoaded',function(){{
  function initMermaid(){{
    try{{
      if(window.mermaid && typeof window.mermaid.initialize==='function'){{
        mermaid.initialize({{startOnLoad:false,theme:'default',securityLevel:'loose'}});
        // Manually render all mermaid blocks after init
        var blocks=document.querySelectorAll('pre.mermaid');
        if(blocks.length){{
          if(typeof mermaid.run==='function'){{
            mermaid.run();
          }}
          else if(typeof mermaid.render==='function'){{
            blocks.forEach(function(b){{
              try{{
                var id='mermaid-'+Math.random().toString(36).substr(2,9);
                mermaid.render(id,b.textContent).then(function(r){{b.innerHTML=r.svg;b.removeAttribute('data-mermaid-processed');}});
              }}catch(e){{}}
            }});
          }}
          else if(typeof mermaid.contentLoaderAsync==='function'){{
            mermaid.contentLoaderAsync();
          }}
        }}
      }}
    }}catch(e){{console.error('Mermaid init error:',e);}}
  }}
  // Initialize immediately if loaded, otherwise wait
  if(window.mermaid && typeof window.mermaid.initialize==='function'){{
    initMermaid();
  }}else{{
    // Wait up to 5 seconds for CDN to load
    var attempts=0;
    var waitForMermaid=setInterval(function(){{
      attempts++;
      if(window.mermaid && typeof window.mermaid.initialize==='function'){{
        clearInterval(waitForMermaid);
        initMermaid();
      }}else if(attempts>50){{
        clearInterval(waitForMermaid);
      }}
    }},100);
  }}
}});
</script>
<script src="{rel_root}assets/script.js" defer></script>
</body>
</html>
"""


STYLE_CSS = """
* { box-sizing: border-box; }
body { margin:0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color:#24292f; background:#fff; }
a { color: #0969da; text-decoration: none; }
a:hover { text-decoration: underline; }
.topbar { display:flex; justify-content:space-between; align-items:center; padding:.6rem 1rem; background:#0d1117; color:#fff; position:sticky; top:0; z-index:100; }
.topbar .brand { color:#fff; font-weight:600; font-size:1.05rem; }
.topnav a, .topnav .lang-toggle { color:#c9d1d9; margin-left:1rem; font-size:.9rem; }
.topnav .lang-toggle.disabled { opacity:.4; }
.layout { display:flex; gap:0; min-height: calc(100vh - 46px); }
.sidebar { width:280px; min-width:280px; background:#f6f8fa; border-right:1px solid #d0d7de; overflow-y:auto; max-height: calc(100vh - 46px); }
.content-wrapper { display:flex; flex:1; gap:0; min-width:0; }
.sidebar-inner { padding: 1rem; font-size: .88rem; }
.sidebar h3 { font-size:.78rem; text-transform:uppercase; color:#57606a; margin:1rem 0 .35rem; letter-spacing:.05em; }
.sidebar ul { list-style:none; padding:0; margin:0; }
.sidebar li { padding: 1px 0; }
.sidebar a { display:block; padding: 2px 6px; border-radius:4px; color:#1f2328; }
.sidebar a:hover { background:#eaeef2; text-decoration:none; }
.sidebar a.active { background:#0969da; color:#fff; }
.sidebar details { margin: 2px 0; }
.sidebar details > summary { cursor:pointer; padding: 2px 6px; border-radius:4px; font-weight:600; color:#1f2328; list-style: revert; }
.sidebar details > summary:hover { background:#eaeef2; }
.sidebar details > ul { padding-left: 1rem; }
.sidebar .sec-kind { display:inline-block; }
.sidebar .sec-kind-division { font-weight:600; color:#0550ae; }
.sidebar .sec-kind-section { color:#1f2328; }
.sidebar .sec-kind-paragraph { color:#57606a; }
.sidebar .sec-summary-link { color:#1f2328; text-decoration:none; display:inline; padding:0; }
.sidebar .sec-summary-link:hover { text-decoration:underline; background:transparent; }
.sidebar .sec-empty { color:#8c959f; }
.sidebar .source-code-link { display:block; padding:4px 6px; background:#fff3cd; border:1px solid #ffc107; border-radius:4px; color:#003d00; font-weight:600; margin-bottom:0.5rem; transition:all 0.2s ease; }
.sidebar .source-code-link:hover { background:#ffd966; border-color:#e6b800; text-decoration:none; }
.content { flex:1; padding: 1.5rem 2rem; max-width: 980px; overflow-x:auto; }
.breadcrumb { font-size:.82rem; color:#57606a; margin-bottom:1rem; }
.breadcrumb a { color:#57606a; }
.markdown-body { line-height:1.6; }
.markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4 { margin-top:1.5em; line-height:1.25; }
.markdown-body h1 { border-bottom:1px solid #d0d7de; padding-bottom:.3em; }
.markdown-body h2 { border-bottom:1px solid #d8dee4; padding-bottom:.25em; }
.markdown-body pre { background:#f6f8fa; padding:1rem; border-radius:6px; overflow-x:auto; font-size:.85rem; }
.markdown-body code { background:rgba(175,184,193,.2); padding:.1em .35em; border-radius:4px; font-size:.88em; }
.markdown-body pre code { background:none; padding:0; font-size: inherit; }
.markdown-body table { border-collapse:collapse; margin:1em 0; display:block; overflow-x:auto; }
.markdown-body th, .markdown-body td { border:1px solid #d0d7de; padding:.4em .75em; }
.markdown-body th { background:#f6f8fa; }
.markdown-body img { max-width:100%; }
.markdown-body figure { margin: 1.5em auto; text-align:center; }
.markdown-body figure img { display:inline-block; max-width:100%; }
.markdown-body figcaption { margin-top:.5em; font-size:.85rem; color:#57606a; font-style:italic; }
.markdown-body blockquote { border-left:4px solid #d0d7de; color:#57606a; padding-left:1em; margin: 1em 0; }
.markdown-body .footnote { font-size:.85rem; color:#57606a; border-top:1px solid #d0d7de; padding-top:1em; margin-top:2em; }
.markdown-body .admonition { padding:.75em 1em; border-left:4px solid #0969da; background:#ddf4ff; border-radius:6px; margin:1em 0; }
.markdown-body .admonition-title { font-weight:600; margin-top:0; }
pre.mermaid { background:transparent; padding:0; text-align:center; min-height:220px; }
pre.mermaid svg { max-width:none; }
.mermaid-zoom-shell { border:1px solid #d0d7de; border-radius:8px; background:#fff; margin: .75rem 0 1rem; }
.mermaid-zoom-toolbar { display:flex; align-items:center; gap:.35rem; padding:.35rem .5rem; border-bottom:1px solid #d8dee4; background:#f6f8fa; }
.mermaid-zoom-toolbar button { border:1px solid #d0d7de; background:#fff; border-radius:6px; min-width:28px; height:26px; line-height:1; cursor:pointer; color:#24292f; }
.mermaid-zoom-toolbar button:hover { background:#f3f4f6; }
.mermaid-zoom-level { margin-left:.35rem; font-size:.8rem; color:#57606a; min-width:52px; }
.mermaid-zoom-viewport { overflow:auto; max-height:72vh; padding:.5rem; background:#fff; }
.mermaid-zoom-viewport pre.mermaid { margin:0; min-height:auto; }
.landing { padding: 3rem 2rem; max-width: 880px; margin: 0 auto; }
.landing h1 { font-size: 2rem; }
.landing .lang-cards { display:grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; margin-top:2rem; }
.landing .lang-cards a { display:block; padding:2rem; border:1px solid #d0d7de; border-radius:8px; text-align:center; font-size:1.15rem; }
.landing .lang-cards a:hover { background:#f6f8fa; text-decoration:none; }
.landing ul { columns: 2; }

/* ----- right-side source panel ------------------------------------ */
.src-toggle { margin-left:1rem; background:#21262d; color:#c9d1d9; border:1px solid #30363d; border-radius:6px; padding:.25rem .6rem; cursor:pointer; font-size:.85rem; }
.src-toggle:hover { background:#30363d; color:#fff; }
.src-toggle.active { background:#0969da; border-color:#0969da; color:#fff; }
.src-btn { display:inline-flex; align-items:center; gap:.25em; margin-left:.5em; padding:1px 8px; font-size:.7em; font-weight:500; background:#ddf4ff; color:#0969da; border:1px solid #54aeff66; border-radius:10px; cursor:pointer; vertical-align:middle; text-transform:none; }
.src-btn:hover { background:#0969da; color:#fff; border-color:#0969da; }
.src-btn::before { content:"⟨/⟩"; font-family:'SFMono-Regular',Consolas,monospace; font-size:.85em; }
.source-panel { flex:0 0 380px; display:flex; flex-direction:column; background:#fff; border-left:1px solid #d0d7de; box-shadow:-4px 0 12px rgba(0,0,0,.08); z-index:90; }
.source-panel[hidden] { display:none; }
.source-panel.collapsed { flex:0 0 0; min-width:0; }
.source-panel .sp-head { display:flex; align-items:center; gap:.75rem; padding:.6rem .8rem; background:#f6f8fa; border-bottom:1px solid #d0d7de; }
.source-panel .sp-title { font-weight:600; font-size:.9rem; }
.source-panel .sp-file { flex:1; font-family:'SFMono-Regular',Consolas,monospace; font-size:.82rem; color:#57606a; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.source-panel .sp-close { background:none; border:none; font-size:1.3rem; cursor:pointer; color:#57606a; padding:0 .5rem; line-height:1; }
.source-panel .sp-close:hover { color:#cf222e; }
.source-panel .sp-citations { padding:.4rem .6rem; border-bottom:1px solid #d8dee4; max-height:120px; overflow-y:auto; display:flex; flex-wrap:wrap; gap:.3rem; background:#f6f8fa; }
.source-panel .sp-citations:empty { display:none; }
.source-panel .sp-citations button { background:#fff; border:1px solid #d0d7de; border-radius:4px; padding:2px 8px; font-size:.78rem; cursor:pointer; font-family:'SFMono-Regular',Consolas,monospace; }
.source-panel .sp-citations button:hover { background:#ddf4ff; border-color:#54aeff; }
.source-panel .sp-citations button.active { background:#0969da; border-color:#0969da; color:#fff; }
.source-panel .sp-codewrap { flex:1; overflow:auto; background:#fafbfc; min-height:200px; }
.source-panel .sp-code { margin:0; padding:0; background:none; font-size:.78rem; line-height:1.45; min-height:160px; }
.source-panel .sp-code .ln { display:inline-block; width:5ch; padding:0 .75em 0 .5em; margin-right:.5em; color:#8c959f; background:#f0f3f6; border-right:1px solid #d8dee4; text-align:right; user-select:none; }
.source-panel .sp-code .row { display:block; white-space:pre; }
.source-panel .sp-code .row.hl { background:#fff8c5; }
.source-panel .sp-code .row.hl-edge { background:#fff8c5; box-shadow:inset 3px 0 0 #d4a72c; }
.source-panel .sp-loading, .source-panel .sp-empty, .source-panel .sp-error { padding:1.5rem; color:#57606a; text-align:center; font-size:.9rem; }
.source-panel .sp-error { color:#cf222e; }

@media (max-width: 900px) {
  .sidebar { display:none; }
  .content { padding:1rem; }
  .landing .lang-cards { grid-template-columns: 1fr; }
  .source-panel { flex:0 0 100%; }
}

/* ----- source viewer (two-column) ----------------------------------- */
body.sv-body { display:flex; flex-direction:column; height:100vh; margin:0; overflow:hidden; }
.sv-toolbar { display:flex; align-items:center; gap:1rem; padding:.5rem .8rem; background:#f6f8fa; border-bottom:1px solid #d0d7de; flex-wrap:wrap; font-size:.85rem; }
.sv-toolbar .sv-meta { display:flex; align-items:baseline; gap:.5rem; }
.sv-toolbar .sv-path { font-family:'SFMono-Regular',Consolas,monospace; font-size:.78rem; color:#57606a; background:none; }
.sv-toolbar .sv-chunk-picker { display:flex; align-items:center; gap:.4rem; }
.sv-toolbar select { font-size:.85rem; padding:.15rem .35rem; border:1px solid #d0d7de; border-radius:4px; max-width:30rem; background:#fff; }
.sv-toolbar .sv-lang-switch { margin-left:auto; display:flex; gap:.25rem; }
.sv-toolbar .sv-lang-switch button { background:#fff; border:1px solid #d0d7de; padding:.2rem .6rem; border-radius:4px; cursor:pointer; font-size:.8rem; }
.sv-toolbar .sv-lang-switch button.active { background:#0969da; border-color:#0969da; color:#fff; }
.sv-bundle-docs { padding:.4rem .8rem; background:#fafbfc; border-bottom:1px solid #d8dee4; font-size:.8rem; display:flex; gap:.5rem; flex-wrap:wrap; }
.sv-bundle-docs:empty { display:none; }
.sv-bundle-docs a { padding:1px 8px; border:1px solid #d0d7de; border-radius:10px; background:#fff; }
.sv-bundle-docs a:hover { background:#ddf4ff; border-color:#54aeff; text-decoration:none; }
.sv-layout { flex:1; display:grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); min-height:0; }
.sv-left, .sv-right { min-width:0; min-height:0; overflow:hidden; display:flex; flex-direction:column; background:#fff; }
.sv-left { border-right:1px solid #d0d7de; background:#fafbfc; }
.sv-code { flex:1; margin:0; padding:0; overflow:auto; background:#fafbfc; font-size:.78rem; line-height:1.45; border-radius:0; }
.sv-code .row { display:block; white-space:pre; }
.sv-code .row:hover { background:#eaeef2; cursor:pointer; }
.sv-code .row .ln { display:inline-block; width:6ch; padding:0 .75em 0 .5em; margin-right:.5em; color:#8c959f; background:#f0f3f6; border-right:1px solid #d8dee4; text-align:right; user-select:none; }
.sv-code .row.chunk-hover { background:#fff8c5; }
.sv-code .row.chunk-hover.chunk-edge { box-shadow:inset 3px 0 0 #d4a72c; }
.sv-code .row.chunk-active { background:#ddf4ff; }
.sv-code .row.chunk-active.chunk-edge { box-shadow:inset 3px 0 0 #0969da; }
.sv-code .row.chunk-active.chunk-hover { background:#cae7ff; }
.sv-doc-head { display:flex; align-items:center; gap:.75rem; padding:.5rem .8rem; background:#f6f8fa; border-bottom:1px solid #d0d7de; font-size:.85rem; }
.sv-doc-head #sv-doc-title { flex:1; font-weight:600; color:#1f2328; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.sv-doc-open { font-size:.78rem; padding:1px 8px; border:1px solid #d0d7de; border-radius:10px; background:#fff; color:#0969da; }
.sv-doc-open:hover { background:#ddf4ff; text-decoration:none; }
.sv-doc-body { flex:1; overflow:auto; padding:1rem 1.5rem; }
.sv-doc-body .sv-empty, .sv-doc-body .sv-loading, .sv-doc-body .sv-error { color:#57606a; padding:1rem; font-style:italic; }
.sv-doc-body .sv-error { color:#cf222e; font-style:normal; }
.sv-source-link { display:inline-flex; align-items:center; gap:.25rem; margin-left:.5em; padding:1px 8px; font-size:.7em; font-weight:500; background:#fff8c5; color:#7d4e00; border:1px solid #d4a72c66; border-radius:10px; text-transform:none; }
.sv-source-link:hover { background:#d4a72c; color:#fff; border-color:#d4a72c; text-decoration:none; }
.markdown-body h1 .sv-source-link.header-source { font-size:.45em; vertical-align:middle; font-weight:500; }
.markdown-body .sv-line-link { display:inline-block; margin-left:.15em; padding:0 .35em; font-size:.72em; font-family:'SFMono-Regular',Consolas,monospace; background:#eaeef2; color:#0969da; border:1px solid #d0d7de; border-radius:8px; line-height:1.45; text-decoration:none; vertical-align:baseline; }
.markdown-body .sv-line-link:hover { background:#0969da; color:#fff; border-color:#0969da; text-decoration:none; }
button.sv-source-link, button.sv-line-link { cursor:pointer; font-family:inherit; }
button.sv-line-link { font-family:'SFMono-Regular',Consolas,monospace; }
@media (max-width: 900px) {
  .sv-layout { grid-template-columns: 1fr; grid-template-rows: 50vh 1fr; }
  .sv-left { border-right:none; border-bottom:1px solid #d0d7de; }
}
"""

SCRIPT_JS = r"""
// Auto-setup layout if missing: wrap .content in .content-wrapper
window.addEventListener('DOMContentLoaded', function(){
  var wrapper = document.querySelector('.content-wrapper');
  if (!wrapper) {
    wrapper = document.createElement('div');
    wrapper.className = 'content-wrapper';
    var content = document.querySelector('.content');
    if (content && content.parentNode) {
      content.parentNode.insertBefore(wrapper, content);
      wrapper.appendChild(content);
    }
  }
  
  // Auto-create source-panel if missing
  var panel = document.getElementById('source-panel');
  if (!panel) {
    panel = document.createElement('div');
    panel.id = 'source-panel';
    panel.className = 'source-panel';
    panel.hidden = true;
    panel.innerHTML = '<div class="sp-head"><span class="sp-title">Source</span><span id="sp-file" class="sp-file"></span><button id="sp-close" class="sp-close">✕</button></div><div id="sp-citations" class="sp-citations"></div><div class="sp-codewrap"><pre id="sp-code" class="sp-code"></pre></div>';
    var layout = document.querySelector('.layout');
    if (layout) layout.appendChild(panel);
  }
  
  // Highlight active sidebar entry & auto-expand ancestors
  var here = location.pathname.split('/').pop();
  document.querySelectorAll('.sidebar a').forEach(function(a){
    if (a.getAttribute('href') && a.getAttribute('href').split('/').pop() === here) {
      a.classList.add('active');
      var p = a.parentElement;
      while (p) {
        if (p.tagName === 'DETAILS') p.open = true;
        p = p.parentElement;
      }
      a.scrollIntoView({block:'center'});
    }
  });
});

function attachMermaidZoom(root){
    var scope = root || document;
    var blocks = scope.querySelectorAll('pre.mermaid');
    blocks.forEach(function(pre){
        if (pre.dataset.zoomReady === '1') return;
        var svg = pre.querySelector('svg');
        if (!svg) return;

        pre.dataset.zoomReady = '1';

        var shell = document.createElement('div');
        shell.className = 'mermaid-zoom-shell';
        var toolbar = document.createElement('div');
        toolbar.className = 'mermaid-zoom-toolbar';
        var viewport = document.createElement('div');
        viewport.className = 'mermaid-zoom-viewport';

        var minus = document.createElement('button');
        minus.type = 'button';
        minus.title = 'Zoom out';
        minus.textContent = '−';
        var plus = document.createElement('button');
        plus.type = 'button';
        plus.title = 'Zoom in';
        plus.textContent = '+';
        var reset = document.createElement('button');
        reset.type = 'button';
        reset.title = 'Reset zoom';
        reset.textContent = 'Reset';
        var level = document.createElement('span');
        level.className = 'mermaid-zoom-level';

        var scale = 1;
        function applyZoom(){
            var targetSvg = pre.querySelector('svg');
            if (!targetSvg) return;
            targetSvg.style.transformOrigin = 'top left';
            targetSvg.style.transform = 'scale(' + scale + ')';
            level.textContent = Math.round(scale * 100) + '%';
        }
        function step(delta){
            scale = Math.max(0.3, Math.min(3, Math.round((scale + delta) * 100) / 100));
            applyZoom();
        }

        minus.addEventListener('click', function(){ step(-0.1); });
        plus.addEventListener('click', function(){ step(0.1); });
        reset.addEventListener('click', function(){ scale = 1; applyZoom(); });
        viewport.addEventListener('wheel', function(ev){
            if (!ev.ctrlKey) return;
            ev.preventDefault();
            step(ev.deltaY > 0 ? -0.1 : 0.1);
        }, {passive:false});

        var originalParent = pre.parentNode;
        toolbar.appendChild(minus);
        toolbar.appendChild(plus);
        toolbar.appendChild(reset);
        toolbar.appendChild(level);
        shell.appendChild(toolbar);
        shell.appendChild(viewport);
        originalParent.insertBefore(shell, pre);
        viewport.appendChild(pre);
        applyZoom();
    });
}

window.addEventListener('DOMContentLoaded', function(){
    // Mermaid may render asynchronously after DOM load, so retry briefly.
    var tries = 0;
    var t = setInterval(function(){
        attachMermaidZoom(document);
        tries += 1;
        if (tries > 30) clearInterval(t);
    }, 200);
});

// -------- right-side source panel ---------------------------------
window.addEventListener('DOMContentLoaded', function(){
  var dataEl = document.getElementById('page-sources');
  if (!dataEl) return;
  var sources;
  try { sources = JSON.parse(dataEl.textContent || '{}'); }
  catch (e) { return; }
  if (!sources || !Object.keys(sources).length) return;

  var panel    = document.getElementById('source-panel');
  var toggle   = document.getElementById('src-toggle');
  var closeBtn = document.getElementById('sp-close');
  var fileEl   = document.getElementById('sp-file');
  var citesEl  = document.getElementById('sp-citations');
  var codeEl   = document.getElementById('sp-code');
  if (!panel) return;
  
  // Auto-create toggle button if missing
  if (!toggle) {
    toggle = document.createElement('button');
    toggle.id = 'src-toggle';
    toggle.className = 'src-toggle';
    toggle.textContent = '⟨/⟩';
    toggle.title = 'Show source code';
    var topnav = document.querySelector('.topnav');
    if (topnav) topnav.insertBefore(toggle, topnav.firstChild);
  }
  
  // Get fresh references after potential auto-creation
  closeBtn = document.getElementById('sp-close');
  fileEl = document.getElementById('sp-file');
  citesEl = document.getElementById('sp-citations');
  codeEl = document.getElementById('sp-code');

  var SOURCES_BASE = window.__SOURCES_BASE__ || '_sources/';
  var loaded = {};       // slug -> array of lines
  var currentSlug = null;
  var activeCid = null;

  function htmlEscape(s){
    return s.replace(/[&<>]/g, function(c){
      return c==='&'?'&amp;':c==='<'?'&lt;':'&gt;';
    });
  }

    function attachMermaidZoom(root){
        var scope = root || document;
        var blocks = scope.querySelectorAll('pre.mermaid');
        blocks.forEach(function(pre){
            if (pre.dataset.zoomReady === '1') return;
            var svg = pre.querySelector('svg');
            if (!svg) return;

            pre.dataset.zoomReady = '1';
            var shell = document.createElement('div');
            shell.className = 'mermaid-zoom-shell';
            var toolbar = document.createElement('div');
            toolbar.className = 'mermaid-zoom-toolbar';
            var viewport = document.createElement('div');
            viewport.className = 'mermaid-zoom-viewport';

            var minus = document.createElement('button');
            minus.type = 'button';
            minus.title = 'Zoom out';
            minus.textContent = '−';
            var plus = document.createElement('button');
            plus.type = 'button';
            plus.title = 'Zoom in';
            plus.textContent = '+';
            var reset = document.createElement('button');
            reset.type = 'button';
            reset.title = 'Reset zoom';
            reset.textContent = 'Reset';
            var level = document.createElement('span');
            level.className = 'mermaid-zoom-level';

            var scale = 1;
            function applyZoom(){
                var targetSvg = pre.querySelector('svg');
                if (!targetSvg) return;
                targetSvg.style.transformOrigin = 'top left';
                targetSvg.style.transform = 'scale(' + scale + ')';
                level.textContent = Math.round(scale * 100) + '%';
            }
            function step(delta){
                scale = Math.max(0.3, Math.min(3, Math.round((scale + delta) * 100) / 100));
                applyZoom();
            }

            minus.addEventListener('click', function(){ step(-0.1); });
            plus.addEventListener('click', function(){ step(0.1); });
            reset.addEventListener('click', function(){ scale = 1; applyZoom(); });
            viewport.addEventListener('wheel', function(ev){
                if (!ev.ctrlKey) return;
                ev.preventDefault();
                step(ev.deltaY > 0 ? -0.1 : 0.1);
            }, {passive:false});

            var originalParent = pre.parentNode;
            toolbar.appendChild(minus);
            toolbar.appendChild(plus);
            toolbar.appendChild(reset);
            toolbar.appendChild(level);
            shell.appendChild(toolbar);
            shell.appendChild(viewport);
            originalParent.insertBefore(shell, pre);
            viewport.appendChild(pre);
            applyZoom();
        });
    }

  function renderCitations(){
    citesEl.innerHTML = '';
    Object.keys(sources).sort(function(a,b){
      var na = parseInt(a.replace(/^src-/,''),10);
      var nb = parseInt(b.replace(/^src-/,''),10);
      return na - nb;
    }).forEach(function(cid){
      var c = sources[cid];
      var btn = document.createElement('button');
      var label = (c.start === c.end) ? ('L' + c.start) : ('L' + c.start + '-L' + c.end);
      btn.textContent = cid.replace(/^src-/,'§') + ' · ' + label;
      btn.title = c.source_rel + ' · confidence ' + c.conf;
      btn.dataset.cid = cid;
      btn.addEventListener('click', function(){ showCitation(cid); });
      citesEl.appendChild(btn);
    });
  }

  function renderSourceLines(slug){
    var lines = loaded[slug] || [];
    var frag = document.createDocumentFragment();
    for (var i = 0; i < lines.length; i++) {
      var row = document.createElement('span');
      row.className = 'row';
      row.id = 'L' + (i+1);
      row.innerHTML = '<span class="ln">' + (i+1) + '</span>' + htmlEscape(lines[i]);
      frag.appendChild(row);
    }
    codeEl.innerHTML = '';
    codeEl.appendChild(frag);
  }

  function highlightRange(start, end){
    codeEl.querySelectorAll('.row.hl, .row.hl-edge').forEach(function(r){
      r.classList.remove('hl','hl-edge');
    });
    for (var i = start; i <= end; i++) {
      var row = codeEl.querySelector('#L' + i);
      if (row) {
        row.classList.add('hl');
        if (i === start) row.classList.add('hl-edge');
      }
    }
    var first = codeEl.querySelector('#L' + start);
    if (first) first.scrollIntoView({block:'center', behavior:'smooth'});
  }

  function setActiveButton(cid){
    citesEl.querySelectorAll('button').forEach(function(b){
      b.classList.toggle('active', b.dataset.cid === cid);
    });
  }

  function showCitation(cid){
    var c = sources[cid];
    if (!c) return;
    activeCid = cid;
    setActiveButton(cid);
    if (!c.slug) {
      codeEl.innerHTML = '<div class="sp-error">Source file not bundled: ' + htmlEscape(c.source_rel) + '</div>';
      fileEl.textContent = c.source_rel;
      return;
    }
    fileEl.textContent = c.source_rel + ' · L' + c.start + (c.end !== c.start ? '-L' + c.end : '');
    if (currentSlug === c.slug && loaded[c.slug]) {
      highlightRange(c.start, c.end);
      return;
    }
    if (loaded[c.slug]) {
      currentSlug = c.slug;
      renderSourceLines(c.slug);
      highlightRange(c.start, c.end);
      return;
    }
    codeEl.innerHTML = '<div class="sp-loading">Loading…</div>';
    fetch(SOURCES_BASE + c.slug + '.txt')
      .then(function(r){ if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function(txt){
        loaded[c.slug] = txt.split(/\r?\n/);
        currentSlug = c.slug;
        renderSourceLines(c.slug);
        highlightRange(c.start, c.end);
      })
      .catch(function(e){
        codeEl.innerHTML = '<div class="sp-error">Failed to load source (' + e.message + ').</div>';
      });
  }

  function openPanel(initialCid){
    panel.hidden = false;
    toggle.classList.add('active');
    if (!citesEl.childElementCount) renderCitations();
    var cid = initialCid || activeCid || Object.keys(sources).sort()[0];
    showCitation(cid);
  }
  function closePanel(){
    panel.hidden = true;
    toggle.classList.remove('active');
  }

  toggle.addEventListener('click', function(){
    if (panel.hidden) openPanel(); else closePanel();
  });
  if (closeBtn) closeBtn.addEventListener('click', closePanel);
  document.addEventListener('keydown', function(e){
    if (e.key === 'Escape' && !panel.hidden) closePanel();
  });

  // Convert heading <span class="src-anchor"> markers into clickable buttons.
  document.querySelectorAll('.markdown-body .src-anchor').forEach(function(span){
    var ids = (span.dataset.ids || '').split(',').filter(Boolean);
    if (!ids.length) return;
    var btn = document.createElement('button');
    btn.className = 'src-btn';
    btn.type = 'button';
    btn.textContent = 'source';
    btn.title = 'Show source for this section (' + ids.join(', ') + ')';
    btn.addEventListener('click', function(ev){
      ev.preventDefault();
      openPanel(ids[0]);
    });
    span.replaceWith(btn);
  });

  // Hijack in-page "source" / "L<n>" chips to open the slide-out panel
  // instead of navigating away to the standalone source viewer.
  document.querySelectorAll('[data-open-cid]').forEach(function(el){
    el.addEventListener('click', function(ev){
      ev.preventDefault();
      openPanel(el.dataset.openCid);
    });
  });
  document.querySelectorAll('[data-open-panel="title"]').forEach(function(el){
    el.addEventListener('click', function(ev){
      ev.preventDefault();
      openPanel();
    });
  });
}); // end DOMContentLoaded for source panel
"""

SOURCE_VIEWER_JS = r"""
// Two-column source viewer. Loads viewer payload, source text, and
// fetches per-chunk documentation HTML on demand.
(function(){
  var dataEl = document.getElementById('sv-data');
  if (!dataEl) return;
  var data;
  try { data = JSON.parse(dataEl.textContent || '{}'); } catch (e) { return; }
  if (!data || !data.chunks || !data.chunks.length) return;

  var pathEl   = document.getElementById('sv-path');
  var codeEl   = document.getElementById('sv-code');
  var selEl    = document.getElementById('sv-chunk-select');
  var langEl   = document.getElementById('sv-lang-switch');
  var docsEl   = document.getElementById('sv-bundle-docs');
  var titleEl  = document.getElementById('sv-doc-title');
  var openEl   = document.getElementById('sv-doc-open');
  var docBody  = document.getElementById('sv-doc-body');
  if (!codeEl || !selEl || !langEl) return;

  var SOURCES_BASE = window.__SOURCES_BASE__ || '';
  var langs = data.langs || ['en','it'];
  var labels = data.langLabels || {};
  var savedLang = null;
  try { savedLang = localStorage.getItem('org-viewer-lang'); } catch(e){}
  var currentLang = (savedLang && langs.indexOf(savedLang) >= 0) ? savedLang : langs[0];
    var stateKey = 'org-viewer-state:' + (data.bundle || 'default');
    var savedState = null;
    try { savedState = JSON.parse(sessionStorage.getItem(stateKey) || 'null'); } catch(e) {}
  var activeChunkId = null;
  var sourceLines = null;
  var rowByLine = {};
  var docCache = {};  // url -> html string
    var chunkByDocUrl = {};  // absolute doc url (without hash) -> chunk id

  function htmlEscape(s){
    return s.replace(/[&<>]/g, function(c){
      return c==='&'?'&amp;':c==='<'?'&lt;':'&gt;';
    });
  }

    function attachMermaidZoom(root){
        var scope = root || document;
        var blocks = scope.querySelectorAll('pre.mermaid');
        blocks.forEach(function(pre){
            if (pre.dataset.zoomReady === '1') return;
            var svg = pre.querySelector('svg');
            if (!svg) return;

            pre.dataset.zoomReady = '1';
            var shell = document.createElement('div');
            shell.className = 'mermaid-zoom-shell';
            var toolbar = document.createElement('div');
            toolbar.className = 'mermaid-zoom-toolbar';
            var viewport = document.createElement('div');
            viewport.className = 'mermaid-zoom-viewport';

            var minus = document.createElement('button');
            minus.type = 'button';
            minus.title = 'Zoom out';
            minus.textContent = '−';
            var plus = document.createElement('button');
            plus.type = 'button';
            plus.title = 'Zoom in';
            plus.textContent = '+';
            var reset = document.createElement('button');
            reset.type = 'button';
            reset.title = 'Reset zoom';
            reset.textContent = 'Reset';
            var level = document.createElement('span');
            level.className = 'mermaid-zoom-level';

            var scale = 1;
            function applyZoom(){
                var targetSvg = pre.querySelector('svg');
                if (!targetSvg) return;
                targetSvg.style.transformOrigin = 'top left';
                targetSvg.style.transform = 'scale(' + scale + ')';
                level.textContent = Math.round(scale * 100) + '%';
            }
            function step(delta){
                scale = Math.max(0.3, Math.min(3, Math.round((scale + delta) * 100) / 100));
                applyZoom();
            }

            minus.addEventListener('click', function(){ step(-0.1); });
            plus.addEventListener('click', function(){ step(0.1); });
            reset.addEventListener('click', function(){ scale = 1; applyZoom(); });
            viewport.addEventListener('wheel', function(ev){
                if (!ev.ctrlKey) return;
                ev.preventDefault();
                step(ev.deltaY > 0 ? -0.1 : 0.1);
            }, {passive:false});

            var originalParent = pre.parentNode;
            toolbar.appendChild(minus);
            toolbar.appendChild(plus);
            toolbar.appendChild(reset);
            toolbar.appendChild(level);
            shell.appendChild(toolbar);
            shell.appendChild(viewport);
            originalParent.insertBefore(shell, pre);
            viewport.appendChild(pre);
            applyZoom();
        });
    }

  if (pathEl) pathEl.textContent = data.sourceRel || data.sourceUrl;

  // ---- Language switch buttons -----------------------------------
  langs.forEach(function(lang){
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = labels[lang] || lang.toUpperCase();
    btn.dataset.lang = lang;
    if (lang === currentLang) btn.classList.add('active');
    btn.addEventListener('click', function(){ setLang(lang); });
    langEl.appendChild(btn);
  });

  function setLang(lang){
    if (lang === currentLang) return;
    currentLang = lang;
    try { localStorage.setItem('org-viewer-lang', lang); } catch(e){}
    Array.prototype.forEach.call(langEl.children, function(b){
      b.classList.toggle('active', b.dataset.lang === lang);
    });
    renderBundleDocs();
    if (activeChunkId) {
      var c = chunkById(activeChunkId);
      if (c) loadChunkDoc(c);
    }
  }

  // ---- Bundle-level doc links ------------------------------------
  function renderBundleDocs(){
    if (!docsEl) return;
    var bd = (data.bundleDocs || {})[currentLang] || {};
    docsEl.innerHTML = '';
    Object.keys(bd).forEach(function(label){
      var a = document.createElement('a');
      a.href = bd[label];
      a.textContent = label;
      a.target = '_blank';
      a.rel = 'noopener';
      docsEl.appendChild(a);
    });
  }
  renderBundleDocs();

  // ---- Populate chunk selector (grouped by kind) -----------------
  var chunksById = {};
  data.chunks.forEach(function(c){ chunksById[c.id] = c; });
  function chunkById(id){ return chunksById[id]; }
    data.chunks.forEach(function(c){
        var docUrls = c.docUrls || {};
        Object.keys(docUrls).forEach(function(lang){
            var rel = docUrls[lang];
            try {
                var abs = new URL(rel, location.href).href.split('#')[0];
                if (!chunkByDocUrl[abs]) chunkByDocUrl[abs] = c.id;
            } catch (e) {}
        });
    });

    function chunkForDocUrl(url){
        try {
            var abs = new URL(url, location.href).href.split('#')[0];
            var id = chunkByDocUrl[abs];
            return id ? chunkById(id) : null;
        } catch (e) {
            return null;
        }
    }

  var groups = {};
  data.chunks.forEach(function(c){
    var k = c.kind || 'other';
    (groups[k] = groups[k] || []).push(c);
  });
  Object.keys(groups).sort().forEach(function(kind){
    var og = document.createElement('optgroup');
    og.label = kind + ' (' + groups[kind].length + ')';
    groups[kind].sort(function(a,b){ return a.start - b.start; }).forEach(function(c){
      var opt = document.createElement('option');
      opt.value = c.id;
      opt.textContent = c.name + '  (L' + c.start + '-L' + c.end + ')';
      og.appendChild(opt);
    });
    selEl.appendChild(og);
  });
  selEl.addEventListener('change', function(){
    var c = chunkById(selEl.value);
    if (c) activateChunk(c, true);
  });

  // ---- Find chunk for a given source line (innermost = smallest) -
  function chunkForLine(line){
    var best = null;
    for (var i = 0; i < data.chunks.length; i++) {
      var c = data.chunks[i];
      if (line >= c.start && line <= c.end) {
        if (!best || (c.end - c.start) < (best.end - best.start)) best = c;
      }
    }
    return best;
  }

  // ---- Highlight helpers -----------------------------------------
  function clearClass(cls){
    var els = codeEl.querySelectorAll('.row.' + cls);
    for (var i = 0; i < els.length; i++) {
      els[i].classList.remove(cls);
      els[i].classList.remove('chunk-edge');
    }
  }
  function applyClass(chunk, cls){
    for (var i = chunk.start; i <= chunk.end; i++) {
      var row = rowByLine[i];
      if (!row) continue;
      row.classList.add(cls);
      if (i === chunk.start) row.classList.add('chunk-edge');
    }
  }
  function highlightHover(chunk){
    clearClass('chunk-hover');
    if (chunk) applyClass(chunk, 'chunk-hover');
  }
  function highlightActive(chunk){
    clearClass('chunk-active');
    if (chunk) {
      applyClass(chunk, 'chunk-active');
    }
  }

  // ---- Render source code ----------------------------------------
  function renderCode(text){
    sourceLines = text.split(/\r?\n/);
    var frag = document.createDocumentFragment();
    for (var i = 0; i < sourceLines.length; i++) {
      var line = i + 1;
      var row = document.createElement('span');
      row.className = 'row';
      row.dataset.line = line;
      row.innerHTML = '<span class="ln">' + line + '</span>' + htmlEscape(sourceLines[i]);
      frag.appendChild(row);
      rowByLine[line] = row;
    }
    codeEl.innerHTML = '';
    codeEl.appendChild(frag);

    codeEl.addEventListener('mouseover', function(ev){
      var row = ev.target.closest('.row');
      if (!row) return;
      var line = parseInt(row.dataset.line, 10);
      var c = chunkForLine(line);
      highlightHover(c);
    });
    codeEl.addEventListener('mouseleave', function(){ highlightHover(null); });
    codeEl.addEventListener('click', function(ev){
      var row = ev.target.closest('.row');
      if (!row) return;
      var line = parseInt(row.dataset.line, 10);
      var c = chunkForLine(line);
      if (c) activateChunk(c, false);
    });
  }

  // ---- Activate chunk (sync select + load doc) -------------------
  function activateChunk(chunk, scrollCode){
    if (!chunk) return;
    activeChunkId = chunk.id;
        try { sessionStorage.setItem(stateKey, JSON.stringify({chunkId: activeChunkId, lang: currentLang})); } catch(e) {}
    if (selEl.value !== chunk.id) selEl.value = chunk.id;
    highlightActive(chunk);
    if (scrollCode) {
      var row = rowByLine[chunk.start];
      if (row) row.scrollIntoView({block:'center', behavior:'smooth'});
    }
    loadChunkDoc(chunk);
  }

  // ---- Load and inject per-chunk documentation -------------------
  function loadChunkDoc(chunk){
        var docMap = (chunk.docUrls || {});
        var url = docMap[currentLang];
        var effectiveLang = currentLang;
        if (!url) {
            var alt = langs.find(function(l){ return docMap[l]; });
            if (alt) {
                url = docMap[alt];
                effectiveLang = alt;
            }
        }
    titleEl.textContent = chunk.name + '  ·  ' + chunk.kind +
      '  (L' + chunk.start + '-L' + chunk.end + ')';
    if (!url) {
            var altLang = langs.find(function(l){ return docMap[l]; });
      if (altLang) {
        docBody.innerHTML = '<p class="sv-empty">No documentation in ' +
          (labels[currentLang] || currentLang) + ' — try ' +
          (labels[altLang] || altLang) + '.</p>';
      } else {
        docBody.innerHTML = '<p class="sv-empty">No per-chunk documentation available for this chunk.</p>';
      }
      openEl.hidden = true;
      return;
    }
        if (effectiveLang !== currentLang) {
            titleEl.textContent += '  ·  ' + (labels[effectiveLang] || effectiveLang).toUpperCase();
        }
    openEl.hidden = false;
    openEl.href = url;
    if (docCache[url]) {
      injectDoc(docCache[url], url);
      return;
    }
    docBody.innerHTML = '<p class="sv-loading">Loading…</p>';
    fetch(url)
      .then(function(r){ if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function(html){
        var parser = new DOMParser();
        var doc = parser.parseFromString(html, 'text/html');
        var article = doc.querySelector('article.markdown-body');
        var inner = article ? article.innerHTML : html;
        docCache[url] = inner;
        injectDoc(inner, url);
      })
      .catch(function(e){
        docBody.innerHTML = '<p class="sv-error">Failed to load documentation: ' + e.message + '</p>';
      });
  }

  function injectDoc(inner, baseUrl){
    docBody.innerHTML = inner;
    // Rewrite relative URLs in <img>, <a> so they resolve from viewer location.
    var base = new URL(baseUrl, location.href);
    docBody.querySelectorAll('img[src], a[href]').forEach(function(el){
      var attr = el.tagName === 'IMG' ? 'src' : 'href';
      var v = el.getAttribute(attr);
      if (!v || /^(https?:|mailto:|data:|#)/i.test(v)) return;
      try { el.setAttribute(attr, new URL(v, base).href); } catch(e){}
    });

        // Keep navigation inside the viewer: clicking links to other section
        // pages should switch chunk in-place instead of reloading this page.
        if (!docBody.dataset.viewerLinkHandler) {
            docBody.addEventListener('click', function(ev){
                var a = ev.target.closest('a[href]');
                if (!a) return;
                if (a.target === '_blank' || ev.ctrlKey || ev.metaKey || ev.shiftKey || ev.altKey) return;
                var href = a.getAttribute('href') || '';
                if (!href || href.startsWith('#') || /^(mailto:|data:|javascript:)/i.test(href)) return;
                var chunk = chunkForDocUrl(a.href || href);
                if (!chunk) return;
                ev.preventDefault();
                activateChunk(chunk, true);
            });
            docBody.dataset.viewerLinkHandler = '1';
        }

    // Render any Mermaid blocks injected from the doc.
    var mer = docBody.querySelectorAll('pre.mermaid');
    if (mer.length && window.mermaid && typeof window.mermaid.run === 'function') {
      try { window.mermaid.run({nodes: mer}); } catch(e){}
    } else if (mer.length && window.mermaid && typeof window.mermaid.init === 'function') {
      try { window.mermaid.init(undefined, mer); } catch(e){}
    }
        attachMermaidZoom(docBody);
    docBody.scrollTop = 0;
  }

    // Global guard: prevent accidental full-page navigation for same-origin
    // section links and route them to in-panel chunk switching.
    document.addEventListener('click', function(ev){
        var a = ev.target.closest('a[href]');
        if (!a) return;
        if (a.target === '_blank' || ev.ctrlKey || ev.metaKey || ev.shiftKey || ev.altKey) return;
        // Keep explicit navigation controls working.
        if (a.id === 'sv-doc-open' || a.closest('#sv-bundle-docs') || a.closest('.topbar')) return;

        var href = a.getAttribute('href') || '';
        if (!href || href.startsWith('#') || /^(mailto:|data:|javascript:)/i.test(href)) return;

        var url;
        try { url = new URL(a.href || href, location.href); } catch (e) { return; }
        if (url.origin !== location.origin) return;

        var chunk = chunkForDocUrl(url.href);
        if (!chunk) return;
        ev.preventDefault();
        activateChunk(chunk, true);
    }, true);

  // ---- Bootstrap: load source text -------------------------------
  fetch(SOURCES_BASE + data.sourceUrl)
    .then(function(r){ if (!r.ok) throw new Error(r.status); return r.text(); })
    .then(function(txt){
      renderCode(txt);
            // Restore last selected chunk for this bundle when available.
            if (savedState && savedState.lang && langs.indexOf(savedState.lang) >= 0 && savedState.lang !== currentLang) {
                setLang(savedState.lang);
            }
            if (savedState && savedState.chunkId) {
                var s = chunkById(savedState.chunkId);
                if (s) {
                    activateChunk(s, true);
                    return;
                }
            }
      // If URL has #L<n>, auto-activate the matching chunk.
      var m = location.hash.match(/^#L(\d+)/);
      if (m) {
        var c = chunkForLine(parseInt(m[1],10));
        if (c) activateChunk(c, true);
      }
    })
    .catch(function(e){
      codeEl.innerHTML = '<div class="sv-error">Failed to load source: ' + e.message + '</div>';
    });
})();
"""

# ----- source viewer (two-column: code + per-chunk docs) -------------------

def _chunk_slug(name: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "-", (name or "").strip().lower()).strip("-")
    return s or "section"


def _find_section_html(sections_dir: Path, chunk: dict, lang: str) -> Path | None:
    """Locate the on-disk section .md for a chunk and return its rendered
    .html path under SITE_ROOT. Walks ``sections_dir`` recursively and
    matches by, in order: ``program/<rest of id>.md`` (the canonical form
    written by section-doc-writer), ``<rest of id>.md``, longest path
    suffix vs the chunk id's segments, then unique-stem fallback."""
    if not sections_dir.is_dir():
        return None
    cid = (chunk.get("id") or "").strip()
    if not cid:
        return None
    id_parts = [p for p in cid.split("/") if p]
    if not id_parts:
        return None

    # Direct path candidates (id is "<program>/<...>"; section files are
    # written either under <program>/ or with the program segment dropped).
    cand_paths = [
        sections_dir / Path(*id_parts).with_suffix(".md"),
        sections_dir / Path(*id_parts[1:]).with_suffix(".md") if len(id_parts) > 1 else None,
        # Canonical section-doc-writer flat filename form used in this repo:
        # DEMO100__procedure-division__B260-CARICAMENTO-TAB-ECCEZIONI.md
        sections_dir / f"{'__'.join(id_parts)}.md",
        # Flat hyphen form sometimes produced by the writer (e.g.
        # "DEMO500-environment-division.md").
        sections_dir / f"{'-'.join(id_parts)}.md",
    ]
    for p in cand_paths:
        if p is not None and p.is_file():
            return md_to_html_path(p, lang)

    # Path-suffix scan: longest tail of id segments that matches the file's
    # relative path parts.
    cid_l = [s.lower() for s in id_parts]
    best: tuple[int, Path] | None = None
    for md in sections_dir.rglob("*.md"):
        rel_str = os.path.relpath(md, sections_dir)
        rel = Path(rel_str).with_suffix("")
        rel_l = [p.lower() for p in rel.parts]
        n = min(len(rel_l), len(cid_l))
        match = 0
        for i in range(1, n + 1):
            if rel_l[-i] == cid_l[-i]:
                match = i
            else:
                break
        if match == len(rel_l) and match > 0 and (best is None or match > best[0]):
            best = (match, md)
    if best is not None:
        return md_to_html_path(best[1], lang)

    # Unique-stem fallback.
    stem = cid_l[-1]
    hits = [md for md in sections_dir.rglob("*.md") if md.stem.lower() == stem]
    if len(hits) == 1:
        return md_to_html_path(hits[0], lang)
    return None


def collect_viewer_chunks(bundle_name: str) -> list[dict]:
    """Read docs/_shared/<bundle>/chunk-manifest.json and return a list of
    chunk descriptors enriched with per-language doc URLs (relative to
    site/_sources/)."""
    manifest_path = SHARED_ROOT / bundle_name / "chunk-manifest.json"
    if not manifest_path.is_file():
        return []
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    chunks_raw = manifest.get("chunks") or []
    out: list[dict] = []
    for c in chunks_raw:
        name = c.get("name") or ""
        slug = c.get("slug") or _chunk_slug(name)
        doc_urls: dict[str, str] = {}
        for lang in LANGS:
            sections_dir = DOCS_ROOT / lang / bundle_name / "sections"
            html_path = _find_section_html(sections_dir, c, lang)
            if html_path is None:
                continue
            # Relative URL from viewer page (site/_sources/<x>.html) to html_path.
            rel = Path("..") / html_path.relative_to(SITE_ROOT)
            doc_urls[lang] = rel.as_posix()
        out.append({
            "id": c.get("id") or f"{bundle_name}/{slug}",
            "name": name,
            "kind": c.get("kind") or "section",
            "start": int(c.get("start_line") or 0),
            "end": int(c.get("end_line") or 0),
            "parentId": c.get("parent_id"),
            "docUrls": doc_urls,
        })
    return out


def write_source_viewer(bundle_name: str, src_entry: dict) -> str | None:
    """Emit site/_sources/<bundle>.html — the two-column source viewer.
    Returns the URL of the emitted page relative to SITE_ROOT, or None
    when the bundle has no chunk manifest or no source text."""
    chunks = collect_viewer_chunks(bundle_name)
    if not chunks:
        return None
    slug = src_entry["slug"]
    src_txt_path = SITE_ROOT / SOURCES_SITE_DIR / f"{slug}.txt"
    if not src_txt_path.is_file():
        return None

    # Bundle-level doc links (FA / requirements / index) for the viewer header.
    bundle_docs: dict[str, dict[str, str]] = {}
    for lang in LANGS:
        bdir = DOCS_ROOT / lang / bundle_name
        entries: dict[str, str] = {}
        for fname, label in LEAF_ORDER:
            md = bdir / fname
            if md.is_file():
                html_path = md_to_html_path(md, lang)
                rel = Path("..") / html_path.relative_to(SITE_ROOT)
                entries[label] = rel.as_posix()
        if entries:
            bundle_docs[lang] = entries

    viewer_data = {
        "bundle": bundle_name,
        "slug": slug,
        "sourceRel": src_entry.get("rel") or src_entry["path"].as_posix(),
        "sourceUrl": f"{slug}.txt",
        "chunks": chunks,
        "bundleDocs": bundle_docs,
        "langs": list(LANGS),
        "langLabels": LANG_LABELS,
    }
    payload = json.dumps(viewer_data, ensure_ascii=False)

    body = SOURCE_VIEWER_BODY.format(
        bundle_label=html.escape(bundle_name),
    )
    page = SOURCE_VIEWER_TEMPLATE.format(
        title=html.escape(f"{bundle_name} — source viewer"),
        rel_root="../",
        sources_base="",  # already in _sources/ — fetch by relative slug
        viewer_payload=payload,
        body=body,
        mermaid_cdn=MERMAID_CDN,
    )
    dst = SITE_ROOT / SOURCES_SITE_DIR / f"{bundle_name}.html"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(page, encoding="utf-8")
    url = f"{SOURCES_SITE_DIR}/{bundle_name}.html"
    VIEWER_BY_BUNDLE[bundle_name] = url
    return url


SOURCE_VIEWER_BODY = """
<div class="sv-toolbar">
  <span class="sv-meta">
    <strong>{bundle_label}</strong>
    <code class="sv-path" id="sv-path"></code>
  </span>
  <span class="sv-chunk-picker">
    <label for="sv-chunk-select">Jump to:</label>
    <select id="sv-chunk-select"><option value="">— select chunk —</option></select>
  </span>
  <span class="sv-lang-switch" id="sv-lang-switch"></span>
</div>
<div class="sv-bundle-docs" id="sv-bundle-docs"></div>
<div class="sv-layout">
  <section class="sv-left">
    <pre class="sv-code"><code id="sv-code"></code></pre>
  </section>
  <section class="sv-right">
    <header class="sv-doc-head">
      <span id="sv-doc-title">Hover or click a chunk on the left, or pick one from the dropdown.</span>
      <a id="sv-doc-open" class="sv-doc-open" target="_blank" rel="noopener" hidden>Open full page ↗</a>
    </header>
    <article id="sv-doc-body" class="markdown-body sv-doc-body">
      <p class="sv-empty">No chunk selected.</p>
    </article>
  </section>
</div>
"""

SOURCE_VIEWER_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="stylesheet" href="{rel_root}assets/style.css">
</head>
<body class="sv-body">
<header class="topbar">
  <a class="brand" href="{rel_root}index.html">DEMO COBOL Modernization</a>
  <nav class="topnav">
    <a href="{rel_root}en/index.html">English home</a>
    <a href="{rel_root}it/index.html">Italiano home</a>
  </nav>
</header>
{body}
<script type="application/json" id="sv-data">{viewer_payload}</script>
<script>window.__SOURCES_BASE__ = "{sources_base}";</script>
<script defer src="{rel_root}assets/mermaid.min.js"
    onerror="(function(){{var s=document.createElement('script');s.src='{mermaid_cdn}';s.defer=true;document.head.appendChild(s);}})();"></script>
<script>window.addEventListener('DOMContentLoaded',function(){{try{{if(window.mermaid){{mermaid.initialize({{startOnLoad:false,theme:'default',securityLevel:'loose'}});}}}}catch(e){{}}}});</script>
<script src="{rel_root}assets/source-viewer.js" defer></script>
</body>
</html>
"""


def write_mermaid_asset() -> None:
    """Best-effort copy of a local mermaid bundle into site assets.

    If a local copy is unavailable, page templates fall back to CDN.
    """
    dst = SITE_ROOT / "assets" / "mermaid.min.js"
    candidates = [
        REPO_ROOT / "node_modules" / "mermaid" / "dist" / "mermaid.min.js",
        REPO_ROOT / "docs" / "_portal" / "assets" / "mermaid.min.js",
    ]
    for src in candidates:
        if src.is_file():
            shutil.copy2(src, dst)
            return
    # If no local bundle is available, emit a tiny loader that fetches Mermaid
    # from CDN while preserving the same local script path.
    dst.write_text(
        (
            "(function(){"
            "var s=document.createElement('script');"
            f"s.src='{MERMAID_CDN}';"
            "s.defer=true;"
            "document.head.appendChild(s);"
            "})();\n"
        ),
        encoding="utf-8",
    )


# ----- doc bundle discovery -------------------------------------------------

LEAF_ORDER = [
    ("index.md", "Index"),
    ("complete.md", "Complete"),
    ("functional-analysis.md", "Functional analysis"),
    ("requirements.md", "Requirements"),
    ("technical-analysis.md", "Technical analysis"),
    ("migration-runbook.md", "Migration runbook"),
    ("_coverage.md", "Coverage"),
]


def _chunk_index(bundle_name: str) -> dict:
    """Return a structured index of the bundle's chunk manifest:

    ``{"by_id": {id_lower: meta}, "by_stem": {stem_lower: [meta, ...]},
    "program": str, "ordered": [meta, ...]}``

    where ``meta = {id, name, kind, order}`` and ``order`` is the source-line
    rank. ``program`` is the common root segment (e.g. ``"DEMO500"``) used to
    strip the program name from chunk ids when building the sidebar tree.
    """
    manifest_path = SHARED_ROOT / bundle_name / "chunk-manifest.json"
    empty = {"by_id": {}, "by_stem": {}, "program": "", "ordered": []}
    if not manifest_path.is_file():
        return empty
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return empty
    chunks = sorted(
        (manifest.get("chunks") or []),
        key=lambda c: (int(c.get("start_line") or 0), int(c.get("end_line") or 0)),
    )
    by_id: dict[str, dict] = {}
    by_stem: dict[str, list[dict]] = {}
    roots: set[str] = set()
    ordered: list[dict] = []
    for idx, c in enumerate(chunks):
        cid = (c.get("id") or "").strip()
        if not cid:
            continue
        cid_l = cid.lower()
        meta = {
            "id": cid, "name": (c.get("name") or "").strip() or cid.rsplit("/", 1)[-1],
            "kind": (c.get("kind") or "").strip().lower(), "order": idx,
            "parent_id": (c.get("parent_id") or "").strip() or None,
        }
        by_id.setdefault(cid_l, meta)
        stem = cid_l.rsplit("/", 1)[-1]
        by_stem.setdefault(stem, []).append(meta)
        roots.add(cid_l.split("/", 1)[0])
        ordered.append(meta)
    # Program root = single common first segment, if any.
    program = next(iter(roots)) if len(roots) == 1 else ""
    return {"by_id": by_id, "by_stem": by_stem, "program": program, "ordered": ordered}


def _resolve_chunk_id(md_rel_parts: tuple[str, ...], index: dict) -> str | None:
    """Match an on-disk section .md (path parts under ``sections/``, no
    suffix) to its canonical chunk id from the manifest. Tries, in order:

    1. ``program/<parts>`` (full join).
    2. ``<parts>`` literally (already includes program).
    3. The hyphen-flattened variant ``program-<parts[0]>`` → ``program/<parts[0]>``.
    4. Path-suffix scan: longest chunk id whose lowercase segments end with
       the file's lowercase segments.
    5. Stem-only lookup: unique chunk whose last segment matches the file
       stem.

    Returns the matched chunk id (original case) or ``None``.
    """
    by_id = index["by_id"]
    program = index["program"]
    parts_l = tuple(p.lower() for p in md_rel_parts)
    # Many generated section files are flat names like
    # DEMO100__procedure-division__B200-CONTROLLO-PARAMETRO.md.
    # Normalize this representation back to chunk-id path segments.
    if len(parts_l) == 1 and "__" in parts_l[0]:
        split_parts = [seg for seg in parts_l[0].split("__") if seg]
        # Collision-disambiguated chunk ids may end with ``__L<line>``.
        # Keep that suffix attached to the previous segment so
        # ``...__W-SYS__L280`` resolves to ``.../W-SYS__L280``.
        if len(split_parts) >= 2 and re.fullmatch(r"l\d+", split_parts[-1]):
            split_parts[-2] = f"{split_parts[-2]}__{split_parts[-1]}"
            split_parts.pop()
        split_parts = tuple(split_parts)
        if split_parts:
            parts_l = split_parts
    if not parts_l:
        return None

    candidates: list[str] = []
    if program:
        candidates.append(f"{program}/{'/'.join(parts_l)}")
    candidates.append("/".join(parts_l))
    # Handle the "DEMO500-environment-division.md" flat form.
    if program and len(parts_l) == 1 and parts_l[0].startswith(f"{program}-"):
        rest = parts_l[0][len(program) + 1:]
        candidates.append(f"{program}/{rest}")

    for cand in candidates:
        if cand in by_id:
            return by_id[cand]["id"]

    # Path-suffix scan.
    best: tuple[int, str] | None = None
    for cid_l, meta in by_id.items():
        seg = cid_l.split("/")
        n = min(len(seg), len(parts_l))
        # Count matching trailing segments.
        match = 0
        for i in range(1, n + 1):
            if seg[-i] == parts_l[-i]:
                match = i
            else:
                break
        if match == len(parts_l) and (best is None or len(seg) < best[0]):
            best = (len(seg), meta["id"])
    if best is not None:
        return best[1]

    # Stem-only lookup.
    stem = parts_l[-1]
    hits = index["by_stem"].get(stem) or []
    if len(hits) == 1:
        return hits[0]["id"]
    return None


def _build_sections_tree(sections_dir: Path, lang: str, index: dict) -> list[dict]:
    """Build the sidebar section tree from manifest parent/child links.

    This guarantees a canonical hierarchy (typically division > section >
    paragraph) regardless of how section markdown files are laid out on disk.
    """
    by_id = index["by_id"]
    ordered = index.get("ordered") or []

    # Map chunk id -> rendered section html (discovered from disk).
    html_by_chunk: dict[str, Path] = {}
    extras: list[dict] = []
    if sections_dir.is_dir():
        for md in sections_dir.rglob("*.md"):
            rel_parts = Path(os.path.relpath(md, sections_dir)).with_suffix("").parts
            if not rel_parts:
                continue
            chunk_id = _resolve_chunk_id(rel_parts, index)
            if chunk_id:
                html_by_chunk[chunk_id.lower()] = md_to_html_path(md, lang)
            else:
                extras.append({
                    "label": rel_parts[-1],
                    "html": md_to_html_path(md, lang),
                    "order": 10 ** 6,
                    "kind": "",
                    "children": [],
                })

    # Build node table for all manifest chunks.
    node_by_id: dict[str, dict] = {}
    for meta in ordered:
        cid_l = meta["id"].lower()
        node_by_id[cid_l] = {
            "label": meta.get("name") or meta["id"].rsplit("/", 1)[-1],
            "html": html_by_chunk.get(cid_l),
            "order": meta.get("order", 10 ** 6),
            "kind": meta.get("kind") or "",
            "children": [],
        }

    # Link children to parent using manifest parent_id.
    roots: list[dict] = []
    for meta in ordered:
        cid_l = meta["id"].lower()
        node = node_by_id[cid_l]
        pid = (meta.get("parent_id") or "").lower()
        if pid and pid in node_by_id:
            node_by_id[pid]["children"].append(node)
        else:
            roots.append(node)

    def _sort(nodes: list[dict]) -> None:
        nodes.sort(key=lambda n: (n["order"], n["label"].lower()))
        for n in nodes:
            _sort(n["children"])

    _sort(roots)
    roots.extend(sorted(extras, key=lambda n: (n["order"], n["label"].lower())))
    return roots


def _section_sort_key(md: Path, order: dict[str, int]) -> tuple[int, str]:
    """Order key for sidebar section listing: source-line order first
    (when known), then alphabetical."""
    stem = md.stem.lower()
    # Strip a leading ``NN-`` numeric prefix used by some section writers.
    trimmed = re.sub(r"^\d+[-_]", "", stem)
    for key in (stem, trimmed):
        if key in order:
            return (order[key], stem)
        for k, v in order.items():
            if key.startswith(k) or k.startswith(key):
                return (v, stem)
    return (10**6, stem)


def collect_bundles(lang: str) -> list[dict]:
    """Return [{name, kind, leaves:[{key,label,md,html}], sections:[{name,md,html}]}]
    for every program/group folder under docs/<lang>/. Sections are ordered
    by their position in the underlying source file (chunk start_line),
    falling back to alphabetical when no chunk manifest is available.
    """
    base = DOCS_ROOT / lang
    out: list[dict] = []
    if not base.is_dir():
        return out

    def walk(parent: Path, group: bool) -> None:
        for entry in sorted(parent.iterdir(), key=lambda p: p.name.lower()):
            if not entry.is_dir():
                continue
            if entry.name == "_groups":
                walk(entry, True)
                continue
            leaves = []
            for fname, label in LEAF_ORDER:
                md = entry / fname
                if md.is_file():
                    leaves.append({"key": fname, "label": label, "md": md,
                                   "html": md_to_html_path(md, lang)})
            sections_dir = entry / "sections"
            sections_tree: list[dict] = []
            if sections_dir.is_dir():
                index = _chunk_index(entry.name)
                sections_tree = _build_sections_tree(sections_dir, lang, index)
            if leaves or sections_tree:
                out.append({
                    "name": entry.name, "group": group,
                    "leaves": leaves, "sections": sections_tree,
                })

    walk(base, False)
    return out


def _fast_relpath(target: Path, start: Path) -> str:
    """Compute relative path without slow os.path.relpath on Windows.
    Algorithm: convert both to absolute, split into parts, find common
    ancestor, then construct '..' and 'folder' chain.
    """
    # Use pure absolute-path normalization to avoid expensive filesystem
    # resolution during large sidebar generation.
    target_abs = Path(os.path.abspath(str(target)))
    start_abs = Path(os.path.abspath(str(start)))
    
    # Normalize path separators and split into parts
    target_parts = list(target_abs.parts)
    start_parts = list(start_abs.parts)
    
    # Find common ancestor index
    common_len = 0
    for t, s in zip(target_parts, start_parts):
        if t.lower() == s.lower():  # Case-insensitive on Windows
            common_len += 1
        else:
            break
    
    # Build relative path
    ups = [".."] * (len(start_parts) - common_len)
    downs = target_parts[common_len:]
    
    result = "/".join(ups + downs) if (ups or downs) else "."
    return result


def build_sidebar(bundles: list[dict], lang: str, current_html: Path) -> str:
    """Emit HTML sidebar nav."""
    def href(target: Path) -> str:
        target_path = target if target.is_absolute() else (SITE_ROOT / target)
        return _fast_relpath(target_path, current_html.parent)

    parts: list[str] = []
    parts.append(f'<h3>{html.escape(LANG_LABELS[lang])}</h3>')
    files = [b for b in bundles if not b["group"]]
    groups = [b for b in bundles if b["group"]]
    parts.append('<ul>')
    for b in files:
        parts.append(_bundle_html(b, href))
    parts.append('</ul>')
    if groups:
        parts.append('<h3>Groups</h3><ul>')
        for b in groups:
            parts.append(_bundle_html(b, href))
        parts.append('</ul>')
    if SHARED_GLOSSARY_MD.exists():
        glossary_html = shared_md_to_html_path(SHARED_GLOSSARY_MD)
        parts.append('<h3>Shared</h3><ul>')
        parts.append(f'<li><a href="{href(glossary_html)}">Central glossary</a></li>')
        parts.append('</ul>')
    return "\n".join(parts)


def _bundle_html(b: dict, href) -> str:
    out = [f'<li><details><summary>{html.escape(b["name"])}</summary><ul>']
    viewer_url = VIEWER_BY_BUNDLE.get(b["name"])
    if viewer_url:
        viewer_path = SITE_ROOT / viewer_url
        out.append(f'<li><a href="{href(viewer_path)}" class="source-code-link" title="View source code with split-panel documentation">📄 Source Code</a></li>')
    for leaf in b["leaves"]:
        out.append(f'<li><a href="{href(leaf["html"])}">{html.escape(leaf["label"])}</a></li>')
    if b["sections"]:
        out.append('<li><details open><summary>Sections</summary><ul>')
        for node in b["sections"]:
            out.append(_section_node_html(node, href))
        out.append('</ul></details></li>')
    out.append('</ul></details></li>')
    return "\n".join(out)


def _section_node_html(node: dict, href) -> str:
    """Render one section-tree node. Internal nodes use <details>; leaves
    use <a>. Internal nodes that also have a backing .md file expose a
    small ``·`` link next to the summary so the self-doc remains reachable.
    """
    def _first_desc_html(n: dict) -> Path | None:
        if n.get("html") is not None:
            return n["html"]
        for child in n.get("children") or []:
            hit = _first_desc_html(child)
            if hit is not None:
                return hit
        return None

    label = html.escape(node["label"])
    kind = node.get("kind") or ""
    label_html = (f'<span class="sec-kind sec-kind-{html.escape(kind)}">{label}</span>'
                  if kind else label)
    if not node["children"]:
        if node["html"] is not None:
            return f'<li><a href="{href(node["html"])}">{label_html}</a></li>'
        return f'<li><span class="sec-empty">{label_html}</span></li>'
    summary_target = node["html"] if node["html"] is not None else _first_desc_html(node)
    summary = label_html
    if summary_target is not None:
        summary = (
            f'<a href="{href(summary_target)}" class="sec-summary-link"'
            f' onclick="event.stopPropagation();" title="Open section page">'
            f'{label_html}</a>'
        )
    inner = ['<ul>']
    for child in node["children"]:
        inner.append(_section_node_html(child, href))
    inner.append('</ul>')
    return (f'<li><details><summary>{summary}</summary>'
            + "\n".join(inner) + '</details></li>')


def build_breadcrumb(md: Path, lang: str, rel_root: str) -> str:
    parts = md.relative_to(DOCS_ROOT / lang).parts
    crumbs = [f'<a href="{rel_root}index.html">Home</a>',
              f'<a href="{rel_root}{lang}/index.html">{LANG_LABELS[lang]}</a>']
    for p in parts[:-1]:
        crumbs.append(html.escape(p))
    crumbs.append(html.escape(parts[-1]))
    return " / ".join(crumbs)


def sibling_html_url(md: Path, lang: str, dst: Path) -> str | None:
    other = "it" if lang == "en" else "en"
    rel = md.relative_to(DOCS_ROOT / lang)
    other_md = DOCS_ROOT / other / rel
    if not other_md.is_file():
        return None
    other_html = md_to_html_path(other_md, other)
    ups = "../" * (len(dst.parent.relative_to(SITE_ROOT).parts))
    return ups + other_html.relative_to(SITE_ROOT).as_posix()


# ----- main -----------------------------------------------------------------

def render_page(md_path: Path, lang: str, bundles: list[dict],
                md_engine: markdown.Markdown) -> None:
    dst = md_to_html_path(md_path, lang)
    dst.parent.mkdir(parents=True, exist_ok=True)
    md_engine.reset()
    raw = md_path.read_text(encoding="utf-8", errors="ignore")
    raw = strip_hidden_sections(raw)
    citations = parse_citations(raw)
    # Heading-level "source" badges intentionally disabled: only the page
    # title (h1) and the inline L<n> citation chips open the source panel.
    body = md_engine.convert(raw)
    body = fixup_links(body, md_path, dst)
    body = figurize_images(body)

    # Resolve the source viewer URL for this page's bundle (first path
    # component under docs/<lang>/, skipping the ``_groups`` namespace).
    rel_parts = md_path.relative_to(DOCS_ROOT / lang).parts
    bundle_name: str | None = None
    if rel_parts:
        if rel_parts[0] == "_groups":
            bundle_name = rel_parts[1] if len(rel_parts) > 1 else None
        else:
            bundle_name = rel_parts[0]
    viewer_url: str | None = None
    if bundle_name and bundle_name in VIEWER_BY_BUNDLE:
        viewer_target = SITE_ROOT / VIEWER_BY_BUNDLE[bundle_name]
        ups = "../" * (len(dst.parent.relative_to(SITE_ROOT).parts))
        viewer_url = ups + viewer_target.relative_to(SITE_ROOT).as_posix()

    has_panel = bool(citations)
    body = inject_title_source_link(body, viewer_url, has_sources=has_panel)
    body = linkify_citation_refs(body, citations, viewer_url, has_sources=has_panel)

    title = read_title(md_path)
    sidebar = build_sidebar(bundles, lang, dst)
    rel_root = "../" * (len(dst.parent.relative_to(SITE_ROOT).parts))
    breadcrumb = build_breadcrumb(md_path, lang, rel_root)
    sibling = sibling_html_url(md_path, lang, dst)
    page_sources_json = json.dumps(
        {cid: {k: v for k, v in c.items() if k != "id"} for cid, c in citations.items()},
        ensure_ascii=False,
    ).replace("<", "\\u003c")  # never let a value close the <script> element early
    page = page_template(title=title, lang=lang, body=body,
                         sidebar=sidebar, rel_root=rel_root,
                         sibling_url=sibling, breadcrumb=breadcrumb,
                         page_sources_json=page_sources_json,
                         has_sources=bool(citations))
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        dst.write_text(page, encoding="utf-8")
    except FileNotFoundError:
        # Defensive retry for occasional Windows path races while creating
        # nested output folders during large render passes.
        os.makedirs(dst.parent, exist_ok=True)
        dst.write_text(page, encoding="utf-8")


def render_shared_page(md_path: Path, bundles: list[dict],
                       md_engine: markdown.Markdown) -> None:
    """Render docs/_*.md pages to site/_shared_pages/*.html."""
    dst = shared_md_to_html_path(md_path)
    dst.parent.mkdir(parents=True, exist_ok=True)
    md_engine.reset()
    raw = md_path.read_text(encoding="utf-8", errors="ignore")
    raw = strip_hidden_sections(raw)
    body = md_engine.convert(raw)
    body = fixup_links(body, md_path, dst)
    body = figurize_images(body)

    title = read_title(md_path)
    # Reuse EN sidebar so shared pages are reachable from the same nav tree.
    sidebar = build_sidebar(bundles, "en", dst)
    rel_root = "../" * (len(dst.parent.relative_to(SITE_ROOT).parts))
    breadcrumb = '<a href="../index.html">Home</a> / Shared / ' + html.escape(md_path.name)
    page = page_template(
        title=title,
        lang="en",
        body=body,
        sidebar=sidebar,
        rel_root=rel_root,
        sibling_url=None,
        breadcrumb=breadcrumb,
        page_sources_json="{}",
        has_sources=False,
    )
    dst.write_text(page, encoding="utf-8")
    SHARED_PAGE_BY_MD[md_path.resolve()] = dst


def write_landing(active_langs: list[str]) -> None:
    SITE_ROOT.mkdir(parents=True, exist_ok=True)
    glossary_link = ""
    if SHARED_GLOSSARY_MD.exists():
        glossary_rel = shared_md_to_html_path(SHARED_GLOSSARY_MD).relative_to(SITE_ROOT).as_posix()
        glossary_link = f'<p><a href="{glossary_rel}">Open central glossary</a></p>'
    cards = "\n  ".join(
        f'<a href="{lang}/index.html">{html.escape(LANG_LABELS[lang])}</a>'
        for lang in active_langs
    )
    html_body = """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DEMO COBOL Modernization — Documentation Portal</title>
<link rel="stylesheet" href="assets/style.css"></head>
<body>
<header class="topbar"><a class="brand" href="index.html">DEMO COBOL Modernization</a></header>
<div class="landing">
<h1>Documentation portal</h1>
<p>Bilingual reverse-engineering deliverables for the sample COBOL workspace.
Pick a language to start browsing programs, JCL jobs, and groups.</p>
<div class="lang-cards">
  {cards}
</div>
</div>{glossary_link}</body></html>""".format(cards=cards, glossary_link=glossary_link)
    (SITE_ROOT / "index.html").write_text(html_body, encoding="utf-8")


def write_lang_index(lang: str, bundles: list[dict]) -> None:
    dst = SITE_ROOT / lang / "index.html"
    dst.parent.mkdir(parents=True, exist_ok=True)
    files = [b for b in bundles if not b["group"]]
    groups = [b for b in bundles if b["group"]]

    def first_html(nodes: list[dict]) -> Path | None:
        for n in nodes:
            if n.get("html") is not None:
                return n["html"]
            child = first_html(n.get("children") or [])
            if child is not None:
                return child
        return None

    def link(b):
        if b["leaves"]:
            rel = b["leaves"][0]["html"].relative_to(SITE_ROOT).as_posix()
        elif b["sections"]:
            first = first_html(b["sections"])
            if first is None:
                return html.escape(b["name"])
            rel = first.relative_to(SITE_ROOT).as_posix()
        else:
            return html.escape(b["name"])
        ups = "../"
        main_link = f'<a href="{ups}{rel}">{html.escape(b["name"])}</a>'
        viewer_url = VIEWER_BY_BUNDLE.get(b["name"])
        if viewer_url:
            main_link += (f' <a class="sv-source-link" href="{ups}{viewer_url}"'
                          f' title="Open the side-by-side source viewer">source ☰</a>')
        return main_link

    glossary_block = ""
    if SHARED_GLOSSARY_MD.exists():
        glossary_rel = rel_url(shared_md_to_html_path(SHARED_GLOSSARY_MD), dst)
        glossary_block = f"<h2>Shared resources</h2>\n<ul><li><a href=\"{glossary_rel}\">Central glossary</a></li></ul>"

    body = f"""<h1>{LANG_LABELS[lang]} — index</h1>
<h2>Programs / JCL files</h2>
<ul>{"".join(f"<li>{link(b)}</li>" for b in files)}</ul>
<h2>Groups</h2>
<ul>{"".join(f"<li>{link(b)}</li>" for b in groups)}</ul>
{glossary_block}
"""
    sidebar = build_sidebar(bundles, lang, dst)
    page = page_template(title=f"{LANG_LABELS[lang]} index", lang=lang,
                         body=body, sidebar=sidebar, rel_root="../",
                         sibling_url=None,
                         breadcrumb=f'<a href="../index.html">Home</a> / {LANG_LABELS[lang]}',
                         page_sources_json="{}", has_sources=False)
    dst.write_text(page, encoding="utf-8")


def copy_shared() -> None:
    """Copy docs/_shared/ to site/_shared/ (SVG diagrams etc.)."""
    src = SHARED_ROOT
    if not src.is_dir():
        return
    dst = SITE_ROOT / "_shared"
    if dst.exists():
        shutil.rmtree(dst)
    # Only copy SVG + PNG + json files to keep the portal small.
    for f in src.rglob("*"):
        if f.is_file() and f.suffix.lower() in {".svg", ".png", ".json", ".mmd"}:
            target = dst / f.relative_to(src)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, target)


def _log(task: str, msg: str = "", t0: float | None = None) -> None:
    """Single-line task logger. Prefix every line with the task name and an
    elapsed-time stamp so the build progress is readable on the console."""
    elapsed = f" ({time.time()-t0:.1f}s)" if t0 is not None else ""
    suffix = f" — {msg}" if msg else ""
    print(f"[portal] {task}{suffix}{elapsed}", flush=True)


def sync_central_glossary(t0: float) -> None:
    """Regenerate docs/_glossary.md from config/glossary.yaml when available."""
    cfg = REPO_ROOT / "config" / "glossary.yaml"
    script = REPO_ROOT / "scripts" / "validation" / "sync-glossary.py"
    if not cfg.is_file() or not script.is_file():
        return
    _log("task=glossary", f"sync from {cfg.relative_to(REPO_ROOT).as_posix()}", t0)
    proc = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        _log("task=glossary", (proc.stdout or "synced").strip(), t0)
    else:
        _log("task=glossary", "sync failed, continuing without update", t0)
        if proc.stderr:
            print(proc.stderr.strip(), file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    source_root = resolve_source_root(args.source_root)
    t0 = time.time()
    sync_central_glossary(t0)
    _log("task=clean", f"target={SITE_ROOT}")
    if SITE_ROOT.exists():
        # Prefer removing contents over the root itself: on Windows an open
        # terminal CWD or browser handle can lock the directory and break
        # ``rmtree`` even after every file has been deleted.
        for child in SITE_ROOT.iterdir():
            try:
                if child.is_dir() and not child.is_symlink():
                    shutil.rmtree(child, ignore_errors=True)
                else:
                    child.unlink(missing_ok=True)
            except OSError as e:
                print(f"[portal] warn: could not remove {child}: {e}")
    SITE_ROOT.mkdir(parents=True, exist_ok=True)
    (SITE_ROOT / "assets").mkdir(exist_ok=True)
    _log("task=write-assets", "style.css, script.js, source-viewer.js")
    (SITE_ROOT / "assets" / "style.css").write_text(STYLE_CSS, encoding="utf-8")
    (SITE_ROOT / "assets" / "script.js").write_text(SCRIPT_JS, encoding="utf-8")
    (SITE_ROOT / "assets" / "source-viewer.js").write_text(SOURCE_VIEWER_JS, encoding="utf-8")
    write_mermaid_asset()

    global SOURCE_INDEX
    _log("task=discover-sources", f"root={source_root}", t0)
    SOURCE_INDEX = discover_sources(source_root)
    _log("task=discover-sources",
         f"indexed {len(set(e['slug'] for e in SOURCE_INDEX.values()))} source files", t0)
    source_label = source_root.relative_to(REPO_ROOT).as_posix() if source_root.is_relative_to(REPO_ROOT) else str(source_root)
    _log("task=copy-sources", f"{source_label} -> site/_sources/", t0)
    copy_sources_to_site()

    _log("task=collect-bundles", f"langs={list(LANGS)}", t0)
    bundles_by_lang = {lang: collect_bundles(lang) for lang in LANGS}
    for lang, bundles in bundles_by_lang.items():
        _log("task=collect-bundles", f"lang={lang} bundles={len(bundles)}", t0)

    # ---- Source viewers (one per bundle that has a chunk-manifest) ------
    # Enumerate from docs/_shared/<bundle>/chunk-manifest.json so viewers are
    # emitted even when docs/en|it are empty (e.g. after reset-repo.ps1).
    bundle_names: set[str] = set()
    if SHARED_ROOT.is_dir():
        for sub in SHARED_ROOT.iterdir():
            if sub.is_dir() and (sub / "chunk-manifest.json").is_file():
                bundle_names.add(sub.name)
    # Include any per-language bundle (in case its manifest lives elsewhere).
    bundle_names.update(b["name"] for langb in bundles_by_lang.values() for b in langb)
    _log("task=source-viewers", f"candidates={len(bundle_names)}", t0)
    viewer_count = 0
    for name in sorted(bundle_names):
        src_entry = SOURCE_INDEX.get(name.upper())
        if not src_entry:
            continue
        _log("task=source-viewers", f"render bundle={name}")
        url = write_source_viewer(name, src_entry)
        if url:
            viewer_count += 1
    _log("task=source-viewers", f"emitted {viewer_count}", t0)

    md_engine = markdown.Markdown(extensions=MD_EXTENSIONS, extension_configs=MD_EXT_CFG,
                                  output_format="html5")

    shared_md_pages = []
    if SHARED_GLOSSARY_MD.is_file():
        shared_md_pages.append(SHARED_GLOSSARY_MD)
    _log("task=shared-pages", f"count={len(shared_md_pages)}", t0)
    for shared_md in shared_md_pages:
        _log("task=shared-pages", f"render {shared_md.name}", t0)
        render_shared_page(shared_md, bundles_by_lang.get("en", []), md_engine)

    # A language is "active" only when it actually has documents to render;
    # this keeps empty placeholder indexes and dead landing cards out of the
    # portal (e.g. before the Italian docs have been generated).
    active_langs = [lang for lang in LANGS
                    if bundles_by_lang[lang] or list((DOCS_ROOT / lang).rglob("*.md"))]
    if not active_langs:
        active_langs = [LANGS[0]]

    total = 0
    for lang in active_langs:
        bundles = bundles_by_lang[lang]
        _log("task=lang-index", f"lang={lang}", t0)
        write_lang_index(lang, bundles)
        md_files = list((DOCS_ROOT / lang).rglob("*.md"))
        _log("task=render-pages", f"lang={lang} pages={len(md_files)}", t0)
        for md in md_files:
            render_page(md, lang, bundles, md_engine)
            total += 1
            if total % 200 == 0:
                _log("task=render-pages", f"progress {total} rendered", t0)
        _log("task=render-pages", f"lang={lang} done", t0)

    _log("task=landing", "index.html", t0)
    write_landing(active_langs)
    _log("task=copy-shared", "docs/_shared -> site/_shared", t0)
    copy_shared()

    # Manifest for downstream tooling.
    manifest = {
        "site_root": SITE_ROOT.relative_to(REPO_ROOT).as_posix(),
        "pages_rendered": total,
        "source_viewers": len(VIEWER_BY_BUNDLE),
        "shared_pages": len(shared_md_pages),
        "languages": active_langs,
        "elapsed_seconds": round(time.time() - t0, 2),
    }
    _log("task=manifest", "writing site/manifest.json", t0)
    (SITE_ROOT / "manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8")

    _log("task=DONE", f"{total} pages, {len(VIEWER_BY_BUNDLE)} viewers", t0)
    _log("task=DONE", f"site={SITE_ROOT}")
    return 0


if __name__ == "__main__":
        sys.exit(main(sys.argv[1:]))
