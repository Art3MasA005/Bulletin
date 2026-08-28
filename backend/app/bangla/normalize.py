"""Bangla normalization -- THE SINGLE SOURCE OF TRUTH.

CLAUDE.md warning #6: ingestion and query must both call this module. Never
inline normalization at a call site. Asymmetry between the two paths destroys
retrieval silently -- no exception, no warning, just a confident "not found".

Two entry points, both here so symmetry is enforceable by import:

    normalize(text)            canonical, human-readable. Used for chunk
                               content, citation snippets, and as the input to
                               embedding. Preserves Bangla digits and
                               punctuation so a citation stays verifiable.

    normalize_for_match(text)  additionally folds digits and strips
                               punctuation. Used for the lexical arm only,
                               where exact-token match matters more than
                               readability.
"""

from __future__ import annotations

import re
import unicodedata
from functools import lru_cache

from bnunicodenormalizer import Normalizer

# U+0980-U+09FF is the Bengali block.
BANGLA_RANGE = (0x0980, 0x09FF)
DANDA = "।"  # Bangla full stop
DOUBLE_DANDA = "॥"

# Removed unconditionally: invisible characters that carry no Bangla meaning
# but break token equality between an ingested chunk and a typed query.
# ZWNJ (200C) and ZWJ (200D) are NOT stripped here -- they control conjunct
# formation and are the normalizer's business, not ours.
_STRIP_INVISIBLE = dict.fromkeys(
    [
        0x200B,  # zero-width space
        0xFEFF,  # BOM / zero-width no-break space
        0x00AD,  # soft hyphen
        0x180E,  # Mongolian vowel separator
    ]
)

# Whitespace variants folded to a plain space.
_SPACE_VARIANTS = dict.fromkeys(
    [
        0x00A0,
        0x2000,
        0x2001,
        0x2002,
        0x2003,
        0x2004,
        0x2005,
        0x2006,
        0x2007,
        0x2008,
        0x2009,
        0x200A,
        0x202F,
        0x205F,
        0x3000,
    ],
    " ",
)

# Typographic variants that differ between a PDF and a phone keyboard.
_PUNCT_FOLD = {
    "‘": "'",
    "’": "'",  # curly single quotes
    "“": '"',
    "”": '"',  # curly double quotes
    "–": "-",
    "—": "-",  # en / em dash
    "−": "-",
    "‐": "-",
    "‑": "-",  # minus, hyphen, nb-hyphen
    "…": "...",
    DOUBLE_DANDA: DANDA,
}

BANGLA_DIGITS = "০১২৩৪৫৬৭৮৯"
_DIGIT_FOLD = {ord(bn): str(i) for i, bn in enumerate(BANGLA_DIGITS)}

_WS_RUN = re.compile(r"[ \t\f\r]+")
_BLANK_LINES = re.compile(r"\n{3,}")
# Strip punctuation but keep word chars and the whole Bengali block.
_PUNCT_RUN = re.compile(r"[^\w\sঀ-৿]+", re.UNICODE)


@lru_cache(maxsize=1)
def _normalizer() -> Normalizer:
    """bnunicodenormalizer is reusable but costly to construct."""
    return Normalizer()


def has_bangla(text: str) -> bool:
    lo, hi = BANGLA_RANGE
    return any(lo <= ord(ch) <= hi for ch in text)


def bangla_ratio(text: str) -> float:
    """Fraction of alphabetic characters sitting in the Bengali block.

    Used by classify.py and bijoy.py to score conversion quality.
    """
    letters = [ch for ch in text if ch.isalpha()]
    if not letters:
        return 0.0
    lo, hi = BANGLA_RANGE
    return sum(1 for ch in letters if lo <= ord(ch) <= hi) / len(letters)


def _normalize_word(word: str) -> str:
    """Run one whitespace-delimited token through bnunicodenormalizer.

    The library operates per word and returns None for input it cannot parse;
    in that case keep the original rather than dropping content on the floor.
    """
    if not has_bangla(word):
        return word
    try:
        result = _normalizer()(word)
    except Exception:  # noqa: BLE001 -- normalization must never kill an ingest
        return word
    normalized = result.get("normalized") if isinstance(result, dict) else None
    return normalized if normalized else word


def normalize(text: str) -> str:
    """Canonical normalization. Call this from ingestion AND from query."""
    if not text:
        return ""

    text = unicodedata.normalize("NFC", text)
    text = text.translate(_STRIP_INVISIBLE)
    text = text.translate(_SPACE_VARIANTS)
    for src, dst in _PUNCT_FOLD.items():
        text = text.replace(src, dst)

    # Per-word Bangla normalization, preserving line structure. Chunking splits
    # on headings and blank lines, so newlines must survive this step.
    lines_out: list[str] = []
    for line in text.split("\n"):
        words = [_normalize_word(w) for w in line.split(" ")]
        lines_out.append(" ".join(w for w in words if w != ""))
    text = "\n".join(lines_out)

    text = _WS_RUN.sub(" ", text)
    text = _BLANK_LINES.sub("\n\n", text)
    return "\n".join(line.strip() for line in text.split("\n")).strip()


def normalize_for_match(text: str) -> str:
    """Lexical-arm normalization: canonical form, digits folded, punctuation out.

    Bangla digits fold to ASCII so a query typed in Bangla numerals matches a
    document printed in Latin ones. Course codes ("CSE 4101") survive intact.
    """
    text = normalize(text).casefold()
    text = text.translate(_DIGIT_FOLD)
    text = _PUNCT_RUN.sub(" ", text)
    return _WS_RUN.sub(" ", text).strip()


def detect_lang(text: str) -> str:
    """Coarse language tag for a chunk or a query: 'bn' | 'en' | 'mixed'.

    Deliberately crude -- it selects a lexical index (tsvector vs pg_trgm) and
    a chunk budget, not a translation. PRD 7.1 tags `lang` per chunk.
    """
    ratio = bangla_ratio(text)
    if ratio >= 0.6:
        return "bn"
    if ratio <= 0.15:
        return "en"
    return "mixed"
