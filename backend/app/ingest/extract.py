"""PyMuPDF text extraction plus font-table inspection.

PRD 7.1. Two jobs:

  1. Pull the text layer out of a PDF, page by page.
  2. Read the PDF font table, which is how a legacy ASCII-mapped font is
     identified reliably. Guessing from the text alone works (bangla/bijoy.py
     does it), but the font name is direct evidence and should win.

Rejection happens here and is loud. PRD 7.1: "Silently indexing an empty
document produces permanent unexplained 'not found' answers -- the worst
failure this product has."
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path

import pymupdf

from app.config import Settings, get_settings

logger = logging.getLogger(__name__)

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff", ".bmp"}
PDF_SUFFIXES = {".pdf"}
# What a corpus walk may pick up. PRD 7.1: "an image is a one-page document".
SUPPORTED_SUFFIXES = PDF_SUFFIXES | IMAGE_SUFFIXES


class DocumentRejected(Exception):
    """Raised for a document that must not be ingested, with a user-facing reason.

    The message is shown to an admin in the documents list (DESIGN 6.6), so it
    says what happened and what to do -- DESIGN 9 voice rules.
    """

    def __init__(self, reason: str, *, code: str) -> None:
        super().__init__(reason)
        self.reason = reason
        self.code = code


@dataclass
class PageExtraction:
    """Raw text layer for one page, before any classification or conversion."""

    page_no: int  # 1-based, matches the citation the user sees
    text: str
    fonts: list[str] = field(default_factory=list)
    width: float = 0.0
    height: float = 0.0
    image_count: int = 0

    @property
    def char_count(self) -> int:
        return len(self.text.strip())


@dataclass
class DocumentExtraction:
    """Result of reading every page's text layer."""

    path: Path
    page_count: int
    pages: list[PageExtraction]
    is_image: bool = False

    @property
    def total_chars(self) -> int:
        return sum(p.char_count for p in self.pages)

    @property
    def fonts(self) -> set[str]:
        return {f for p in self.pages for f in p.fonts}


def _reject_on_size(path: Path, settings: Settings) -> None:
    size_mb = path.stat().st_size / (1024 * 1024)
    if size_mb > settings.max_upload_mb:
        raise DocumentRejected(
            f"This file is {size_mb:.1f} MB. The limit is {settings.max_upload_mb} MB. "
            "Split it into smaller files and upload again.",
            code="too_large",
        )


def open_document(path: Path, settings: Settings | None = None) -> pymupdf.Document:
    """Open a PDF or image, rejecting anything that cannot be ingested.

    Rejection reasons are checked in the order a user would care about.
    """
    settings = settings or get_settings()
    if not path.exists():
        raise DocumentRejected(f"File not found: {path}", code="missing")

    _reject_on_size(path, settings)

    try:
        doc = pymupdf.open(path)
    except Exception as exc:  # noqa: BLE001 -- surface a readable reason, not a traceback
        raise DocumentRejected(
            f"This file could not be opened as a PDF or image ({exc}). "
            "Check that it is not corrupted and upload again.",
            code="unreadable",
        ) from exc

    if doc.needs_pass:
        doc.close()
        raise DocumentRejected(
            "This PDF is password protected. Remove the password and upload again.",
            code="encrypted",
        )

    if doc.page_count > settings.max_pages:
        pages = doc.page_count
        doc.close()
        raise DocumentRejected(
            f"This document has {pages} pages. The limit is {settings.max_pages}. "
            "Split it and upload the parts separately.",
            code="too_many_pages",
        )

    return doc


def page_fonts(doc: pymupdf.Document, page_index: int) -> list[str]:
    """Font base-names used on one page, from the PDF font table.

    This is the reliable legacy-encoding signal: a page set in SutonnyMJ names
    it here even when the extracted text looks like ordinary Latin letters.
    """
    names: list[str] = []
    try:
        for font in doc.get_page_fonts(page_index, full=True):
            # (xref, ext, type, basefont, name, encoding, referencer)
            basefont = font[3] if len(font) > 3 else ""
            if basefont:
                names.append(str(basefont))
    except Exception as exc:  # noqa: BLE001 -- a missing font table is not fatal
        logger.warning("font table unreadable page_no=%d error=%s", page_index + 1, exc)
    return names


def extract_page(doc: pymupdf.Document, page_index: int) -> PageExtraction:
    """Extract one page's text layer and font list. Never raises on bad pages."""
    page = doc.load_page(page_index)
    try:
        text = page.get_text("text") or ""
    except Exception as exc:  # noqa: BLE001 -- one bad page must not kill the doc
        logger.warning("text extraction failed page_no=%d error=%s", page_index + 1, exc)
        text = ""

    try:
        image_count = len(page.get_images(full=True))
    except Exception:  # noqa: BLE001
        image_count = 0

    rect = page.rect
    return PageExtraction(
        page_no=page_index + 1,
        text=text,
        fonts=page_fonts(doc, page_index),
        width=rect.width,
        height=rect.height,
        image_count=image_count,
    )


def extract_document(path: Path, settings: Settings | None = None) -> DocumentExtraction:
    """Read every page's text layer.

    Does NOT reject on low character count -- that decision belongs to
    pipeline.py, which only knows the document is empty after vision escalation
    has also been tried. PRD 7.1: reject "under 50 characters extracted after
    all paths".
    """
    settings = settings or get_settings()
    doc = open_document(path, settings)
    try:
        is_image = path.suffix.lower() in IMAGE_SUFFIXES
        pages = [extract_document_page(doc, i, path) for i in range(doc.page_count)]
        result = DocumentExtraction(
            path=path,
            page_count=doc.page_count,
            pages=pages,
            is_image=is_image,
        )
    finally:
        doc.close()

    logger.info(
        "extracted doc=%s pages=%d chars=%d fonts=%s",
        path.name,
        result.page_count,
        result.total_chars,
        sorted(result.fonts)[:5],
    )
    return result


def extract_document_page(doc: pymupdf.Document, page_index: int, path: Path) -> PageExtraction:
    """extract_page with per-page logging, as CLAUDE.md requires."""
    page = extract_page(doc, page_index)
    logger.debug(
        "page extracted doc=%s page_no=%d chars=%d fonts=%s",
        path.name,
        page.page_no,
        page.char_count,
        page.fonts[:3],
    )
    return page


def render_page_png(path: Path, page_no: int, settings: Settings | None = None) -> bytes:
    """Render one page to PNG bytes for a vision read (ingest/vision.py).

    page_no is 1-based to match citations.
    """
    settings = settings or get_settings()
    doc = open_document(path, settings)
    try:
        page = doc.load_page(page_no - 1)
        pixmap = page.get_pixmap(dpi=settings.vision_render_dpi)
        return pixmap.tobytes("png")
    finally:
        doc.close()
