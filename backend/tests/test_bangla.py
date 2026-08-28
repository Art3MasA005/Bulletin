"""Bangla unit tests with real strings, including the four conjuncts named in
CLAUDE.md: ক্ষ, জ্ঞ, ঞ্চ, র্ধ্ব."""

from __future__ import annotations

import pytest

from app.bangla import bijoy, segment
from app.bangla.normalize import (
    bangla_ratio,
    detect_lang,
    has_bangla,
    normalize,
    normalize_for_match,
)

CONJUNCTS = ["ক্ষ", "জ্ঞ", "ঞ্চ", "র্ধ্ব"]


# ── normalize ───────────────────────────────────────────────────────────────


@pytest.mark.parametrize("conjunct", CONJUNCTS)
def test_conjuncts_survive_normalization(conjunct: str) -> None:
    """Normalization must not decompose or mangle a conjunct cluster."""
    assert normalize(conjunct) == conjunct


def test_normalization_is_idempotent() -> None:
    """Ingestion normalizes once, query normalizes once -- they must converge."""
    text = "পরীক্ষা ১৫ জানুয়ারি ২০২৬ তারিখে শুরু হবে।"
    once = normalize(text)
    assert normalize(once) == once


def test_zero_width_space_removed_but_conjunct_intact() -> None:
    assert normalize("পরী​ক্ষা") == "পরীক্ষা"


def test_curly_quotes_and_dashes_folded() -> None:
    assert normalize("“Final” – exam") == '"Final" - exam'


def test_double_danda_folds_to_single() -> None:
    assert normalize("শেষ॥") == "শেষ।"


def test_newlines_survive_for_structure_aware_chunking() -> None:
    assert "\n" in normalize("Heading\n\nBody text")


def test_normalize_for_match_folds_bangla_digits() -> None:
    """A query typed in Bangla numerals must match a doc printed in Latin ones."""
    assert normalize_for_match("২০২৬") == normalize_for_match("2026")


def test_normalize_for_match_preserves_course_codes() -> None:
    assert "cse 4101" in normalize_for_match("Course: CSE 4101 (Section A)")


def test_bangla_ratio_and_lang_detection() -> None:
    assert detect_lang("পরীক্ষা কবে শুরু হবে") == "bn"
    assert detect_lang("When do the final exams start") == "en"
    assert bangla_ratio("abc") == 0.0
    assert has_bangla("CSE 4101 পরীক্ষা")


def test_empty_input_is_safe() -> None:
    assert normalize("") == ""
    assert normalize_for_match("") == ""


# ── bijoy ───────────────────────────────────────────────────────────────────

# Real Bijoy/SutonnyMJ byte sequences and their correct Unicode readings.
LEGACY_SAMPLES = [
    ("Avwg evsjvq Mvb MvB", "আমি বাংলায় গান গাই"),
    ("wek¦we`¨vjq", "বিশ্ববিদ্যালয়"),
    ("cix¶v", "পরীক্ষা"),
    ("ZvwiL", "তারিখ"),
]


@pytest.mark.parametrize(("legacy", "expected"), LEGACY_SAMPLES)
def test_bijoy_conversion_correctness(legacy: str, expected: str) -> None:
    result = bijoy.convert(legacy)
    # Compared against the NORMALIZED expectation, not the raw literal: convert()
    # ends in normalize(), so its output is in canonical form. See
    # test_nfc_decomposes_ya_with_nukta for why the two differ.
    assert result.text == normalize(expected), result.reason
    assert result.confidence >= 0.75, f"would escalate unnecessarily: {result.reason}"


def test_nfc_decomposes_ya_with_nukta() -> None:
    """U+09DF is a Unicode composition exclusion, so NFC splits it.

    'য়' typed as one codepoint (U+09DF) normalizes to two (U+09AF U+09BC).
    Both forms occur in real PDFs and on real keyboards. This is precisely why
    CLAUDE.md #6 demands symmetry: index one form, query the other, and every
    lookup silently misses. Because both sides call normalize(), they converge.
    """
    precomposed = "য়"
    decomposed = "য়"
    assert precomposed != decomposed
    assert normalize(precomposed) == normalize(decomposed)


