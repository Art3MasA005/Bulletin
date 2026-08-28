"""Routine photo -> structured JSON. PRD 8.2 steps 2-3.

This module reads a student's attached routine or registration slip into
RoutineExtraction. It deliberately does NOT retrieve, generate, or index
anything:

  * CLAUDE.md #2 -- nothing here ever reaches `chunks`. There is no embedding
    call in this file and there must never be one.
  * CLAUDE.md #3 -- the result is returned UNCONFIRMED. Turning it into a query
    requires ConfirmedEntities, which only the confirmation endpoint can mint.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

from app.attachments.schemas import RoutineExtraction
from app.config import Settings, get_settings
from app.ingest.extract import IMAGE_SUFFIXES, render_page_png
from app.providers.base import Provider, ProviderError

logger = logging.getLogger(__name__)

ROUTINE_PROMPT = (
    "This image is a university class routine, exam routine, or course "
    "registration slip belonging to a student.\n\n"
    "Extract every course listed, one entry per course.\n\n"
    "Rules:\n"
    "- Read course codes character by character. They are alphanumeric and "
    "a single wrong character makes the entry useless.\n"
    "- Do not infer, correct, or complete a code you cannot actually read.\n"
    "- Read each row across carefully. If the grid is skewed or the rows are "
    "hard to align, lower the confidence for the affected entries rather than "
    "guessing which row a value belongs to.\n"
    "- confidence is per course and reflects how certain you are of THAT "
    "course code specifically. Use below 0.9 whenever the text is blurred, "
    "cropped, skewed, or ambiguous between similar characters such as 1/7, "
    "0/O, 5/S, or 8/B.\n"
    "- Bangla text may appear; transcribe it in Unicode Bangla.\n"
    "- If a field is not printed, leave it null. Do not invent it.\n\n"
    "Return JSON matching the schema exactly."
)


@dataclass
class AttachmentExtraction:
    """Extraction outcome for one attachment, plus what the UI needs to render it."""

    attachment_id: str
    extraction: RoutineExtraction
    flagged_codes: list[str]
    ok: bool
    reason: str

    @property
    def requires_review(self) -> bool:
        return bool(self.flagged_codes)


def _attachment_png(path: Path, settings: Settings) -> bytes:
    """Get PNG bytes for an attachment, whether it is an image or a PDF.

    PRD 7.1 treats an image as a one-page document; the same holds here. Only
    the first page of a multi-page PDF attachment is read -- a routine is one
    page, and reading more multiplies the most expensive call in the product.
    """
    if path.suffix.lower() in IMAGE_SUFFIXES:
        return path.read_bytes()
    return render_page_png(path, 1, settings)


def extract_routine(
    path: Path,
    provider: Provider,
    *,
    attachment_id: str,
    settings: Settings | None = None,
) -> AttachmentExtraction:
    """Read a routine attachment into a typed, UNCONFIRMED extraction.

    Never raises: a failed extraction returns ok=False with an empty course
    list, and the UI asks the user to add the courses by hand rather than
    presenting a wrong answer.
    """
    settings = settings or get_settings()
    floor = settings.extraction_confidence_floor

    size_mb = path.stat().st_size / (1024 * 1024) if path.exists() else 0.0
    if size_mb > settings.attachment_max_mb:
        return AttachmentExtraction(
            attachment_id=attachment_id,
            extraction=RoutineExtraction(),
            flagged_codes=[],
            ok=False,
            reason=(
                f"This file is {size_mb:.1f} MB. The limit is "
                f"{settings.attachment_max_mb} MB. Take a smaller photo and try again."
            ),
        )

    try:
        png = _attachment_png(path, settings)
    except Exception as exc:  # noqa: BLE001
        logger.warning("attachment render failed attachment_id=%s error=%s", attachment_id, exc)
        return AttachmentExtraction(
            attachment_id=attachment_id,
            extraction=RoutineExtraction(),
            flagged_codes=[],
            ok=False,
            reason=f"This file could not be read ({exc}).",
        )

    try:
        extraction = provider.extract_structured(png, RoutineExtraction, prompt=ROUTINE_PROMPT)
    except ProviderError as exc:
        logger.warning(
            "attachment extraction failed attachment_id=%s provider=%s error=%s",
            attachment_id,
            provider.name,
            exc,
        )
        return AttachmentExtraction(
            attachment_id=attachment_id,
            extraction=RoutineExtraction(),
            flagged_codes=[],
            ok=False,
            reason="The courses could not be read from this file. Add them by hand.",
        )

    flagged = [c.code for c in extraction.flagged(floor)]
    logger.info(
        "attachment extracted attachment_id=%s courses=%d flagged=%d floor=%.2f",
        attachment_id,
        len(extraction.courses),
        len(flagged),
        floor,
    )
    return AttachmentExtraction(
        attachment_id=attachment_id,
        extraction=extraction,
        flagged_codes=flagged,
        ok=bool(extraction.courses),
        reason="ok" if extraction.courses else "no courses found in this file",
    )
