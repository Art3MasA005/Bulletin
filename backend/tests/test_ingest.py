"""Extraction, classification, and escalation against real fixture PDFs.

CLAUDE.md: "classify.py fixture PDFs: Unicode, legacy-font, scanned." and
"Retrieval tests against a seeded fixture corpus, not mocks."
"""

from __future__ import annotations

from pathlib import Path

import pytest

from app.bangla.normalize import bangla_ratio, normalize
from app.config import get_settings
from app.ingest.classify import ExtractionMethod, classify_document
from app.ingest.extract import DocumentRejected, extract_document, render_page_png
from app.ingest.pipeline import ingest_document
from app.providers.base import Provider, ProviderError
from tests import fixtures


@pytest.fixture
def settings(tmp_path: Path):
    """Real settings, with reports (and therefore checkpoints) redirected."""
    return get_settings().model_copy(update={"reports_dir": tmp_path / "reports"})


# ── extraction ──────────────────────────────────────────────────────────────


def test_english_pdf_extracts_native_text(tmp_path: Path, settings) -> None:
    pdf = fixtures.english_pdf(tmp_path / "en.pdf")
    result = extract_document(pdf, settings)
    assert result.page_count == 1
    assert "Final examinations" in result.pages[0].text
    assert result.pages[0].char_count > 100


def test_page_numbers_are_one_based(tmp_path: Path, settings) -> None:
    """Citations show these numbers to users; off-by-one opens the wrong page."""
    pdf = fixtures.english_pdf(tmp_path / "en.pdf")
    assert extract_document(pdf, settings).pages[0].page_no == 1


def test_font_table_is_read(tmp_path: Path, settings) -> None:
    pdf = fixtures.bangla_legacy_pdf(tmp_path / "legacy.pdf")
    if pdf is None:
        pytest.skip("no legacy Bangla font installed")
    result = extract_document(pdf, settings)
    assert any("ansi" in f.lower() for f in result.fonts)


def test_render_page_png_produces_an_image(tmp_path: Path, settings) -> None:
    pdf = fixtures.english_pdf(tmp_path / "en.pdf")
    png = render_page_png(pdf, 1, settings)
    assert png.startswith(b"\x89PNG")


# ── rejection (PRD 7.1) ─────────────────────────────────────────────────────


def test_encrypted_pdf_is_rejected_with_readable_reason(tmp_path: Path, settings) -> None:
    pdf = fixtures.encrypted_pdf(tmp_path / "locked.pdf")
    with pytest.raises(DocumentRejected) as exc:
        extract_document(pdf, settings)
    assert exc.value.code == "encrypted"
    assert "password" in exc.value.reason.lower()


def test_missing_file_is_rejected(tmp_path: Path, settings) -> None:
    with pytest.raises(DocumentRejected):
        extract_document(tmp_path / "nope.pdf", settings)


def test_page_limit_is_enforced(tmp_path: Path, settings) -> None:
    pdf = fixtures.english_pdf(tmp_path / "en.pdf")
    tight = settings.model_copy(update={"max_pages": 0})
    with pytest.raises(DocumentRejected) as exc:
        extract_document(pdf, tight)
    assert exc.value.code == "too_many_pages"


def test_empty_document_is_rejected_not_silently_indexed(tmp_path: Path, settings) -> None:
    """PRD 7.1: silently indexing an empty document is the worst failure here."""
    pdf = fixtures.empty_pdf(tmp_path / "blank.pdf")
    result = ingest_document(pdf, provider=None, settings=settings)
    assert result.rejected is not None
    assert result.reject_code == "empty_extraction"


# ── classification ──────────────────────────────────────────────────────────


def test_english_classifies_as_native_text(tmp_path: Path, settings) -> None:
    pdf = fixtures.english_pdf(tmp_path / "en.pdf")
    doc = classify_document(extract_document(pdf, settings), settings)
    assert doc.method is ExtractionMethod.NATIVE_TEXT
    assert doc.lang == "en"


def test_unicode_bangla_classifies_as_native_text(tmp_path: Path, settings) -> None:
    pdf = fixtures.bangla_unicode_pdf(tmp_path / "bn.pdf")
    if pdf is None:
        pytest.skip("no Unicode Bangla font installed")
    extraction = extract_document(pdf, settings)
    assert bangla_ratio(extraction.pages[0].text) > 0.8
    doc = classify_document(extraction, settings)
    assert doc.method is ExtractionMethod.NATIVE_TEXT
    assert doc.lang == "bn"


def test_legacy_font_classifies_as_legacy(tmp_path: Path, settings) -> None:
    """The headline case: text layer reads as Latin, page renders as Bangla."""
    pdf = fixtures.bangla_legacy_pdf(tmp_path / "legacy.pdf")
    if pdf is None:
        pytest.skip("no legacy Bangla font installed")
    extraction = extract_document(pdf, settings)
    # Precondition: this really is the broken case, not accidentally clean text.
    assert bangla_ratio(extraction.pages[0].text) < 0.1
    doc = classify_document(extraction, settings)
    assert doc.method is ExtractionMethod.LEGACY
    assert doc.pages[0].confidence >= 0.8


