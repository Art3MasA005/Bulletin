"""Structure-aware chunking. PRD 7.1.

Three rules, in priority order:

  1. **Split on structure before length.** Headings, numbered clauses, and
     table rows are the real boundaries in an institutional document. A fee
     schedule cut mid-table produces a chunk that answers nothing.

  2. **Different budgets per language.** ~600 tokens for English, but a
     CHARACTER budget for Bangla (~1,200), because Bangla is 2-4x more
     token-expensive. Using a token budget for both silently produces Bangla
     chunks a quarter the size of the English ones.

  3. **Never split mid-conjunct.** A boundary inside a conjunct cluster
     produces two tokens that exist in no document and match no query.
     Enforced via bangla/segment.safe_split_point.

Every chunk carries `lang` (PRD 7.1) and `audience` (PRD 9 -- denormalized so
the audience filter applies in a single query, CLAUDE.md #4).
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from app.bangla.normalize import detect_lang, normalize
from app.bangla.segment import safe_split_point, split_sentences
from app.config import Settings, get_settings

logger = logging.getLogger(__name__)

# English tokens per whitespace-delimited word. A deliberate approximation:
# a real tokenizer would add a dependency and a model-specific coupling for a
# budget that is itself a tuning knob. Verified against the gold set in Phase 1.
TOKENS_PER_WORD = 1.3

# A heading is short, has no terminal punctuation, and often carries a clause
# number. Matches Latin and Bangla numerals.
_HEADING_MAX_CHARS = 90
_CLAUSE_NUMBER = re.compile(r"^\s*(?:[০-৯\d]+[.)।]?)+\s*")
_TERMINAL_PUNCT = ("।", ".", "?", "!", ":", ";", ",")

# A table row has several columns separated by wide whitespace runs.
_TABLE_ROW = re.compile(r"\S+(?:\s{2,}|\t)\S+(?:(?:\s{2,}|\t)\S+)+")


@dataclass
class Chunk:
    """One indexable unit. Mirrors the `chunks` table in PRD 9."""

    content: str
    page_no: int
    section: str | None
    lang: str
    extraction_method: str
    index: int = 0
    audience: str = "all"

    @property
    def char_count(self) -> int:
        return len(self.content)


@dataclass
class _Block:
    """A structural unit of a page: heading, table row, or paragraph."""

    text: str
    kind: str  # "heading" | "table" | "body"
    section: str | None = None


def estimate_tokens(text: str) -> int:
    """Approximate token count for the English budget."""
    words = len(text.split())
    return int(words * TOKENS_PER_WORD) + 1


def budget_for(lang: str, settings: Settings) -> tuple[str, int]:
    """Return (unit, limit) for a language.

    Bangla and mixed text both use the character budget: a mixed chunk is
    dominated by whichever script is more expensive, which is Bangla.
    """
    if lang == "en":
        return "tokens", settings.chunk_tokens_en
    return "chars", settings.chunk_chars_bn


def _measure(text: str, unit: str) -> int:
    return estimate_tokens(text) if unit == "tokens" else len(text)


def _is_heading(line: str) -> bool:
    stripped = line.strip()
    if not stripped or len(stripped) > _HEADING_MAX_CHARS:
        return False
    if stripped.endswith(_TERMINAL_PUNCT):
        return False
    # A numbered clause opener, an ALL-CAPS line, or a short title-like line.
    if _CLAUSE_NUMBER.match(stripped) and len(stripped.split()) <= 12:
        return True
    letters = [c for c in stripped if c.isalpha()]
    if letters and all(c.isupper() for c in letters if c.isascii()):
        return len(stripped.split()) <= 12
    return len(stripped.split()) <= 8


def _blocks(text: str) -> list[_Block]:
    """Break page text into structural blocks, tracking the current section.

    Consecutive table rows are kept together so a table is not fragmented row
    by row, and consecutive body lines re-join into a paragraph.
    """
    blocks: list[_Block] = []
    section: str | None = None
    buffer: list[str] = []
    buffer_kind = "body"

    def flush() -> None:
        nonlocal buffer, buffer_kind
        if buffer:
            joined = "\n".join(buffer) if buffer_kind == "table" else " ".join(buffer)
            joined = joined.strip()
            if joined:
                blocks.append(_Block(text=joined, kind=buffer_kind, section=section))
        buffer = []
        buffer_kind = "body"

    for raw_line in text.split("\n"):
        line = raw_line.strip()
        if not line:
            flush()
            continue

        if _is_heading(line):
            flush()
            section = line
            blocks.append(_Block(text=line, kind="heading", section=section))
            continue

        kind = "table" if _TABLE_ROW.search(raw_line) else "body"
        if kind != buffer_kind:
            flush()
            buffer_kind = kind
        buffer.append(line)

    flush()
    return blocks


def _split_oversized(text: str, unit: str, limit: int) -> list[str]:
    """Break a block that exceeds the budget on its own.

    Sentences first (danda-aware), then a hard cut nudged to a conjunct-safe
    position if even one sentence is too long.
    """
    pieces: list[str] = []
    current = ""

    for sentence in split_sentences(text) or [text]:
        candidate = f"{current} {sentence}".strip() if current else sentence
        if _measure(candidate, unit) <= limit:
            current = candidate
            continue
        if current:
            pieces.append(current)
            current = ""
        if _measure(sentence, unit) <= limit:
            current = sentence
            continue
        # One sentence larger than the whole budget: hard-cut it, but never
        # inside a conjunct.
        remaining = sentence
        while _measure(remaining, unit) > limit:
            approx = limit if unit == "chars" else int(limit / TOKENS_PER_WORD) * 5
            cut = safe_split_point(remaining, min(approx, len(remaining) - 1))
            if cut <= 0:
                break
            pieces.append(remaining[:cut].strip())
            remaining = remaining[cut:].strip()
        if remaining:
            current = remaining

    if current:
        pieces.append(current)
    return [p for p in pieces if p.strip()]


def _overlap_tail(text: str, unit: str, limit: int, ratio: float) -> str:
    """Trailing slice of a chunk, repeated at the head of the next one.

    Cut at a conjunct-safe point and prefer starting on a word boundary, so the
    overlap is readable text rather than a fragment.
    """
    if ratio <= 0:
        return ""
    target = int((limit if unit == "chars" else limit * 4) * ratio)
    if target <= 0 or target >= len(text):
        return text if len(text) < target else ""
    start = safe_split_point(text, len(text) - target)
    tail = text[start:]
    space = tail.find(" ")
    return tail[space + 1 :].strip() if 0 <= space < 40 else tail.strip()


def chunk_page(
    text: str,
    *,
    page_no: int,
    extraction_method: str,
    audience: str = "all",
    settings: Settings | None = None,
    start_index: int = 0,
) -> list[Chunk]:
    """Chunk one page's text. Input must already be normalized."""
    settings = settings or get_settings()
    text = text.strip()
    if not text:
        return []

    page_lang = detect_lang(text)
    unit, limit = budget_for(page_lang, settings)

    chunks: list[Chunk] = []
    current: list[str] = []
    current_section: str | None = None
    index = start_index

    def emit() -> None:
        nonlocal current, index
        body = " ".join(current).strip() if current else ""
        if not body:
            current = []
            return
        chunk_lang = detect_lang(body)
        chunks.append(
            Chunk(
                content=body,
                page_no=page_no,
                section=current_section,
                lang=chunk_lang,
                extraction_method=extraction_method,
                index=index,
                audience=audience,
            )
        )
        index += 1
        overlap = _overlap_tail(body, unit, limit, settings.chunk_overlap_ratio)
        current = [overlap] if overlap else []

    for block in _blocks(text):
        # A heading opens a new section; start a fresh chunk so the heading
        # travels with the text it introduces.
        if block.kind == "heading":
            if current and _measure(" ".join(current), unit) > limit * 0.5:
                emit()
                current = []
            current_section = block.section
            current.append(block.text)
            continue

        for piece in _split_oversized(block.text, unit, limit):
            candidate = " ".join([*current, piece]).strip()
            if _measure(candidate, unit) > limit and current:
                emit()
                candidate = " ".join([*current, piece]).strip()
            current.append(piece)
            if _measure(" ".join(current), unit) >= limit:
                emit()

    if current:
        emit()

    logger.debug(
        "chunked page_no=%d lang=%s unit=%s limit=%d chunks=%d",
        page_no,
        page_lang,
        unit,
        limit,
        len(chunks),
    )
    return chunks


def chunk_pages(
    pages: list[tuple[int, str, str]],
    *,
    audience: str = "all",
    settings: Settings | None = None,
) -> list[Chunk]:
    """Chunk a whole document.

    `pages` is a list of (page_no, text, extraction_method) -- exactly what
    pipeline.IngestResult carries, kept as a plain tuple so this module does
    not depend on the ingestion dataclasses.
    """
    settings = settings or get_settings()
    out: list[Chunk] = []
    for page_no, text, method in pages:
        out.extend(
            chunk_page(
                normalize(text),
                page_no=page_no,
                extraction_method=method,
                audience=audience,
                settings=settings,
                start_index=len(out),
            )
        )
    logger.info("chunked document pages=%d chunks=%d", len(pages), len(out))
    return out
