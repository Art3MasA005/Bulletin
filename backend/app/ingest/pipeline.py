"""Extraction escalation and per-page checkpointing. PRD 7.1, 11.

The routing table, implemented:

    extract text + read PDF font table
        |- English text layer     -> quality score (ingest/ocr_quality.py)
        |                              |- high -> use directly
        |                              '- low  -> render PNG -> vision read
        |- Unicode Bangla layer   -> normalize -> use
        |- Legacy-font Bangla     -> Bijoy convert -> confidence score
        |                              |- high -> use
        |                              '- low  -> render PNG -> vision read
        '- No text layer          -> render PNG -> vision read

The quality branch is not in the PRD 7.1 table. It was added after the real
corpus turned out to be scans carrying a bad OCR text layer -- a state that
passes every other check and indexes as noise. See ingest/ocr_quality.py.

Cheap path first, escalate only on failure -- PRD 6: vision on every page
exhausts a free tier immediately.

Checkpointing is per page (PRD 11) because free hosts kill long jobs. A restart
resumes at the first unfinished page rather than reprocessing the document and
re-spending vision tokens.
"""

from __future__ import annotations

import json
import logging
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from app.bangla import bijoy
from app.bangla.normalize import detect_lang, normalize
from app.config import Settings, get_settings
from app.ingest.classify import (
    DocumentClassification,
    ExtractionMethod,
    classify_document,
)
from app.ingest.extract import DocumentRejected, extract_document
from app.ingest.ocr_quality import repair_course_codes
from app.ingest.vision import read_page
from app.providers.base import Provider

logger = logging.getLogger(__name__)

CHECKPOINT_VERSION = 1


@dataclass
class PageResult:
    """Final text for one page, and the audit trail of how it was obtained."""

    page_no: int
    text: str
    method: str  # ExtractionMethod value, as finally used
    lang: str
    confidence: float
    escalated: bool
    reason: str

    @property
    def char_count(self) -> int:
        return len(self.text.strip())

    @property
    def needs_retry(self) -> bool:
        """Whether this page still has work left, despite being checkpointed.

        A checkpoint records completed work. A page that wanted vision and did
        not get it -- no provider configured, a 429, a failed read -- is not
        completed work: it fell back to text that the routing table already
        judged unusable. Treating it as done is how a transient rate limit
        turns into a permanently badly-indexed page.
        """
        return self.escalated and (
            "vision read failed" in self.reason
            or "vision unavailable" in self.reason
            or "no provider configured" in self.reason
        )


