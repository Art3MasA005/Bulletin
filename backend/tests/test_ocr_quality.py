"""The OCR-quality gate: the fourth routing state, and the code repair.

Every string in the "real corpus" tests is copied verbatim out of the Green
University PDFs in `corpus/inbox/`. They are the evidence that this gate is
needed: each one classifies as `native_text` with high confidence and is
wrong.
"""

from __future__ import annotations

import pytest

from app.config import get_settings
from app.ingest.ocr_quality import (
    MIN_WORDS,
    QualityReport,
    repair_course_codes,
    text_quality,
)

FLOOR = get_settings().ocr_quality_floor

# Real page text. The routine is a scan whose OCR layer mangles exam dates.
GARBAGE_ROUTINE = (
    "CSE (Regular)-FINAL Exa#ihation Routine, Summer 2026 Final Summer 26 DAY -\\ "
    "Departrnent ofComptrter Science & Eogineering FINAL Exsmlnotlon Routln€ "
    "CSE (Regular), Summcr 2026 Stt*,,,,' !60 26t t5l 250 251 2.t! 2!t 212 ] 2lt "
    "1t:r \\ ^K\"*'* ffi\"t',1 t!.irr4 & lC D.,rni..i or Co.lrbr S.l..e & t !l.c.l.r"
)

CLEAN_NOTICE = (
    "This is to notify all students, faculty members and related administrative "
    "officers that the Final Examinations of Summer 2026 for all the academic "
    "programs of Green University of Bangladesh will be held from 05th September "
    "2026 to 13th September 2026. Students are advised to download their admit "
    "cards from the student portal after clearing all dues."
)


def test_a_garbage_ocr_layer_scores_below_the_floor() -> None:
    """The state PRD 7.1 does not model: present, Unicode, not Bijoy, and wrong."""
    report = text_quality(GARBAGE_ROUTINE)
    assert report.below(FLOOR), report
    assert report.score < 0.7


def test_clean_prose_scores_above_the_floor() -> None:
    report = text_quality(CLEAN_NOTICE)
    assert not report.below(FLOOR), report


def test_the_two_populations_are_separated() -> None:
    """A gate that cannot tell them apart escalates everything and costs money."""
    assert text_quality(CLEAN_NOTICE).score - text_quality(GARBAGE_ROUTINE).score > 0.2


@pytest.mark.parametrize(
    "line",
    [
        "07 SIiPTENIBER 2026 I I SnP',rf tltBtiR 2026 06:00 Pll - 08:00 PNI csE 453",
        "icut( t Bryamcoattd (04 0opanment d CSE teen Urwers{Y d BdCdest' r* u'qflfi$i#ii#dhm",
        "15'Au8-2026 M(T 601: Consumer Behavior MgA521: Productlon and Operations",
    ],
)
def test_real_corpus_damage_is_caught(line: str) -> None:
    """Mangled dates on an exam routine: the wrong-answer failure mode."""
    padded = (line + " ") * 3  # past MIN_WORDS, as a real page would be
    assert text_quality(padded).below(FLOOR)


def test_a_short_page_is_not_judged() -> None:
    """A three-line cover page is not garbage just because it is short."""
    report = text_quality("Green University of Bangladesh")
    assert report.score == 1.0
    assert "too little evidence" in report.reason
    assert report.words < MIN_WORDS


def test_a_bangla_page_is_left_to_the_bijoy_path() -> None:
    """Every signal here is Latin-script; saying so beats scoring nonsense."""
    bangla = "চূড়ান্ত পরীক্ষা আগামী ১২ ডিসেম্বর তারিখে শুরু হবে এবং ২০ ডিসেম্বর শেষ হবে। " * 3
    report = text_quality(bangla)
    assert report.score == 1.0
    assert "Latin-script heuristics do not apply" in report.reason


def test_empty_text_is_not_a_crash() -> None:
    assert isinstance(text_quality(""), QualityReport)
    assert text_quality("").score == 1.0


def test_score_stays_in_range() -> None:
    assert 0.0 <= text_quality("\\^~|{} " * 40).score <= 1.0


# ── course-code repair, symmetric with the query side ───────────────────────


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("CS€ 211: Computer Architecture", "CSE 211: Computer Architecture"),
        ("ENG'207 Business English", "ENG 207 Business English"),
        ("EE€ 201 and T€X 311", "EEE 201 and TEX 311"),
        ("CSE 201'CSE(181): Object Oriented", "CSE 201'CSE(181): Object Oriented"),
    ],
)
def test_repairs_the_measured_substitutions(raw: str, expected: str) -> None:
    """The same OCR damage normalize_course_code repairs on the query side.

    Repairing one side only is the CLAUDE.md #6 asymmetry with a different
    alphabet: the lexical arm silently never matches.
    """
    assert repair_course_codes(raw)[0] == expected


@pytest.mark.parametrize(
    "text",
    [
        "Room 401 is closed",
        "SEPTEMBER 2026 examinations",
        "The fee is €500 per credit",
        "Section 2A 2026",
        "Building 12 Level 3",
    ],
)
def test_ordinary_text_is_untouched(text: str) -> None:
    """A euro sign in a fee schedule is a legitimate character."""
    repaired, repairs = repair_course_codes(text)
    assert repaired == text
    assert repairs == 0


def test_repair_count_is_reported_for_logging() -> None:
    _, repairs = repair_course_codes("CS€ 211 CS€ 213 clean CSE 215")
    assert repairs == 2
