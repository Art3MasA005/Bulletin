"""`make extract-report` -- encoding classification, rendered page beside text.

CLAUDE.md #7: run this before `make ingest` on any new corpus. Legacy-font
documents ingested without the converter index as garbage, with no error
anywhere.

CLAUDE.md #8: inspect the output before writing Flutter code. If the extracted
text is wrong, frontend work is worthless.

By default this runs WITHOUT a provider, so it costs nothing: pages that would
need a vision read are listed as escalation candidates rather than read. Pass
--vision to actually spend tokens.

    python -m tools.extract_report                 # free, whole corpus
    python -m tools.extract_report --vision        # spends vision tokens
    python -m tools.extract_report --limit 5 corpus/bn_legacy
"""

from __future__ import annotations

import argparse
import base64
import html
import logging
import sys
from dataclasses import dataclass
from pathlib import Path

from app.config import Settings, get_settings
from app.ingest.extract import (
    IMAGE_SUFFIXES,
    PDF_SUFFIXES,
    DocumentRejected,
    render_page_png,
)
from app.ingest.pipeline import IngestResult, ingest_document
from app.providers.base import Provider

logger = logging.getLogger(__name__)

THUMB_DPI = 72
SNIPPET_CHARS = 1800


@dataclass
class PageRow:
    page_no: int
    method: str
    lang: str
    confidence: float
    escalated: bool
    reason: str
    text: str
    thumbnail: str  # data: URI


@dataclass
class DocRow:
    name: str
    path: Path
    pages: list[PageRow]
    rejected: str | None
    method_counts: dict[str, int]
    total_chars: int


def find_documents(root: Path, limit: int | None = None) -> list[Path]:
    suffixes = PDF_SUFFIXES | IMAGE_SUFFIXES
    files = sorted(p for p in root.rglob("*") if p.suffix.lower() in suffixes)
    return files[:limit] if limit else files


def _thumbnail(path: Path, page_no: int, settings: Settings) -> str:
    """Small rendered page as a data: URI, so the report is one portable file."""
    try:
        thumb_settings = settings.model_copy(update={"vision_render_dpi": THUMB_DPI})
        png = render_page_png(path, page_no, thumb_settings)
        return "data:image/png;base64," + base64.b64encode(png).decode("ascii")
    except Exception as exc:  # noqa: BLE001 -- a missing thumbnail must not stop the report
        logger.warning("thumbnail failed doc=%s page_no=%d error=%s", path.name, page_no, exc)
        return ""


def build_doc_row(
    path: Path, provider: Provider | None, settings: Settings, max_pages: int
) -> DocRow:
    try:
        result: IngestResult = ingest_document(path, provider, settings=settings, resume=False)
    except DocumentRejected as exc:
        return DocRow(
            name=path.name,
            path=path,
            pages=[],
            rejected=exc.reason,
            method_counts={},
            total_chars=0,
        )

    rows: list[PageRow] = []
    for page in result.pages[:max_pages]:
        rows.append(
            PageRow(
                page_no=page.page_no,
                method=page.method,
                lang=page.lang,
                confidence=page.confidence,
                escalated=page.escalated,
                reason=page.reason,
                text=page.text,
                thumbnail=_thumbnail(path, page.page_no, settings),
            )
        )
    return DocRow(
        name=path.name,
        path=path,
        pages=rows,
        rejected=result.rejected,
        method_counts=result.method_counts(),
        total_chars=result.total_chars,
    )


CSS = """
:root{--ink:#1C1B2E;--muted:#5A5870;--faint:#8C8AA0;--paper:#FDFCFA;
--accent:#6A5AE0;--bn:#C4456B;--en:#2F6FB5;--ok:#2F8F6E;--warn:#B8701E;--bad:#C0392B;
--line:rgba(28,27,46,.10)}
*{box-sizing:border-box}
body{margin:0;padding:32px;background:#EFE9F7;color:var(--ink);
font:16px/1.6 "Segoe UI",system-ui,sans-serif}
h1{font-size:24px;line-height:1.25;margin:0 0 4px}
.sub{color:var(--muted);margin:0 0 24px}
.doc{background:var(--paper);border-radius:20px;padding:24px;margin:0 0 24px;
box-shadow:0 8px 20px -16px rgba(66,52,96,.5)}
.doc h2{font-size:18px;margin:0 0 12px;word-break:break-all}
.badges{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px}
.badge{font:12px/1.2 ui-monospace,Consolas,monospace;padding:6px 10px;border-radius:12px;
background:rgba(28,27,46,.05);color:var(--muted)}
.badge.native{background:rgba(47,143,110,.14);color:var(--ok)}
.badge.legacy{background:rgba(184,112,30,.14);color:var(--warn)}
.badge.scanned{background:rgba(106,90,224,.12);color:var(--accent)}
.rejected{background:rgba(192,57,43,.12);color:var(--bad);padding:12px 16px;border-radius:12px}
.page{display:grid;grid-template-columns:220px 1fr;gap:20px;padding:20px 0;
border-top:1px solid var(--line)}
.thumb img{width:100%;border-radius:12px;border:1px solid var(--line);background:#fff}
.meta{font:12px/1.5 ui-monospace,Consolas,monospace;color:var(--muted);margin-top:8px}
.reason{color:var(--faint);font-size:12px;margin-top:6px}
.text{white-space:pre-wrap;font-size:14px;line-height:1.7;background:rgba(28,27,46,.03);
padding:16px;border-radius:12px;max-height:460px;overflow:auto}
.text:lang(bn){line-height:1.8}
.empty{color:var(--bad);font-style:italic}
.esc{color:var(--warn);font-weight:600}
.warnbox{background:rgba(184,112,30,.14);color:var(--warn);padding:16px 20px;
border-radius:16px;margin-bottom:24px;line-height:1.6}
@media(max-width:720px){.page{grid-template-columns:1fr}}
"""