@dataclass
class IngestResult:
    path: Path
    pages: list[PageResult] = field(default_factory=list)
    rejected: str | None = None
    reject_code: str | None = None

    @property
    def total_chars(self) -> int:
        return sum(p.char_count for p in self.pages)

    @property
    def escalated_pages(self) -> list[int]:
        return [p.page_no for p in self.pages if p.escalated]

    @property
    def ok(self) -> bool:
        return self.rejected is None and bool(self.pages)

    def method_counts(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for page in self.pages:
            counts[page.method] = counts.get(page.method, 0) + 1
        return counts


# ── checkpointing ───────────────────────────────────────────────────────────


def _checkpoint_path(path: Path, settings: Settings) -> Path:
    ckpt_dir = settings.reports_path / "checkpoints"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    return ckpt_dir / f"{path.stem}.ckpt.json"


def load_checkpoint(path: Path, settings: Settings) -> dict[int, PageResult]:
    """Return already-processed pages, keyed by page number."""
    ckpt = _checkpoint_path(path, settings)
    if not ckpt.exists():
        return {}
    try:
        data = json.loads(ckpt.read_text(encoding="utf-8"))
        if data.get("version") != CHECKPOINT_VERSION:
            return {}
        return {int(k): PageResult(**v) for k, v in data.get("pages", {}).items()}
    except Exception as exc:  # noqa: BLE001 -- a bad checkpoint just means redo the work
        logger.warning("checkpoint unreadable doc=%s error=%s", path.name, exc)
        return {}


def save_checkpoint(path: Path, pages: dict[int, PageResult], settings: Settings) -> None:
    ckpt = _checkpoint_path(path, settings)
    payload = {
        "version": CHECKPOINT_VERSION,
        "doc": path.name,
        "updated_at": datetime.now(UTC).isoformat(),
        "pages": {str(k): asdict(v) for k, v in pages.items()},
    }
    ckpt.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


# ── the escalation policy ───────────────────────────────────────────────────


def process_page(
    path: Path,
    page_index: int,
    extraction,  # DocumentExtraction
    classification: DocumentClassification,
    provider: Provider | None,
    settings: Settings,
) -> PageResult:
    """Run one page through the routing table.

    `provider` may be None, in which case escalation is recorded as needed but
    not performed -- that is how `make extract-report` inspects a corpus for
    free before spending any vision tokens.
    """
    page = extraction.pages[page_index]
    page_class = classification.pages[page_index]
    page_no = page.page_no

    def vision(lang_hint: str, why: str) -> PageResult | None:
        if provider is None:
            return PageResult(
                page_no=page_no,
                text="",
                method=ExtractionMethod.SCANNED.value,
                lang=page_class.lang,
                confidence=0.0,
                escalated=True,
                reason=f"{why}; vision needed but no provider configured",
            )
        result = read_page(path, page_no, provider, lang_hint=lang_hint, settings=settings)
        if not result.ok:
            return None
        return PageResult(
            page_no=page_no,
            text=result.text,
            method=ExtractionMethod.SCANNED.value,
            lang=detect_lang(result.text),
            confidence=0.8,
            escalated=True,
            reason=f"{why}; vision read succeeded",
        )

    # ── No text layer -> straight to vision ─────────────────────────────────
    if page_class.method is ExtractionMethod.SCANNED:
        got = vision(page_class.lang, page_class.reason)
        if got is not None:
            return got
        return PageResult(
            page_no=page_no,
            text="",
            method=ExtractionMethod.SCANNED.value,
            lang="unknown",
            confidence=0.0,
            escalated=True,
            reason=f"{page_class.reason}; vision read failed",
        )

    # ── Legacy font -> convert, escalate on low confidence ──────────────────
    if page_class.method is ExtractionMethod.LEGACY:
        converted = bijoy.convert(page.text)
        if converted.confidence >= settings.bijoy_confidence_floor:
            return PageResult(
                page_no=page_no,
                text=converted.text,
                method=ExtractionMethod.LEGACY.value,
                lang="bn",
                confidence=converted.confidence,
                escalated=False,
                reason=f"bijoy conversion accepted ({converted.reason})",
            )
        why = (
            f"bijoy confidence {converted.confidence:.2f} below floor "
            f"{settings.bijoy_confidence_floor:.2f} ({converted.reason})"
        )
        got = vision("bn", why)
        if got is not None:
            return got
        # Vision unavailable or failed: keep the low-confidence conversion but
        # carry the real score, so downstream can report the document honestly
        # rather than presenting garbage as a clean read.
        return PageResult(
            page_no=page_no,
            text=converted.text,
            method=ExtractionMethod.LEGACY.value,
            lang="bn",
            confidence=converted.confidence,
            escalated=True,
            reason=f"{why}; vision unavailable, kept low-confidence conversion",
        )

    # ── Native text layer, but the OCR is bad -> vision ─────────────────────
    #
    # The page renders correctly; only its text layer is wrong. Same escape
    # hatch as the legacy-font path, for the same reason (PRD 7.1).
    if page_class.poor_text_layer:
        why = page_class.reason
        if provider is not None:
            got = vision(page_class.lang, why)
            if got is not None:
                return got
        # No provider, or the vision read failed. Keep the poor text rather
        # than dropping the page, but carry the low quality as the confidence
        # so `make extract-report` and the documents list both show it.
        repaired, repairs = repair_course_codes(normalize(page.text))
        return PageResult(
            page_no=page_no,
            text=repaired,
            method=ExtractionMethod.NATIVE_TEXT.value,
            lang=page_class.lang,
            confidence=page_class.quality,
            escalated=True,
            reason=f"{why}; vision unavailable, kept the poor text layer",
        )

    # ── Native text layer -> normalize and use ──────────────────────────────
    text, repairs = repair_course_codes(normalize(page.text))
    if repairs:
        logger.info("repaired doc=%s page_no=%d ocr_course_codes=%d", path.name, page_no, repairs)
    return PageResult(
        page_no=page_no,
        text=text,
        method=ExtractionMethod.NATIVE_TEXT.value,
        lang=detect_lang(text),
        confidence=page_class.confidence,
        escalated=False,
        reason=page_class.reason,
    )


def ingest_document(
    path: Path,
    provider: Provider | None = None,
    *,
    settings: Settings | None = None,
    resume: bool = True,
) -> IngestResult:
    """Extract, classify, and escalate a whole document, checkpointing as it goes."""
    settings = settings or get_settings()

    try:
        extraction = extract_document(path, settings)
    except DocumentRejected as exc:
        logger.warning("rejected doc=%s code=%s reason=%s", path.name, exc.code, exc.reason)
        return IngestResult(path=path, rejected=exc.reason, reject_code=exc.code)

    classification = classify_document(extraction, settings)
    checkpointed: dict[int, PageResult] = load_checkpoint(path, settings) if resume else {}
    # A page whose escalation never happened is retried on the next run that
    # has a provider; everything else is skipped.
    done = {no: page for no, page in checkpointed.items() if not page.needs_retry}
    if checkpointed:
        logger.info(
            "resuming doc=%s completed_pages=%d retrying_pages=%d",
            path.name,
            len(done),
            len(checkpointed) - len(done),
        )

    for index, page in enumerate(extraction.pages):
        if page.page_no in done:
            continue
        result = process_page(path, index, extraction, classification, provider, settings)
        done[page.page_no] = result
        # Checkpoint after EVERY page: a free host can kill the job at any
        # moment and a vision token spent twice is a token wasted (PRD 11).
        save_checkpoint(path, done, settings)
        logger.info(
            "page done doc=%s page_no=%d method=%s chars=%d escalated=%s conf=%.2f",
            path.name,
            result.page_no,
            result.method,
            result.char_count,
            result.escalated,
            result.confidence,
        )

    pages = [done[n] for n in sorted(done)]
    result = IngestResult(path=path, pages=pages)

    # PRD 7.1: reject under 50 chars extracted AFTER ALL PATHS. This is the
    # last place that check can honestly be made.
    if result.total_chars < settings.min_extracted_chars:
        reason = (
            f"Only {result.total_chars} characters could be read from this "
            "document, even after trying to read the pages as images. It may be "
            "blank or unreadable. Check the file and upload again."
        )
        logger.warning("rejected-after-ingest doc=%s chars=%d", path.name, result.total_chars)
        return IngestResult(path=path, pages=pages, rejected=reason, reject_code="empty_extraction")

    logger.info(
        "ingest complete doc=%s pages=%d chars=%d methods=%s escalated=%s",
        path.name,
        len(pages),
        result.total_chars,
        result.method_counts(),
        result.escalated_pages,
    )
    return result
