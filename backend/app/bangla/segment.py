"""Sentence segmentation that understands both '.' and the Bangla danda.

PRD 7.1: "Bangla sentences end at danda (U+0964), which standard splitters
miss." A splitter that only knows '.' treats an entire Bangla paragraph as one
sentence, which then blows through the chunk budget and gets cut mid-word.

Also exports the conjunct-safety check chunk.py depends on: a chunk boundary
must never fall inside a conjunct cluster, because splitting across a hasant
produces two tokens that exist in no document and match no query.
"""

from __future__ import annotations

import re

DANDA = "।"
DOUBLE_DANDA = "॥"
HASANT = "্"  # virama -- binds two consonants into a conjunct

# Combining marks: vowel signs, nukta, and the hasant itself. A boundary
# immediately before any of these would orphan the mark.
_COMBINING_LO, _COMBINING_HI = 0x09BC, 0x09CD

# Abbreviations after which a '.' is not a sentence end.
_ABBREVIATIONS = {
    "dr",
    "mr",
    "mrs",
    "ms",
    "prof",
    "sr",
    "jr",
    "st",
    "vs",
    "etc",
    "e.g",
    "i.e",
    "no",
    "vol",
    "fig",
    "dept",
    "univ",
    "approx",
    "ph.d",
    "m.sc",
    "b.sc",
    "m.a",
    "b.a",
    "sec",
    "art",
    "cl",
}

_SENTENCE_END = re.compile(rf"([.?!{DANDA}{DOUBLE_DANDA}])(\s+|$)")
_TRAILING_TOKEN = re.compile(r"([A-Za-z.]+)\.$")


def is_conjunct_boundary(text: str, index: int) -> bool:
    """True when splitting `text` at `index` would break a conjunct.

    A split is unsafe when the character before the cut is a hasant (the next
    consonant belongs to the same cluster) or when the character at the cut is
    a combining mark that would be orphaned from its base.
    """
    if index <= 0 or index >= len(text):
        return False
    if text[index - 1] == HASANT:
        return True
    return _COMBINING_LO <= ord(text[index]) <= _COMBINING_HI


def safe_split_point(text: str, index: int, *, search: int = 12) -> int:
    """Nudge `index` to the nearest position that does not break a conjunct.

    Walks backwards first (shorter chunk is safer than a broken one), then
    forwards. Returns the original index if nothing safe is nearby.
    """
    if not is_conjunct_boundary(text, index):
        return index
    for offset in range(1, search + 1):
        back = index - offset
        if back > 0 and not is_conjunct_boundary(text, back):
            return back
    for offset in range(1, search + 1):
        fwd = index + offset
        if fwd < len(text) and not is_conjunct_boundary(text, fwd):
            return fwd
    return index


def _is_abbreviation(chunk: str) -> bool:
    match = _TRAILING_TOKEN.search(chunk.strip())
    if not match:
        return False
    token = match.group(1).rstrip(".").lower()
    return token in _ABBREVIATIONS or (len(token) == 1 and token.isalpha())


def split_sentences(text: str) -> list[str]:
    """Split into sentences on '.', '?', '!', danda and double danda.

    Abbreviation-aware for Latin text; the danda has no abbreviation ambiguity,
    so Bangla splits cleanly.
    """
    if not text.strip():
        return []

    sentences: list[str] = []
    start = 0
    for match in _SENTENCE_END.finditer(text):
        end = match.end(1)
        candidate = text[start:end]
        if match.group(1) == "." and _is_abbreviation(candidate):
            continue
        stripped = candidate.strip()
        if stripped:
            sentences.append(stripped)
        start = match.end()

    tail = text[start:].strip()
    if tail:
        sentences.append(tail)
    return sentences


def split_paragraphs(text: str) -> list[str]:
    """Blank-line separated blocks, preserved for structure-aware chunking."""
    return [block.strip() for block in re.split(r"\n\s*\n", text) if block.strip()]
