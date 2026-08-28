"""Encoding classification: native_text | legacy | scanned.

PRD 7.1 routing table. This module decides which extraction path a page takes,
and it is the single most consequential decision in ingestion: misroute a
legacy page as native_text and it indexes as garbage, with no error anywhere
(CLAUDE.md warning #7).

Evidence, in order of trust:

  1. The PDF font table. A page set in SutonnyMJ says so outright.
  2. Character-profile analysis of the extracted text (bangla/bijoy.py).
  3. Character count relative to page area -- an empty text layer on a page
     that contains a full-page image is a scan.
  4. Text-layer QUALITY (ingest/ocr_quality.py). A scan carrying a bad OCR
     text layer looks like clean native text to every check above -- it is
     Unicode, it is not Bijoy, and it is long enough. It is also wrong. This
     is the state the PRD 7.1 routing table does not model, and it is why a
     page can be `native_text` and still need vision.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from enum import StrEnum

from app.bangla import bijoy
from app.bangla.normalize import bangla_ratio, detect_lang
from app.config import Settings, get_settings
from app.ingest.extract import DocumentExtraction, PageExtraction
from app.ingest.ocr_quality import text_quality

logger = logging.getLogger(__name__)


class ExtractionMethod(StrEnum):
    """How a page's text was (or must be) obtained. Persisted on `chunks`."""

    NATIVE_TEXT = "native_text"
    LEGACY = "legacy"
    SCANNED = "scanned"


@dataclass(frozen=True)
class PageClassification:
    page_no: int
    method: ExtractionMethod
    lang: str
    confidence: float
    reason: str
    # 1.0 for a page this check does not apply to (Bangla, or too short).
    quality: float = 1.0
    quality_reason: str = ""
    poor_text_layer: bool = False

    @property
    def needs_vision(self) -> bool:
        """Scanned pages always need vision; legacy pages only if conversion fails.

        A native_text page with `poor_text_layer` set also needs it -- see the
        quality note in the module docstring.
        """
        return self.method is ExtractionMethod.SCANNED or self.poor_text_layer


def classify_page(page: PageExtraction, settings: Settings | None = None) -> PageClassification:
    """Classify one page. Cheap: no model calls, no conversion."""
    settings = settings or get_settings()
    text = page.text

    # ── No usable text layer -> scanned ─────────────────────────────────────
    if page.char_count < settings.scanned_chars_per_page:
        reason = (
            f"only {page.char_count} chars in the text layer"
            f" (floor {settings.scanned_chars_per_page})"
        )
        if page.image_count:
            reason += f", {page.image_count} image(s) on the page"
        return PageClassification(
            page_no=page.page_no,
            method=ExtractionMethod.SCANNED,
            lang="unknown",
            confidence=0.9 if page.image_count else 0.7,
            reason=reason,
        )

    # ── Font table: direct evidence, trusted first ──────────────────────────
    legacy_fonts = [f for f in page.fonts if bijoy.font_is_legacy(f)]
    signal = bijoy.legacy_signal(text)

    if legacy_fonts:
        # Font says legacy. If the text also looks legacy, that is a certainty.
        confidence = 0.95 if signal >= 0.35 else 0.8
        return PageClassification(
            page_no=page.page_no,
            method=ExtractionMethod.LEGACY,
            lang="bn",
            confidence=confidence,
            reason=f"legacy font {legacy_fonts[0]!r}, text signal {signal:.2f}",
        )

    # ── No font evidence: fall back to the character profile ────────────────
    if signal >= 0.35:
        return PageClassification(
            page_no=page.page_no,
            method=ExtractionMethod.LEGACY,
            lang="bn",
            confidence=round(signal, 2),
            reason=f"no legacy font named, but text profile scores {signal:.2f}",
        )

    lang = detect_lang(text)

    # The text layer is Unicode and is not Bijoy. That does not make it right:
    # a scan with a bad OCR layer reaches exactly this point looking clean.
    quality = text_quality(text)
    poor = quality.below(settings.ocr_quality_floor)
    reason = f"clean text layer, lang={lang}, bangla={bangla_ratio(text):.0%}"
    if poor:
        reason = (
            f"text layer present but poor: quality {quality.score:.2f} below floor "
            f"{settings.ocr_quality_floor:.2f} ({quality.reason})"
        )

    return PageClassification(
        page_no=page.page_no,
        method=ExtractionMethod.NATIVE_TEXT,
        lang=lang,
        # Confidence follows the weaker of the two signals: a clean-looking
        # page with a 0.53 text layer is not a confident native_text read.
        confidence=round(min(1.0 - signal, quality.score), 2),
        reason=reason,
        quality=quality.score,
        quality_reason=quality.reason,
        poor_text_layer=poor,
    )


@dataclass
class DocumentClassification:
    pages: list[PageClassification]

    @property
    def method(self) -> ExtractionMethod:
        """The document-level label: the most severe method any page needs.

        A 40-page circular with two scanned pages is not a native_text
        document -- reporting it as one hides the pages that will need vision.
        """
        methods = {p.method for p in self.pages}
        for candidate in (
            ExtractionMethod.SCANNED,
            ExtractionMethod.LEGACY,
            ExtractionMethod.NATIVE_TEXT,
        ):
            if candidate in methods:
                return candidate
        return ExtractionMethod.NATIVE_TEXT

    @property
    def lang(self) -> str:
        langs = [p.lang for p in self.pages if p.lang != "unknown"]
        if not langs:
            return "unknown"
        if all(x == "bn" for x in langs):
            return "bn"
        if all(x == "en" for x in langs):
            return "en"
        return "mixed"

    @property
    def vision_pages(self) -> list[int]:
        return [p.page_no for p in self.pages if p.needs_vision]

    def counts(self) -> dict[str, int]:
        out = {m.value: 0 for m in ExtractionMethod}
        for p in self.pages:
            out[p.method.value] += 1
        return out


def classify_document(
    extraction: DocumentExtraction, settings: Settings | None = None
) -> DocumentClassification:
    settings = settings or get_settings()
    pages = [classify_page(p, settings) for p in extraction.pages]
    result = DocumentClassification(pages=pages)
    logger.info(
        "classified doc=%s method=%s lang=%s counts=%s vision_pages=%d",
        extraction.path.name,
        result.method,
        result.lang,
        result.counts(),
        len(result.vision_pages),
    )
    return result
