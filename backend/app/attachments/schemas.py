"""Typed schemas for chat-attachment extraction. PRD 8.2.

Structured per-course extraction, NOT table-as-text. PRD 8.3: "A routine is a
table, and grid misalignment is the characteristic vision-model failure: a time
from one row lands against a course from another. Structured per-course
extraction reduces this; the confirmation step catches what remains."

Per-field confidence is not decoration. It drives the warn treatment in the
confirmation UI (DESIGN 5) for anything below
settings.extraction_confidence_floor.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, Field, field_validator

# "CSE 4101", "CSE-4101", "cse4101" all normalize to "CSE 4101".
# The separator class includes the apostrophe and backtick because OCR emits
# them for a hyphen -- see _OCR_LETTER_FIXES.
COURSE_CODE_RE = re.compile(r"^\s*([A-Za-z]{2,5})\s*['`‘’-]?\s*(\d{3,5})\s*$")

# The same code with the batch/section suffix the routines print after it:
# "CSE 201-CSE(181)", "MAT 103-CSE(181)", "EEE-303-EEE(191)". Measured on a
# real routine read by the vision model (2026-08-28), which returned every
# course in this form. The leading code is the part that identifies the course;
# the suffix identifies which batch sits the exam.
COURSE_CODE_WITH_SECTION_RE = re.compile(
    r"^\s*([A-Za-z]{2,5})\s*['`‘’-]?\s*(\d{3,5})\s*-\s*[A-Za-z]{2,5}\s*\([^)]*\)\s*$"
)

# Systematic OCR substitutions measured on the real Green University corpus
# (2026-08-28): the institution publishes scanned-then-OCR'd PDFs, and the text
# layer renders 'E' as the euro sign inside course codes -- "CS€ 211", "EE€ 201",
# "T€X 311". Applied ONLY here, never to document text at large, because the euro
# sign is a legitimate character in a fee schedule.
_OCR_LETTER_FIXES = str.maketrans({"€": "E", "£": "E"})


def normalize_course_code(raw: str) -> str:
    """Canonical course-code form: uppercase letters, single space, digits.

    The lexical arm matches these as exact tokens (PRD 8.2 step 5), so the form
    written by the user in the confirmation chip and the form indexed from the
    institutional document must agree.

    Repairs the OCR confusions observed in the real corpus. Without this, 2.9%
    of course codes in the published exam routines never match a query -- a
    silent hole in exactly the retrieval arm the routine-join depends on.
    """
    raw = (raw or "").translate(_OCR_LETTER_FIXES)
    match = COURSE_CODE_RE.match(raw) or COURSE_CODE_WITH_SECTION_RE.match(raw)
    if not match:
        return (raw or "").strip().upper()
    return f"{match.group(1).upper()} {match.group(2)}"


class CourseEntry(BaseModel):
    """One course read off a student's routine or registration slip."""

    code: str = Field(description="Course code exactly as printed, e.g. 'CSE 4101'")
    title: str | None = Field(default=None, description="Course title if printed")
    section: str | None = Field(default=None, description="Section if printed")
    confidence: float = Field(
        ge=0.0,
        le=1.0,
        description=(
            "How confident the read of THIS course code is. Lower it when the "
            "text is blurred, skewed, cropped, or ambiguous between similar "
            "digits such as 1/7 or 0/8."
        ),
    )

    @field_validator("code")
    @classmethod
    def _canonicalise(cls, value: str) -> str:
        return normalize_course_code(value)

    def needs_review(self, floor: float) -> bool:
        return self.confidence < floor


class RoutineExtraction(BaseModel):
    """Everything read from one attached routine image or PDF page."""

    semester: str | None = Field(default=None, description="e.g. 'Spring 2026'")
    section: str | None = Field(default=None, description="Overall section if printed")
    student_id: str | None = Field(default=None, description="Student ID if printed")
    courses: list[CourseEntry] = Field(default_factory=list)

    def flagged(self, floor: float) -> list[CourseEntry]:
        """Courses that must render with a warn dot in the confirmation UI."""
        return [c for c in self.courses if c.needs_review(floor)]

    def codes(self) -> list[str]:
        """Deduplicated canonical course codes, order preserved."""
        seen: dict[str, None] = {}
        for course in self.courses:
            if course.code:
                seen.setdefault(course.code, None)
        return list(seen)


class ConfirmedEntities(BaseModel):
    """What the user actually confirmed. The ONLY valid input to a join query.

    CLAUDE.md warning #3 / PRD 8.3: the system must never answer a join query
    without explicit user confirmation of the extracted entities. join.py
    accepts this type and nothing else, so the boundary is enforced by the type
    system rather than by a remembered convention.
    """

    attachment_id: str
    codes: list[str] = Field(min_length=1)
    confirmed: bool = Field(description="Must be True; the user pressed the action")

    @field_validator("codes")
    @classmethod
    def _canonicalise_all(cls, values: list[str]) -> list[str]:
        return [normalize_course_code(v) for v in values if v and v.strip()]

    @field_validator("confirmed")
    @classmethod
    def _must_be_confirmed(cls, value: bool) -> bool:
        if not value:
            raise ValueError(
                "ConfirmedEntities requires confirmed=True. A join answer "
                "cannot be generated from unconfirmed extraction (CLAUDE.md #3)."
            )
        return value
