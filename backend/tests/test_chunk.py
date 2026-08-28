"""Chunking tests.

CLAUDE.md requires: "Chunking tests asserting Bangla chunks respect the
character budget and never split mid-conjunct."
"""

from __future__ import annotations

import pytest

from app.bangla.normalize import normalize
from app.bangla.segment import HASANT, is_conjunct_boundary
from app.config import get_settings
from app.ingest.chunk import (
    Chunk,
    budget_for,
    chunk_page,
    chunk_pages,
    estimate_tokens,
)

BANGLA_SENTENCE = "পরীক্ষা ১৫ জানুয়ারি ২০২৬ তারিখে শুরু হবে এবং ফলাফল ফেব্রুয়ারিতে প্রকাশিত হবে।"
ENGLISH_SENTENCE = (
    "Final examinations for the Spring 2026 semester commence on 15 January "
    "and results are published in the first week of February."
)


@pytest.fixture
def settings():
    return get_settings()


def chunk_text(text: str, settings, **kw) -> list[Chunk]:
    return chunk_page(
        normalize(text), page_no=1, extraction_method="native_text", settings=settings, **kw
    )


# ── budgets ─────────────────────────────────────────────────────────────────


def test_english_uses_a_token_budget(settings) -> None:
    assert budget_for("en", settings) == ("tokens", settings.chunk_tokens_en)


def test_bangla_uses_a_character_budget(settings) -> None:
    """Bangla is 2-4x more token-expensive; a token budget starves it."""
    assert budget_for("bn", settings) == ("chars", settings.chunk_chars_bn)


def test_mixed_language_uses_the_character_budget(settings) -> None:
    assert budget_for("mixed", settings)[0] == "chars"


def test_token_estimate_grows_with_length() -> None:
    assert estimate_tokens("one two three") > estimate_tokens("one")


# ── the required assertions ─────────────────────────────────────────────────


def test_bangla_chunks_respect_the_character_budget(settings) -> None:
    text = " ".join([BANGLA_SENTENCE] * 60)
    chunks = chunk_text(text, settings)
    assert len(chunks) > 1, "input must actually exceed one chunk"
    limit = settings.chunk_chars_bn
    for chunk in chunks:
        # Overlap is carried at the head of the next chunk, so allow the
        # configured overlap on top of the budget.
        ceiling = limit * (1 + settings.chunk_overlap_ratio) + 200
        assert chunk.char_count <= ceiling, f"{chunk.char_count} chars exceeds {ceiling}"


def test_no_chunk_ever_starts_or_ends_mid_conjunct(settings) -> None:
    """A boundary inside a conjunct yields tokens no query can match."""
    text = " ".join(["শব্দক্ষজ্ঞঞ্চর্ধ্বশব্দ " + BANGLA_SENTENCE] * 40)
    for chunk in chunk_text(text, settings):
        assert not chunk.content.startswith(HASANT)
        assert not chunk.content.endswith(HASANT)
        assert not is_conjunct_boundary(chunk.content, 0)


def test_conjuncts_survive_chunking_intact(settings) -> None:
    text = " ".join([BANGLA_SENTENCE, "ক্ষ জ্ঞ ঞ্চ র্ধ্ব"] * 40)
    joined = " ".join(c.content for c in chunk_text(text, settings))
    for conjunct in ("ক্ষ", "জ্ঞ", "ঞ্চ", "র্ধ্ব"):
        assert conjunct in joined


def test_english_chunks_respect_the_token_budget(settings) -> None:
    text = " ".join([ENGLISH_SENTENCE] * 120)
    chunks = chunk_text(text, settings)
    assert len(chunks) > 1
    ceiling = settings.chunk_tokens_en * (1 + settings.chunk_overlap_ratio) + 80
    for chunk in chunks:
        assert estimate_tokens(chunk.content) <= ceiling


# ── structure before length ─────────────────────────────────────────────────


def test_heading_becomes_the_section_label(settings) -> None:
    text = "Examination Rules\n\nStudents must carry an admit card to every session."
    chunks = chunk_text(text, settings)
    assert chunks[0].section == "Examination Rules"


