"""Legacy ASCII-mapped Bangla (Bijoy / SutonnyMJ family) -> Unicode.

PRD 7.1, secondary claim: many Bangla PDFs encode text with an ASCII-mapped
legacy font. PyMuPDF extracts the raw bytes, so the text layer reads as Latin
gibberish ("Avwg evsjvq Mvb MvB") while the rendered page looks perfectly
normal to a human.

This module does two jobs:

    looks_legacy(text)   detect the encoding without needing the font table,
                         so a caller with only text can still route correctly.

    convert(text)        convert and return a CONFIDENCE score. Below
                         settings.bijoy_confidence_floor the pipeline
                         escalates the page to a vision read instead
                         (see ingest/pipeline.py).

The confidence score is the point of this module. Conversion never raises on
bad input -- it produces plausible-looking garbage. Only the score separates a
good conversion from a bad one, and only the score can trigger escalation.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from functools import lru_cache

from app.bangla.normalize import bangla_ratio, has_bangla, normalize

# Font names that identify an ASCII-mapped legacy encoding. Matched
# case-insensitively as a substring of the PDF font-table entry.
LEGACY_FONT_MARKERS = (
    "sutonnymj",
    "sutonny",
    "boishakhi",
    "bijoy",
    "bornomala",
    "amarbangla",
    "aabc",
    "chandrabati",
    "modhumati",
    "prionty",
    "rinkiy",
    "shreelipi",
    # Foundries ship an ASCII-mapped build of an otherwise Unicode face and
    # name it "<face> ANSI" / "<face> ASCII". Real example seen in the wild:
    # "Kalpurush ANSI Regular". The suffix is the whole signal.
    "ansi",
    "ascii",
)

# The dominant detection signal. In Bijoy encoding these Latin letters carry
# the most common Bangla vowel signs and consonants, so their density runs
# 0.35-0.50 of all letters. In ordinary English prose the same set runs ~0.02.
# Measured on real samples; the adversarial case (a deliberately v/q/x-heavy
# English sentence) still only reaches 0.15 -- see the tests.
_LEGACY_LETTER_PROFILE = set("vwqxzVWQXZ")
_PROFILE_PIVOT = 0.35

# Latin-1 / Windows-1252 punctuation and accented letters, which Bijoy uses for
# conjuncts and matras. Absent from English, but also absent from short Bijoy
# fragments -- corroborating evidence, not a primary signal. Defined by
# codepoint range rather than a literal blob so the source stays legible.
_LEGACY_SIGNAL_CHARS = frozenset(
    [chr(c) for c in range(0x00A1, 0x0100) if chr(c) not in "­"]
    + [
        chr(c)
        for c in (
            0x2020,
            0x2021,
            0x2030,
            0x2039,
            0x203A,
            0x0152,
            0x0153,
            0x201E,
            0x2026,
            0x0192,
            0x02C6,
            0x2122,
        )
    ]
)
_SIGNAL_PIVOT = 0.05

# Mid-word capitals are common in Bijoy and rare in prose -- but numeric tables
# ("Room 402 CSE 4101") trip it constantly, so it carries the least weight.
_MIDWORD_PIVOT = 0.20

# Below this many Latin letters the densities are too noisy to trust; a short
# numeric table would otherwise score as legacy.
_MIN_LETTERS = 12

_LATIN_LETTERS = re.compile(r"[A-Za-z]")
_WORDLIKE = re.compile(r"\S+")
_TOKENS = re.compile(r"[A-Za-zÀ-ɏ]{2,}")


@dataclass(frozen=True)
class ConversionResult:
    """Outcome of one Bijoy -> Unicode conversion attempt."""

    text: str
    confidence: float
    reason: str

    @property
    def ok(self) -> bool:
        return self.confidence > 0.0


@lru_cache(maxsize=1)
def _converter():
    """bijoy2unicode handles i-kar reordering, reph, and split vowels."""
    from bijoy2unicode import converter

    return converter.Unicode()


def font_is_legacy(font_name: str) -> bool:
    """True when a PDF font-table entry names a known ASCII-mapped font."""
    lowered = font_name.lower()
    return any(marker in lowered for marker in LEGACY_FONT_MARKERS)


def legacy_signal(text: str) -> float:
    """0..1 estimate that `text` is ASCII-mapped Bangla rather than English.

    Text-only detection, for callers without a font table. classify.py prefers
    the font table and uses this as corroboration.
    """
    if not text.strip():
        return 0.0
    # Real Bangla Unicode present means the text layer is already fine.
    if bangla_ratio(text) > 0.3:
        return 0.0

    sample = text[:4000]
    letters = [ch for ch in sample if ch.isalpha() and ord(ch) < 0x0250]
    if len(letters) < _MIN_LETTERS:
        return 0.0

    profile = sum(1 for ch in letters if ch in _LEGACY_LETTER_PROFILE) / len(letters)
    signal = sum(1 for ch in sample if ch in _LEGACY_SIGNAL_CHARS) / len(sample)
    tokens = _TOKENS.findall(sample)
    midword_upper = sum(1 for t in tokens if any(c.isupper() for c in t[1:]))
    midword = midword_upper / len(tokens) if tokens else 0.0

    score = (
        0.65 * min(1.0, profile / _PROFILE_PIVOT)
        + 0.25 * min(1.0, signal / _SIGNAL_PIVOT)
        + 0.10 * min(1.0, midword / _MIDWORD_PIVOT)
    )
    return round(min(1.0, score), 3)


def looks_legacy(text: str, threshold: float = 0.35) -> bool:
    return legacy_signal(text) >= threshold


def _score_conversion(source: str, converted: str) -> tuple[float, str]:
    """Score a conversion 0..1 and explain the number.

    A good conversion turns Latin gibberish into text that is overwhelmingly
    Bengali codepoints, with the Latin residue gone. Leftover Latin means the
    mapping table missed glyphs -- exactly the case that must escalate.

    KNOWN BLIND SPOT -- read before trusting this number.

    This score measures whether the output is SHAPED like Bangla, not whether
    it says the right thing. A conversion that renders কর্তৃপক্ষ as কতর্পভ্র
    scores 1.00: every codepoint is Bengali, no Latin residue, no orphan
    matras, no doubled hasant. Observed on a synthetic fixture; a real
    mis-mapped glyph table would do the same.

    So a high score means "escalation is not obviously required", NOT "this
    text is correct". The only real check is a human reading
    eval/reports/extraction_samples.html against the rendered page, which is
    why CLAUDE.md #8 makes that a gate rather than a suggestion. If the report
    shows wrong text at high confidence on the real corpus, lower
    BULLETIN_BIJOY_CONFIDENCE_FLOOR toward 1.0 so those pages escalate to
    vision, and record the finding in the Ablation B table (PRD 12).
    """
    if not converted.strip():
        return 0.0, "conversion produced no text"

    bn = bangla_ratio(converted)
    if bn < 0.5:
        return round(bn, 3), f"only {bn:.0%} of letters are Bengali after conversion"

    # Residual Latin letters relative to the input's Latin volume.
    src_latin = len(_LATIN_LETTERS.findall(source)) or 1
    residue = len(_LATIN_LETTERS.findall(converted)) / src_latin
    # Orphaned combining marks at word start signal a reordering failure.
    orphan_matra = sum(
        1 for w in _WORDLIKE.findall(converted) if w and 0x09BE <= ord(w[0]) <= 0x09CD
    )
    orphan_ratio = orphan_matra / max(len(_WORDLIKE.findall(converted)), 1)
    # Doubled hasant is never valid and indicates a broken conjunct.
    double_hasant = converted.count("্্")

    score = bn
    score -= min(0.4, residue * 0.8)
    score -= min(0.3, orphan_ratio * 3.0)
    score -= min(0.2, double_hasant * 0.05)
    score = max(0.0, min(1.0, score))

    reasons = [f"bengali={bn:.0%}"]
    if residue > 0.05:
        reasons.append(f"latin residue={residue:.0%}")
    if orphan_ratio > 0.02:
        reasons.append(f"orphan matras={orphan_ratio:.0%}")
    if double_hasant:
        reasons.append(f"double hasant x{double_hasant}")
    return round(score, 3), ", ".join(reasons)


def convert(text: str, *, normalize_output: bool = True) -> ConversionResult:
    """Convert legacy-encoded text to Unicode Bangla with a confidence score.

    Never raises. A failed conversion returns confidence 0.0 and the original
    text, so the caller can escalate to vision without special-casing errors.
    """
    if not text.strip():
        return ConversionResult(text="", confidence=0.0, reason="empty input")

    if has_bangla(text) and bangla_ratio(text) > 0.5:
        out = normalize(text) if normalize_output else text
        return ConversionResult(text=out, confidence=1.0, reason="already unicode bangla")

    try:
        converted = _converter().convertBijoyToUnicode(text)
    except Exception as exc:  # noqa: BLE001 -- a bad page must not kill an ingest
        return ConversionResult(text=text, confidence=0.0, reason=f"converter error: {exc}")

    if not converted:
        return ConversionResult(text=text, confidence=0.0, reason="converter returned empty")

    confidence, reason = _score_conversion(text, converted)
    # Normalization is applied AFTER conversion so the output enters the index
    # through the same path as native Unicode text (CLAUDE.md #6).
    out = normalize(converted) if normalize_output else converted
    return ConversionResult(text=out, confidence=confidence, reason=reason)