def render_html(docs: list[DocRow], *, used_vision: bool) -> str:
    totals: dict[str, int] = {}
    escalation_candidates = 0
    for doc in docs:
        for method, count in doc.method_counts.items():
            totals[method] = totals.get(method, 0) + count
        escalation_candidates += sum(1 for p in doc.pages if p.escalated)

    parts: list[str] = [
        "<!doctype html><meta charset='utf-8'>",
        "<title>Bulletin - extraction samples</title>",
        f"<style>{CSS}</style>",
        "<h1>Extraction samples</h1>",
        "<p class='sub'>Rendered page beside the text actually extracted. "
        "Read the text. If it is wrong here, every answer built on it is wrong.</p>",
    ]

    if not used_vision:
        parts.append(
            "<div class='warnbox'><strong>Run without --vision.</strong> "
            "Pages that need a vision read are marked <span class='esc'>escalated</span> "
            "and show empty text. That is expected: this run cost nothing. "
            "Re-run with <code>--vision</code> to read them.</div>"
        )

    summary = " ".join(
        f"<span class='badge {m}'>{html.escape(m)}: {c}</span>" for m, c in sorted(totals.items())
    )
    parts.append(
        f"<div class='badges'>{summary}"
        f"<span class='badge'>documents: {len(docs)}</span>"
        f"<span class='badge'>escalated pages: {escalation_candidates}</span></div>"
    )

    for doc in docs:
        parts.append("<section class='doc'>")
        parts.append(f"<h2>{html.escape(doc.name)}</h2>")
        if doc.rejected:
            parts.append(f"<div class='rejected'>Rejected: {html.escape(doc.rejected)}</div>")
        badges = " ".join(
            f"<span class='badge {html.escape(m)}'>{html.escape(m)}: {c}</span>"
            for m, c in sorted(doc.method_counts.items())
        )
        parts.append(
            f"<div class='badges'>{badges}<span class='badge'>chars: {doc.total_chars}</span></div>"
        )

        for page in doc.pages:
            snippet = page.text[:SNIPPET_CHARS]
            more = len(page.text) - len(snippet)
            body = html.escape(snippet) if snippet else "<span class='empty'>no text</span>"
            if more > 0:
                body += f"\n\n[... {more} more characters]"
            thumb = (
                f"<img src='{page.thumbnail}' alt='page {page.page_no}'>"
                if page.thumbnail
                else "<div class='empty'>no preview</div>"
            )
            esc = " <span class='esc'>escalated</span>" if page.escalated else ""
            parts.append(
                "<div class='page'>"
                f"<div class='thumb'>{thumb}"
                f"<div class='meta'>page {page.page_no} - {html.escape(page.method)} - "
                f"{html.escape(page.lang)} - conf {page.confidence:.2f}{esc}</div>"
                f"<div class='reason'>{html.escape(page.reason)}</div></div>"
                f"<div class='text' lang='{html.escape(page.lang)}'>{body}</div>"
                "</div>"
            )
        parts.append("</section>")

    return "\n".join(parts)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Extraction/encoding report for a corpus.")
    parser.add_argument("corpus", nargs="?", default=None, help="corpus dir (default from config)")
    parser.add_argument("--vision", action="store_true", help="actually spend vision tokens")
    parser.add_argument("--limit", type=int, default=None, help="max documents")
    parser.add_argument("--max-pages", type=int, default=8, help="max pages shown per document")
    parser.add_argument("--out", type=Path, default=None, help="output HTML path")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO, format="%(levelname)s %(name)s %(message)s", stream=sys.stderr
    )
    settings = get_settings()
    root = Path(args.corpus) if args.corpus else settings.corpus_path
    if not root.exists():
        print(f"Corpus directory not found: {root}", file=sys.stderr)
        print("Put documents in corpus/ (see TASKS.md Phase 0).", file=sys.stderr)
        return 2

    provider: Provider | None = None
    if args.vision:
        from app.providers.openrouter import OpenRouterProvider

        provider = OpenRouterProvider(settings)

    files = find_documents(root, args.limit)
    if not files:
        print(f"No PDFs or images found under {root}", file=sys.stderr)
        return 2

    print(f"Reading {len(files)} document(s) from {root}...", file=sys.stderr)
    docs = [build_doc_row(p, provider, settings, args.max_pages) for p in files]

    out = args.out or (settings.reports_path / "extraction_samples.html")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render_html(docs, used_vision=args.vision), encoding="utf-8")
    print(f"Wrote {out}", file=sys.stderr)
    print("Now READ it. CLAUDE.md #8.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
