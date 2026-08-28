"""Attachment extraction and the confirmation correctness boundary.

Two of the three non-negotiable tests in CLAUDE.md live here in the form they
can take before there is a database:

  * "A join answer cannot generate without extraction_confirmed = true"
    -- enforced by the ConfirmedEntities type, tested directly.
  * "No attachment-derived content appears in chunks"
    -- the DB assertion belongs to Phase 4, but the structural guarantee that
    the attachments package contains no embedding path is testable now.
"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.attachments.extract_entities import extract_routine
from app.attachments.schemas import (
    ConfirmedEntities,
    CourseEntry,
    RoutineExtraction,
    normalize_course_code,
)
from app.config import get_settings
from app.providers.base import Provider, ProviderError

# ── CLAUDE.md #3: the confirmation boundary ─────────────────────────────────


def test_unconfirmed_entities_cannot_be_constructed() -> None:
    """The type system, not a remembered convention, enforces the boundary."""
    with pytest.raises(ValidationError, match="confirmed=True"):
        ConfirmedEntities(attachment_id="a1", codes=["CSE 4101"], confirmed=False)


def test_confirmed_entities_require_at_least_one_code() -> None:
    with pytest.raises(ValidationError):
        ConfirmedEntities(attachment_id="a1", codes=[], confirmed=True)


def test_confirmed_entities_canonicalise_user_edits() -> None:
    """A user retyping a chip must produce the same token the index holds."""
    entities = ConfirmedEntities(
        attachment_id="a1", codes=["cse-4101", " mat 4103 ", "ENG3101"], confirmed=True
    )
    assert entities.codes == ["CSE 4101", "MAT 4103", "ENG 3101"]


def test_extraction_result_is_not_a_confirmation() -> None:
    """extract_routine returns data to show the user, never a licence to answer."""
    extraction = RoutineExtraction(courses=[CourseEntry(code="CSE 4101", confidence=0.99)])
    assert not hasattr(extraction, "confirmed")
    assert not isinstance(extraction, ConfirmedEntities)


# ── course-code canonicalisation ────────────────────────────────────────────


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("CSE 4101", "CSE 4101"),
        ("cse4101", "CSE 4101"),
        ("CSE-4101", "CSE 4101"),
        ("  cse   4101  ", "CSE 4101"),
        ("MAT4103", "MAT 4103"),
        ("EEE 2101", "EEE 2101"),
    ],
)
def test_course_code_canonical_forms(raw: str, expected: str) -> None:
    assert normalize_course_code(raw) == expected


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        # Real strings lifted from the Green University exam routines. The
        # published PDFs are scans with an OCR text layer, and these two
        # substitutions are systematic in it.
        ("CS€ 211", "CSE 211"),
        ("CS€ 323", "CSE 323"),
        ("EE€ 201", "EEE 201"),
        ("EE€-209", "EEE 209"),
        ("T€X 311", "TEX 311"),
        ("ENG'207", "ENG 207"),
        ("ENG'115", "ENG 115"),
        ("BUS'306", "BUS 306"),
        # Already handled before the corpus arrived; kept so the fix cannot
        # regress them.
        ("EEE-303", "EEE 303"),
        ("CsE 435", "CSE 435"),
        ("csE 437", "CSE 437"),
        ("cSE 309", "CSE 309"),
    ],
)
def test_ocr_mangled_codes_from_the_real_corpus(raw: str, expected: str) -> None:
    """CLAUDE.md: an extraction change ships with a case that would have caught it.

    Measured 2026-08-28: 2.9% of the 577 course-code tokens in the corpus failed
    to normalize before this fix. Every failure was one of these two patterns.
    """
    assert normalize_course_code(raw) == expected


def test_unparseable_code_is_kept_not_dropped() -> None:
    """A code we cannot parse still belongs on screen for the user to fix."""
    assert normalize_course_code("Lab (practical)") == "LAB (PRACTICAL)"


# ── per-field confidence drives the warn treatment (DESIGN 5) ───────────────


def test_low_confidence_courses_are_flagged() -> None:
    extraction = RoutineExtraction(
        courses=[
            CourseEntry(code="CSE 4101", confidence=0.99),
            CourseEntry(code="CSE 4107", confidence=0.62),
            CourseEntry(code="MAT 4103", confidence=0.90),
        ]
    )
    flagged = [c.code for c in extraction.flagged(0.9)]
    assert flagged == ["CSE 4107"], "only sub-floor entries carry the warn dot"


def test_codes_are_deduplicated_in_order() -> None:
    extraction = RoutineExtraction(
        courses=[
            CourseEntry(code="CSE 4101", confidence=0.9),
            CourseEntry(code="cse-4101", confidence=0.8),
            CourseEntry(code="MAT 4103", confidence=0.9),
        ]
    )
    assert extraction.codes() == ["CSE 4101", "MAT 4103"]


def test_confidence_must_be_a_probability() -> None:
    with pytest.raises(ValidationError):
        CourseEntry(code="CSE 4101", confidence=1.4)


# ── extraction behaviour ────────────────────────────────────────────────────


class StubVisionProvider(Provider):
    name = "stub"

    def __init__(self, payload: RoutineExtraction | None = None, fail: bool = False):
        self.payload = payload
        self.fail = fail
        self.calls = 0

    def embed(self, texts):
        raise AssertionError("attachments must never be embedded (CLAUDE.md #2)")

    def rerank(self, query, docs):
        raise NotImplementedError

    def generate(self, messages, *, stream=False):
        raise NotImplementedError

    def read_page_image(self, png_bytes, *, lang_hint="auto"):
        raise NotImplementedError

    def extract_structured(self, png_bytes, schema, *, prompt):
        self.calls += 1
        if self.fail:
            raise ProviderError("vision failed", status=503)
        return self.payload


def test_extraction_flags_low_confidence_entries(tmp_path: Path) -> None:
    image = tmp_path / "routine.png"
    image.write_bytes(b"\x89PNG\r\n\x1a\n" + b"0" * 64)

    provider = StubVisionProvider(
        RoutineExtraction(
            semester="Spring 2026",
            courses=[
                CourseEntry(code="CSE 4101", confidence=0.98),
                CourseEntry(code="CSE 4107", confidence=0.55),
            ],
        )
    )
    result = extract_routine(image, provider, attachment_id="att-1")
    assert result.ok
    assert result.requires_review
    assert result.flagged_codes == ["CSE 4107"]


def test_failed_extraction_returns_empty_not_a_guess(tmp_path: Path) -> None:
    """A wrong course code produces a confident wrong exam date (PRD 8.3)."""
    image = tmp_path / "routine.png"
    image.write_bytes(b"\x89PNG\r\n\x1a\n" + b"0" * 64)

    result = extract_routine(image, StubVisionProvider(fail=True), attachment_id="att-2")
    assert not result.ok
    assert result.extraction.courses == []
    assert "by hand" in result.reason


def test_oversized_attachment_is_refused_before_any_vision_call(tmp_path: Path) -> None:
    """Vision is the most expensive operation in the product (PRD 8.5)."""
    image = tmp_path / "huge.png"
    image.write_bytes(b"\x89PNG" + b"0" * (2 * 1024 * 1024))

    provider = StubVisionProvider(RoutineExtraction())
    settings = get_settings().model_copy(update={"attachment_max_mb": 1})
    result = extract_routine(image, provider, attachment_id="att-3", settings=settings)
    assert not result.ok
    assert provider.calls == 0
    assert "limit is 1 MB" in result.reason


# ── CLAUDE.md #2: no path from attachments into the vector index ────────────


def test_attachments_package_contains_no_embedding_path() -> None:
    """Structural guard: `attachments` has no embedding column and no embed call.

    A DB-level assertion follows in Phase 4. This one fails the moment someone
    adds an innocent-looking embed() to this package, which is how a student's
    routine would end up retrievable by another student.
    """
    package = Path(__file__).resolve().parents[1] / "app" / "attachments"
    forbidden = {"embed", "upsert_chunk", "insert_chunk", "index_document"}

    offenders: list[str] = []
    for source in package.glob("*.py"):
        tree = ast.parse(source.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                func = node.func
                name = getattr(func, "attr", None) or getattr(func, "id", None)
                if name in forbidden:
                    offenders.append(f"{source.name}:{node.lineno} calls {name}()")
    assert not offenders, "attachment content must never reach chunks: " + "; ".join(offenders)


def test_attachments_never_import_the_chunk_writer() -> None:
    package = Path(__file__).resolve().parents[1] / "app" / "attachments"
    for source in package.glob("*.py"):
        text = source.read_text(encoding="utf-8")
        assert "from app.ingest.chunk" not in text, f"{source.name} imports the chunker"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        # What the vision model actually returned from a real routine page
        # (2026-08-28): the course code followed by the batch that sits it.
        ("CSE 201-CSE(181)", "CSE 201"),
        ("MAT 103-CSE(181)", "MAT 103"),
        ("CSE 435-CSE(201)", "CSE 435"),
        ("EEE-303-EEE(191)", "EEE 303"),
        ("CSE 311", "CSE 311"),
    ],
)
def test_a_batch_suffix_is_stripped_from_the_code(raw: str, expected: str) -> None:
    """The course is what the student asks about; the batch is not part of it.

    Keeping the suffix would make the confirmation chip read "CSE 201-CSE(181)"
    and send that to the lexical arm, which then matches only the routine that
    prints the same batch -- and never a notice that says plain "CSE 201".
    """
    assert normalize_course_code(raw) == expected
