"""Confirmed course codes -> retrieval queries. PRD 8.2 steps 5-6.

This is the second half of the routine-join feature. The first half
(extract_entities.py) reads a photograph; this half turns what the user
*confirmed* into queries against the institution's published documents.

Three rules the module exists to enforce:

  1. **Nothing enters here unconfirmed.** The only accepted input is
     ConfirmedEntities, which cannot be constructed with confirmed=False
     (CLAUDE.md #3). `require_confirmation` covers the other direction -- a
     stored attachment row whose `extraction_confirmed` is still false.

  2. **One query per course code, not one query for all of them.** A single
     "CSE 4101 CSE 4107 EEE 2101 exam date" query returns the chunks that
     mention the most codes, which on an exam routine is the page header. Per
     code, the lexical arm matches the exact token and the answer can cite a
     different source for each course.

  3. **A code with no result is reported, never dropped.** "Your exam dates
     are X and Y" when the student registered for three courses is a wrong
     answer, not a partial one. JoinOutcome.missing_codes carries them to the
     generator, which must say so explicitly.

The attachment is never cited as authority (PRD 8.2 step 6). It establishes
*which* questions to ask; every fact in the answer comes from a retrieved
institutional chunk.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field

from app.attachments.schemas import ConfirmedEntities, normalize_course_code
from app.config import Settings, get_settings
from app.retrieve.dense import Candidate

logger = logging.getLogger(__name__)


class UnconfirmedJoin(RuntimeError):
    """A join was attempted against an attachment the user has not confirmed.

    Raised, never returned as an empty result: a caller that forgets to check
    a returned flag produces exactly the failure CLAUDE.md #3 forbids.
    """


# Words that belong to the student asking, never to the institutional document.
# "When is my CSE 4101 exam" retrieves better as "CSE 4101 exam" -- a published
# routine says "Course Code", "Date", "Time", and never "my".
_PERSONAL = frozenset(
    {
        "i",
        "me",
        "my",
        "mine",
        "myself",
        "we",
        "our",
        "ours",
        "you",
        "your",
        "yours",
        "am",
        "is",
        "are",
        "was",
        "were",
        "do",
        "does",
        "did",
        "have",
        "has",
        "had",
        "the",
        "a",
        "an",
        "of",
        "for",
        "to",
        "in",
        "on",
        "at",
        "and",
        "or",
        "please",
        "tell",
        "show",
        "give",
        "can",
        "could",
        "would",
        "will",
    }
)

# Course codes already in the question are dropped from the shared intent
# text: they are added back per code, and leaving them in would make every
# per-code query match every code. The separator class matches the OCR
# confusions normalize_course_code repairs.
_CODE_IN_TEXT = re.compile("\\b[A-Za-z]{2,5}\\s*['`‘’-]?\\s*\\d{3,5}\\b")

_WORD = re.compile(r"[\wঀ-৿]+", re.UNICODE)


@dataclass(frozen=True)
class JoinQuery:
    """One retrieval query, bound to the course code that produced it."""

    code: str
    text: str

    def __str__(self) -> str:  # pragma: no cover - logging convenience
        return f"{self.code}: {self.text}"


@dataclass
class JoinPlan:
    """The full set of queries for one confirmed attachment."""

    attachment_id: str
    question: str
    queries: list[JoinQuery]
    dropped_codes: list[str] = field(default_factory=list)

    @property
    def codes(self) -> list[str]:
        return [q.code for q in self.queries]

    def __len__(self) -> int:
        return len(self.queries)


@dataclass
class JoinOutcome:
    """Retrieval results grouped by course code, plus the codes that found none.

    `missing_codes` is the reason this type exists. The generator needs to
    distinguish "no exam date is published for CSE 4101" from "CSE 4101 was
    never asked about", and only this structure carries that difference.
    """

    attachment_id: str
    question: str
    by_code: dict[str, list[Candidate]]
    missing_codes: list[str]

    @property
    def answered_codes(self) -> list[str]:
        return [code for code, hits in self.by_code.items() if hits]

    @property
    def complete(self) -> bool:
        return not self.missing_codes

    def all_candidates(self) -> list[Candidate]:
        """Every retrieved candidate, deduplicated by chunk id, order preserved."""
        seen: dict[int, Candidate] = {}
        for hits in self.by_code.values():
            for hit in hits:
                seen.setdefault(hit.chunk_id, hit)
        return list(seen.values())


def require_confirmation(attachment: object) -> None:
    """Guard for a stored attachment row before any join retrieval.

    Accepts anything carrying `extraction_confirmed` -- a Pydantic model, a
    dataclass, or the mapping a database driver returns. Raises UnconfirmedJoin
    unless it is exactly True; a missing attribute is treated as unconfirmed,
    because a row shape that has lost the column must fail closed.
    """
    if isinstance(attachment, dict):
        confirmed = attachment.get("extraction_confirmed")
        identifier = attachment.get("id", "?")
    else:
        confirmed = getattr(attachment, "extraction_confirmed", None)
        identifier = getattr(attachment, "id", "?")

    if confirmed is not True:
        logger.warning(
            "join refused attachment_id=%s extraction_confirmed=%r", identifier, confirmed
        )
        raise UnconfirmedJoin(
            f"attachment {identifier} has extraction_confirmed={confirmed!r}; "
            "a join answer cannot be generated without user confirmation "
            "(CLAUDE.md #3, PRD 8.3)"
        )


def intent_terms(question: str) -> str:
    """The part of the question worth adding to every per-code query.

    Strips course codes (added back per code) and the personal/function words
    that no institutional document contains. Returns "" for a question made
    entirely of those -- "what about mine?" contributes nothing, and an empty
    intent is better than a query of stopwords.
    """
    without_codes = _CODE_IN_TEXT.sub(" ", question or "")
    kept = [w for w in _WORD.findall(without_codes) if w.lower() not in _PERSONAL]
    return " ".join(kept)


def query_for_code(code: str, question: str) -> JoinQuery:
    """Build the retrieval query for one confirmed course code."""
    canonical = normalize_course_code(code)
    intent = intent_terms(question)
    text = f"{canonical} {intent}".strip()
    return JoinQuery(code=canonical, text=text)


def build_join_plan(
    question: str,
    confirmed: ConfirmedEntities,
    *,
    settings: Settings | None = None,
) -> JoinPlan:
    """Confirmed entities -> one retrieval query per course code.

    Only ConfirmedEntities is accepted, so an unconfirmed extraction cannot
    reach retrieval by any path through this module.

    Fan-out is capped at settings.join_max_codes: each code is a separate
    retrieval round trip, and a registration slip with thirty lines would turn
    one question into thirty. Codes beyond the cap are returned in
    `dropped_codes` so the caller can tell the user, never silently discarded.
    """
    if not isinstance(confirmed, ConfirmedEntities):
        raise UnconfirmedJoin(
            f"build_join_plan requires ConfirmedEntities, got {type(confirmed).__name__} "
            "(CLAUDE.md #3)"
        )

    settings = settings or get_settings()
    cap = settings.join_max_codes

    seen: dict[str, None] = {}
    for code in confirmed.codes:
        if code:
            seen.setdefault(code, None)
    codes = list(seen)

    kept, dropped = codes[:cap], codes[cap:]
    plan = JoinPlan(
        attachment_id=confirmed.attachment_id,
        question=question,
        queries=[query_for_code(code, question) for code in kept],
        dropped_codes=dropped,
    )
    logger.info(
        "join plan attachment_id=%s codes=%d dropped=%d",
        confirmed.attachment_id,
        len(plan.queries),
        len(dropped),
    )
    return plan


def collect(plan: JoinPlan, results: dict[str, list[Candidate]]) -> JoinOutcome:
    """Group per-code retrieval results, recording every code that found nothing."""
    by_code = {q.code: list(results.get(q.code, [])) for q in plan.queries}
    missing = [code for code, hits in by_code.items() if not hits]
    missing.extend(plan.dropped_codes)

    logger.info(
        "join outcome attachment_id=%s answered=%d missing=%d",
        plan.attachment_id,
        sum(1 for hits in by_code.values() if hits),
        len(missing),
    )
    return JoinOutcome(
        attachment_id=plan.attachment_id,
        question=plan.question,
        by_code=by_code,
        missing_codes=missing,
    )