def test_scanned_page_classifies_as_scanned(tmp_path: Path, settings) -> None:
    pdf = fixtures.scanned_pdf(tmp_path / "scan.pdf")
    doc = classify_document(extract_document(pdf, settings), settings)
    assert doc.method is ExtractionMethod.SCANNED
    assert doc.vision_pages == [1]


def test_document_method_reports_the_most_severe_page(tmp_path: Path, settings) -> None:
    """A mostly-clean doc with one scanned page is not a native_text doc."""
    import pymupdf

    doc = pymupdf.open()
    page = doc.new_page()
    page.insert_textbox(pymupdf.Rect(40, 60, 550, 700), fixtures.ENGLISH_TEXT, fontsize=13)
    doc.new_page()  # blank -> scanned
    path = tmp_path / "mixed.pdf"
    doc.save(path)
    doc.close()

    classified = classify_document(extract_document(path, settings), settings)
    assert classified.method is ExtractionMethod.SCANNED
    assert classified.counts()["native_text"] == 1
    assert classified.counts()["scanned"] == 1


# ── escalation policy ───────────────────────────────────────────────────────


class RecordingProvider(Provider):
    """Counts vision calls so tests can assert the cheap path ran first."""

    name = "recording"

    def __init__(self, text: str = "পরীক্ষা ১৫ জানুয়ারি ২০২৬ তারিখে শুরু হবে।"):
        self.text = text
        self.page_reads = 0

    def embed(self, texts):
        raise NotImplementedError

    def rerank(self, query, docs):
        raise NotImplementedError

    def generate(self, messages, *, stream=False):
        raise NotImplementedError

    def read_page_image(self, png_bytes: bytes, *, lang_hint: str = "auto") -> str:
        self.page_reads += 1
        return self.text

    def extract_structured(self, png_bytes, schema, *, prompt):
        raise NotImplementedError


class FailingVisionProvider(RecordingProvider):
    name = "failing"

    def read_page_image(self, png_bytes: bytes, *, lang_hint: str = "auto") -> str:
        self.page_reads += 1
        raise ProviderError("vision unavailable", status=503, retryable=True)


def test_native_text_never_calls_vision(tmp_path: Path, settings) -> None:
    """PRD 6: vision on every page exhausts a free tier immediately."""
    pdf = fixtures.english_pdf(tmp_path / "en.pdf")
    provider = RecordingProvider()
    result = ingest_document(pdf, provider, settings=settings)
    assert provider.page_reads == 0
    assert result.pages[0].method == "native_text"
    assert result.escalated_pages == []


def test_good_legacy_conversion_does_not_escalate(tmp_path: Path, settings) -> None:
    pdf = fixtures.bangla_legacy_pdf(tmp_path / "legacy.pdf")
    if pdf is None:
        pytest.skip("no legacy Bangla font installed")
    provider = RecordingProvider()
    result = ingest_document(pdf, provider, settings=settings)
    page = result.pages[0]
    assert page.method == "legacy"
    assert bangla_ratio(page.text) > 0.8, "conversion should yield real Bangla"
    assert provider.page_reads == 0, "confident conversion must not spend vision tokens"


def test_low_confidence_legacy_escalates_to_vision(tmp_path: Path, settings) -> None:
    """The escalation rule: below the floor, read the rendered page instead."""
    pdf = fixtures.bangla_legacy_pdf(tmp_path / "legacy.pdf")
    if pdf is None:
        pytest.skip("no legacy Bangla font installed")
    provider = RecordingProvider()
    # Floor above 1.0 forces every conversion to be judged insufficient.
    strict = settings.model_copy(update={"bijoy_confidence_floor": 1.01})
    result = ingest_document(pdf, provider, settings=strict, resume=False)
    assert provider.page_reads == 1
    assert result.pages[0].escalated
    # Normalized, because vision output enters the index through the same
    # normalization as native text (CLAUDE.md #6 symmetry).
    assert result.pages[0].text == normalize(provider.text)


def test_scanned_page_escalates_to_vision(tmp_path: Path, settings) -> None:
    pdf = fixtures.scanned_pdf(tmp_path / "scan.pdf")
    provider = RecordingProvider()
    result = ingest_document(pdf, provider, settings=settings)
    assert provider.page_reads == 1
    assert result.pages[0].escalated
    assert "পরীক্ষা" in result.pages[0].text


def test_vision_failure_does_not_crash_the_ingest(tmp_path: Path, settings) -> None:
    pdf = fixtures.scanned_pdf(tmp_path / "scan.pdf")
    provider = FailingVisionProvider()
    result = ingest_document(pdf, provider, settings=settings)
    assert result.rejected is not None  # empty after all paths
    assert provider.page_reads == 1


def test_ingest_without_provider_marks_escalation_candidates(tmp_path: Path, settings) -> None:
    """`make extract-report` runs free: it reports what WOULD need vision."""
    pdf = fixtures.scanned_pdf(tmp_path / "scan.pdf")
    result = ingest_document(pdf, provider=None, settings=settings)
    assert result.pages[0].escalated
    assert "no provider configured" in result.pages[0].reason


