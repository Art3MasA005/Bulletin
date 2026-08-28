"""Is this text layer worth indexing? The third state PRD 7.1 does not model.

The routing table in PRD 7.1 assumes a text layer is either present and
correct, legacy-encoded, or absent. The real corpus has a fourth case, and it
is the dangerous one: **a scan with a low-quality OCR text layer**. The text is
present, it is Unicode, it is not Bijoy, and it is wrong.

classify.py cannot see that from the font table -- the page is "native_text"
with high confidence -- and nothing downstream can either. It indexes as noise.

Measured on the real Green University corpus (2026-08-28, 34 pages, all
English), this score separates the two populations cleanly:

    prose notices           0.92 - 1.00
    exam-routine tables     0.53 - 0.82

and the tables are exactly where the damage matters: "07 SIiPTENIBER 2026"
for a printed exam date, "16-Au8-2025" for a 2026 exam, "M(T 601" for a course
code. A wrong exam date answered confidently is the worst failure this product
has, so a table page below the floor escalates to a vision read of the rendered
page -- which is correct, because the page *renders* correctly. Only the text
layer is broken.

Three signals, no dictionary and no model:

  * **plausible words** -- a token is plausible if it is mostly letters and,
    at three letters or more, contains a vowel. "Departrnent" passes (it is
    only misspelled); "ffi" and "t!.irr4" do not.
  * **mid-word capitals** -- "SnP',rf tltBtiR" and "MgA521". Real English text
    has very few; OCR on a table has many.
  * **structural junk** -- backslashes, carets, braces, pipes. Ink smudges and
    table rules read as punctuation.

Limitation, stated rather than hidden: every signal is Latin-script. A Bangla
page returns a neutral score, and its quality is judged by the Bijoy path
instead (bangla/bijoy.py). Bangla OCR quality scoring is Phase 1+ work and is
listed in TASKS.md, not silently assumed to work here.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from app.bangla.normalize import bangla_ratio

logger = logging.getLogger(__name__)

_VOWELS = frozenset("aeiouyAEIOUY")
_JUNK_CHARS = frozenset("\\^~|{}<>")
_STRIP = ".,;:!?()[]'\"“”‘’"

# Below this many words there is not enough evidence to judge. A three-line
# cover page is not garbage just because it is short -- and a page with almost
# no text layer was already routed to `scanned` by classify.py.
MIN_WORDS = 15

# A page more than half Bangla is judged by the Bijoy path, not by this one.
BANGLA_PAGE_RATIO = 0.5

# Weights. Deliberately blunt: the two populations are ~0.15 apart, so a
# fitted model would be false precision on 34 pages.
_CAPS_WEIGHT = 0.5
_JUNK_WEIGHT = 5.0


@dataclass(frozen=True)
class QualityReport:
    """A page's text-layer quality, with the components that produced it."""

    score: float
    plausible_words: float
    midword_caps: float
    junk_chars: float
    words: int
    reason: str

    def below(self, floor: float) -> bool:
        return self.score < floor


def _is_plausible(word: str) -> bool:
    core = word.strip("-—–")
    if not core:
        return False
    letters = [c for c in core if c.isalpha()]
    if not letters:
        return False
    # Mostly letters: "CSE-4101" and "12:30pm" are fine, "ffi\"t',1" is not.
    if len(letters) < len(core) * 0.7:
        return False
    # A run of three or more letters with no vowel is not an English word.
    return not (len(letters) >= 3 and not (set(letters) & _VOWELS))


def _has_midword_caps(word: str) -> bool:
    """Capitals inside a word that also has lowercase -- "SnP" but not "GUB"."""
    tail = word[1:]
    return any(c.isupper() for c in tail) and any(c.islower() for c in tail)


def text_quality(text: str) -> QualityReport:
    """Score a page's text layer between 0 (garbage) and 1 (clean)."""
    text = text or ""
    words = [w for w in (t.strip(_STRIP) for t in text.split()) if any(c.isalpha() for c in w)]

    if bangla_ratio(text) > BANGLA_PAGE_RATIO:
        return QualityReport(
            score=1.0,
            plausible_words=1.0,
            midword_caps=0.0,
            junk_chars=0.0,
            words=len(words),
            reason="Bangla page; Latin-script heuristics do not apply",
        )

    if len(words) < MIN_WORDS:
        return QualityReport(
            score=1.0,
            plausible_words=1.0,
            midword_caps=0.0,
            junk_chars=0.0,
            words=len(words),
            reason=f"only {len(words)} words; too little evidence to judge",
        )

    plausible = sum(_is_plausible(w) for w in words) / len(words)
    caps = sum(_has_midword_caps(w) for w in words if len(w) > 3) / len(words)
    junk = sum(1 for c in text if c in _JUNK_CHARS) / max(len(text), 1)

    score = plausible - _CAPS_WEIGHT * caps - _JUNK_WEIGHT * junk
    score = max(0.0, min(1.0, score))

    return QualityReport(
        score=round(score, 3),
        plausible_words=round(plausible, 3),
        midword_caps=round(caps, 3),
        junk_chars=round(junk, 4),
        words=len(words),
        reason=(
            f"{plausible:.0%} plausible words, {caps:.0%} mid-word capitals, "
            f"{junk:.2%} junk characters"
        ),
    )


# ── course codes in document text ───────────────────────────────────────────
#
# The same OCR substitutions attachments/schemas.normalize_course_code repairs
# on the query side occur on the INDEX side, in the published routines: the
# corpus contains "CS€ 211" and "ENG'207". Repairing one side only is the
# asymmetry CLAUDE.md #6 warns about for Bangla, with the same result -- the
# lexical arm never matches, and the routine join silently returns nothing.
#
# Applied to a code-shaped token ONLY. A bare euro sign in a fee schedule is a
# legitimate character and is left alone.

_CODE_TOKEN = re.compile(r"\b([A-Za-z][A-Za-z€£]{1,4})\s*(['`‘’])?\s*(\d{3,5})\b")
_LETTER_FIX = str.maketrans({"€": "E", "£": "E"})
_MANGLED = frozenset("€£'`‘’")


def repair_course_codes(text: str) -> tuple[str, int]:
    """Repair OCR-mangled course codes in document text. Returns (text, repairs).

    "CS€ 211" -> "CSE 211", "ENG'207" -> "ENG 207".

    Only a code-shaped token that actually carries one of the measured OCR
    substitutions is rewritten. A clean token is returned byte for byte --
    "Room 401" and "Section 2A" must not be touched, and a bare euro sign in a
    fee schedule is a legitimate character. This is a repair for one known
    scanner, not a spell-corrector.
    """
    repairs = 0

    def _fix(match: re.Match[str]) -> str:
        nonlocal repairs
        whole = match.group(0)
        if not (_MANGLED & set(whole)):
            return whole
        letters = match.group(1).translate(_LETTER_FIX)
        repairs += 1
        return f"{letters} {match.group(3)}"

    return _CODE_TOKEN.sub(_fix, text or ""), repairs
