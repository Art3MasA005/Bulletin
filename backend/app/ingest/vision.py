"""Page render -> provider vision read.

PRD 7.1, on why this works for legacy fonts: "the encoding problem lives only
in the text layer. The page RENDERS correctly -- a human reads normal Bangla.
A vision model reading the rendered page gets correct Unicode, bypassing
conversion."

Vision is the expensive path. Per PRD 6, running it on every page exhausts a
free tier immediately, so pipeline.py calls this only on escalation.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

from app.bangla.normalize import detect_lang, normalize
from app.config import Settings, get_settings
from app.ingest.extract import render_page_png
from app.providers.base import Provider, ProviderError

logger = logging.getLogger(__name__)


@dataclass
class VisionRead:
    page_no: int
    text: str
    ok: bool
    reason: str
    png_bytes: int = 0


def read_page(
    path: Path,
    page_no: int,
    provider: Provider,
    *,
    lang_hint: str = "auto",
    settings: Settings | None = None,
) -> VisionRead:
    """Render one page and read it with the provider's vision capability.

    Never raises: a failed vision read leaves the page with whatever text the
    cheap path produced, and the failure is logged and reported. A page that
    ends up empty is caught by pipeline.py's minimum-character check.
    """
    settings = settings or get_settings()
    try:
        png = render_page_png(path, page_no, settings)
    except Exception as exc:  # noqa: BLE001
        logger.warning("render failed doc=%s page_no=%d error=%s", path.name, page_no, exc)
        return VisionRead(page_no=page_no, text="", ok=False, reason=f"render failed: {exc}")

    try:
        raw = provider.read_page_image(png, lang_hint=lang_hint)
    except ProviderError as exc:
        logger.warning(
            "vision read failed doc=%s page_no=%d provider=%s error=%s",
            path.name,
            page_no,
            provider.name,
            exc,
        )
        return VisionRead(page_no=page_no, text="", ok=False, reason=str(exc), png_bytes=len(png))

    # Vision output enters the index through the same normalization as native
    # text -- CLAUDE.md #6 symmetry.
    text = normalize(raw)
    logger.info(
        "vision read doc=%s page_no=%d chars=%d lang=%s",
        path.name,
        page_no,
        len(text),
        detect_lang(text),
    )
    return VisionRead(
        page_no=page_no,
        text=text,
        ok=bool(text.strip()),
        reason="ok" if text.strip() else "vision returned no text",
        png_bytes=len(png),
    )