# ── checkpointing (PRD 11) ──────────────────────────────────────────────────


def test_checkpoint_resume_skips_completed_pages(tmp_path: Path, settings) -> None:
    """Free hosts kill long jobs; a restart must not re-spend vision tokens."""
    pdf = fixtures.scanned_pdf(tmp_path / "scan.pdf")
    first = RecordingProvider()
    ingest_document(pdf, first, settings=settings)
    assert first.page_reads == 1

    second = RecordingProvider()
    result = ingest_document(pdf, second, settings=settings, resume=True)
    assert second.page_reads == 0, "resumed run must not re-read the page"
    assert result.pages[0].text


def test_resume_false_reprocesses(tmp_path: Path, settings) -> None:
    pdf = fixtures.scanned_pdf(tmp_path / "scan.pdf")
    ingest_document(pdf, RecordingProvider(), settings=settings)
    second = RecordingProvider()
    ingest_document(pdf, second, settings=settings, resume=False)
    assert second.page_reads == 1


# ── the fourth routing state: a present but unreadable text layer ───────────


def test_bad_ocr_text_layer_escalates_to_vision(tmp_path: Path, settings) -> None:
    """The gap the real corpus exposed.

    The page has a text layer, it is Unicode, it is not Bijoy, and it is long
    enough -- so every check in the PRD 7.1 routing table calls it native_text.
    It is also garbage. The page renders correctly, so vision is the fix.
    """
    pdf = fixtures.bad_ocr_pdf(tmp_path / "bad_ocr.pdf")
    provider = RecordingProvider()
    result = ingest_document(pdf, provider, settings=settings, resume=False)

    assert provider.page_reads == 1
    assert result.pages[0].escalated
    assert result.pages[0].text == normalize(provider.text)


def test_a_good_text_layer_still_does_not_call_vision(tmp_path: Path, settings) -> None:
    """The gate must not escalate everything -- vision per page is the cost risk."""
    pdf = fixtures.english_pdf(tmp_path / "en.pdf")
    provider = RecordingProvider()
    result = ingest_document(pdf, provider, settings=settings, resume=False)
    assert provider.page_reads == 0
    assert not result.pages[0].escalated


def test_bad_ocr_without_a_provider_keeps_the_text_and_flags_it(tmp_path: Path, settings) -> None:
    """A free extract-report run must still show what the text layer contains.

    Dropping the page would hide the evidence a human needs for the CLAUDE.md
    #8 inspection -- the point is to SEE that the extraction is wrong.
    """
    pdf = fixtures.bad_ocr_pdf(tmp_path / "bad_ocr.pdf")
    result = ingest_document(pdf, provider=None, settings=settings, resume=False)
    page = result.pages[0]

    assert page.text, "the poor text layer must be kept, not dropped"
    assert page.escalated
    assert page.confidence < settings.ocr_quality_floor
    assert "kept the poor text layer" in page.reason


def test_ocr_mangled_course_codes_are_repaired_at_ingest(tmp_path: Path, settings) -> None:
    """Symmetry with the query side: the index must carry the repaired form.

    The published routines contain "CSE'211" and "CS€ 211". attachments/schemas.py
    repairs the query side; repairing only one side means the lexical arm never
    matches and the routine join silently returns nothing.
    """
    pdf = fixtures.ocr_code_pdf(tmp_path / "codes.pdf")
    result = ingest_document(pdf, provider=None, settings=settings, resume=False)
    text = result.pages[0].text

    assert "CSE 211" in text and "CSE'211" not in text
    assert "ENG 207" in text


def test_a_failed_escalation_is_retried_on_the_next_run(tmp_path: Path, settings) -> None:
    """A checkpoint records completed work, not a page that never got its vision read.

    Without this, one transient 429 leaves a page permanently indexed from the
    text layer the routing table already judged unusable.
    """
    pdf = fixtures.bad_ocr_pdf(tmp_path / "bad_ocr.pdf")

    # First run: no provider, so the escalation is recorded but not performed.
    first = ingest_document(pdf, provider=None, settings=settings, resume=False)
    assert first.pages[0].needs_retry

    # Second run, resuming, now with a provider: the page is read after all.
    provider = RecordingProvider()
    second = ingest_document(pdf, provider, settings=settings, resume=True)
    assert provider.page_reads == 1
    assert second.pages[0].text == normalize(provider.text)
    assert not second.pages[0].needs_retry


def test_a_completed_page_is_not_reprocessed(tmp_path: Path, settings) -> None:
    """The retry rule must not defeat checkpointing itself."""
    pdf = fixtures.bad_ocr_pdf(tmp_path / "bad_ocr.pdf")
    first = RecordingProvider()
    ingest_document(pdf, first, settings=settings, resume=False)
    assert first.page_reads == 1

    second = RecordingProvider()
    ingest_document(pdf, second, settings=settings, resume=True)
    assert second.page_reads == 0