def test_legacy_text_is_detected() -> None:
    assert bijoy.looks_legacy("Avwg evsjvq Mvb MvB")


def test_english_is_not_mistaken_for_legacy() -> None:
    english = (
        "Final examinations for the Spring 2026 semester commence on 15 January. "
        "Students must carry their admit card to every session."
    )
    assert not bijoy.looks_legacy(english)
    assert bijoy.legacy_signal(english) < 0.2


def test_unicode_bangla_is_not_mistaken_for_legacy() -> None:
    assert not bijoy.looks_legacy("পরীক্ষা ১৫ জানুয়ারি তারিখে শুরু হবে।")


def test_already_unicode_passes_through_at_full_confidence() -> None:
    result = bijoy.convert("পরীক্ষার সময়সূচি")
    assert result.confidence == 1.0
    assert result.reason == "already unicode bangla"


def test_garbage_scores_low_enough_to_escalate() -> None:
    """The whole point of the score: bad conversion must trigger vision."""
    result = bijoy.convert("%%%% ^^^^ @@@@ 1234 zzzz")
    assert result.confidence < 0.75, result.reason


def test_font_marker_detection() -> None:
    assert bijoy.font_is_legacy("ABCDEE+SutonnyMJ")
    assert bijoy.font_is_legacy("BijoyEkushey-Normal")
    assert not bijoy.font_is_legacy("NotoSansBengali-Regular")


def test_conversion_never_raises() -> None:
    for bad in ["", "   ", "\x00\x01", "😀😀"]:
        bijoy.convert(bad)  # must not raise


# ── segment ─────────────────────────────────────────────────────────────────


def test_danda_splits_bangla_sentences() -> None:
    text = (
        "পরীক্ষা শুরু হবে ১৫ জানুয়ারি। ফলাফল প্রকাশিত হবে ফেব্রুয়ারিতে। আবেদন করতে হবে অনলাইনে।"
    )
    assert len(segment.split_sentences(text)) == 3


def test_period_splits_english_sentences() -> None:
    text = "Finals begin on 15 January. Results follow in February."
    assert len(segment.split_sentences(text)) == 2


def test_abbreviation_does_not_split() -> None:
    assert len(segment.split_sentences("Contact Dr. Rahman for details.")) == 1


def test_mixed_language_paragraph_splits_on_both_marks() -> None:
    text = "The exam starts at 9 AM. পরীক্ষা সকাল ৯টায় শুরু হবে। Bring your ID."
    assert len(segment.split_sentences(text)) == 3


@pytest.mark.parametrize("conjunct", CONJUNCTS)
def test_split_point_never_breaks_a_conjunct(conjunct: str) -> None:
    text = f"শব্দ{conjunct}শব্দ"
    for i in range(1, len(text)):
        safe = segment.safe_split_point(text, i)
        assert not segment.is_conjunct_boundary(
            text, safe
        ), f"index {i} -> {safe} splits {conjunct!r}"


def test_hasant_boundary_is_flagged_unsafe() -> None:
    text = "ক্ষ"
    assert segment.is_conjunct_boundary(text, 2)  # right after the hasant


def test_paragraph_split() -> None:
    assert len(segment.split_paragraphs("Head\n\nBody\n\nTail")) == 3


def test_confidence_score_cannot_detect_semantic_errors() -> None:
    """Pins the documented blind spot in _score_conversion.

    Structurally perfect Bangla that says the wrong thing scores high. This
    test exists so the limitation is visible in the suite rather than
    discovered in production, and so it fails loudly if someone later claims
    the score validates correctness.
    """
    wrong_but_well_formed = "কতর্পভ্র"  # কতর্পভ্র
    score, reason = bijoy._score_conversion("KZ©c£", wrong_but_well_formed)
    assert score >= 0.9, "shape-based scoring accepts it"
    assert "bengali=100%" in reason
    # The guard that actually catches this is a human reading the extraction
    # report against the rendered page (CLAUDE.md #8).