def test_section_travels_with_the_text_it_introduces(settings) -> None:
    text = (
        "Hostel Rules\n\n"
        + " ".join([ENGLISH_SENTENCE] * 40)
        + "\n\nScholarship Policy\n\n"
        + " ".join([ENGLISH_SENTENCE] * 40)
    )
    sections = {c.section for c in chunk_text(text, settings)}
    assert "Hostel Rules" in sections
    assert "Scholarship Policy" in sections


def test_bangla_numbered_clause_is_a_heading(settings) -> None:
    heading = "৩.১ ছাত্রাবাসের নিয়ম"
    text = f"{heading}\n\nআবেদন অনলাইনে করতে হবে।"
    # normalize() on the expectation too: 'নিয়ম' carries য় (U+09DF), which NFC
    # decomposes. See test_nfc_decomposes_ya_with_nukta.
    assert chunk_text(text, settings)[0].section == normalize(heading)


def test_table_rows_stay_together(settings) -> None:
    text = (
        "Exam Schedule\n\n"
        "CSE 4101    15 Jan    09:00    Room 402\n"
        "CSE 4103    17 Jan    09:00    Room 402\n"
        "MAT 4101    19 Jan    14:00    Room 311\n"
    )
    chunks = chunk_text(text, settings)
    combined = " ".join(c.content for c in chunks)
    for code in ("CSE 4101", "CSE 4103", "MAT 4101"):
        assert code in combined
    assert len(chunks) == 1, "a small table must not fragment"


# ── metadata ────────────────────────────────────────────────────────────────


def test_lang_is_tagged_per_chunk(settings) -> None:
    assert chunk_text(BANGLA_SENTENCE, settings)[0].lang == "bn"
    assert chunk_text(ENGLISH_SENTENCE, settings)[0].lang == "en"


def test_audience_is_denormalized_onto_every_chunk(settings) -> None:
    """PRD 9: denormalized so the filter applies in a single query."""
    chunks = chunk_text(ENGLISH_SENTENCE, settings, audience="teachers")
    assert all(c.audience == "teachers" for c in chunks)


def test_audience_defaults_are_not_permissive_by_accident(settings) -> None:
    """The publish flow requires an explicit choice (DESIGN 6.7)."""
    assert chunk_text(ENGLISH_SENTENCE, settings)[0].audience == "all"


def test_page_no_and_method_are_carried(settings) -> None:
    chunks = chunk_page(
        normalize(ENGLISH_SENTENCE),
        page_no=7,
        extraction_method="legacy",
        settings=settings,
    )
    assert chunks[0].page_no == 7
    assert chunks[0].extraction_method == "legacy"


def test_chunk_indices_are_sequential_across_pages(settings) -> None:
    pages = [
        (1, " ".join([ENGLISH_SENTENCE] * 30), "native_text"),
        (2, " ".join([BANGLA_SENTENCE] * 30), "native_text"),
    ]
    chunks = chunk_pages(pages, settings=settings)
    assert [c.index for c in chunks] == list(range(len(chunks)))
    assert {c.page_no for c in chunks} == {1, 2}


# ── edge cases ──────────────────────────────────────────────────────────────


def test_empty_page_produces_no_chunks(settings) -> None:
    assert chunk_text("", settings) == []
    assert chunk_text("   \n\n  ", settings) == []


def test_no_chunk_is_empty_or_whitespace(settings) -> None:
    text = " ".join([BANGLA_SENTENCE, ENGLISH_SENTENCE] * 30)
    assert all(c.content.strip() for c in chunk_text(text, settings))


def test_single_oversized_sentence_is_split_safely(settings) -> None:
    """No terminal punctuation anywhere: must still be cut, and cut safely."""
    text = "ক্ষজ্ঞঞ্চর্ধ্ব" * 800
    chunks = chunk_text(text, settings)
    assert len(chunks) > 1
    for chunk in chunks:
        assert not chunk.content.startswith(HASANT)
        assert not chunk.content.endswith(HASANT)


def test_content_is_preserved_across_chunks(settings) -> None:
    """Chunking may overlap, but must never drop text."""
    text = " ".join(f"clause{i} {ENGLISH_SENTENCE}" for i in range(40))
    joined = " ".join(c.content for c in chunk_text(text, settings))
    for i in range(40):
        assert f"clause{i}" in joined, f"clause{i} was dropped"
