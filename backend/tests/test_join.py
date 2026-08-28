"""The routine join: confirmed codes -> retrieval queries. PRD 8.2 steps 5-6.

The third non-negotiable test in CLAUDE.md ("a join answer cannot generate
without extraction_confirmed = true") has two halves. The type-level half lives
in test_attachments.py; the row-level half -- a stored attachment whose flag is
still false -- lives here.
"""

from __future__ import annotations

from dataclasses import dataclass

import pytest

from app.attachments.join import (
    JoinQuery,
    UnconfirmedJoin,
    build_join_plan,
    collect,
    intent_terms,
    query_for_code,
    require_confirmation,
)
from app.attachments.schemas import ConfirmedEntities
from app.config import get_settings
from app.retrieve.dense import Candidate


def _confirmed(*codes: str, attachment_id: str = "att-1") -> ConfirmedEntities:
    return ConfirmedEntities(attachment_id=attachment_id, codes=list(codes), confirmed=True)


def _candidate(chunk_id: int, content: str) -> Candidate:
    return Candidate(
        chunk_id=chunk_id,
        doc_id="doc-1",
        content=content,
        page_no=1,
        section=None,
        lang="en",
        extraction_method="native_text",
        score=0.72,
    )


# ── CLAUDE.md #3: the confirmation boundary, at the row level ───────────────


@dataclass
class _Row:
    id: str
    extraction_confirmed: bool


@pytest.mark.parametrize("flag", [False, None, 0, "true"])
def test_join_refuses_an_unconfirmed_attachment_row(flag: object) -> None:
    """Only the boolean True passes. "true" and 1 are how this silently breaks."""
    with pytest.raises(UnconfirmedJoin, match="CLAUDE.md #3"):
        require_confirmation({"id": "att-9", "extraction_confirmed": flag})


def test_join_fails_closed_when_the_column_is_missing() -> None:
    """A row shape that lost the column must refuse, not default to allowed."""
    with pytest.raises(UnconfirmedJoin):
        require_confirmation({"id": "att-9"})
    with pytest.raises(UnconfirmedJoin):
        require_confirmation(object())


def test_confirmed_row_passes() -> None:
    require_confirmation(_Row(id="att-1", extraction_confirmed=True))
    require_confirmation({"id": "att-1", "extraction_confirmed": True})


def test_build_join_plan_rejects_anything_but_confirmed_entities() -> None:
    """The unconfirmed extraction type must not reach retrieval by any path."""

    class LooksConfirmed:
        attachment_id = "att-1"
        codes = ["CSE 4101"]
        confirmed = True

    with pytest.raises(UnconfirmedJoin, match="ConfirmedEntities"):
        build_join_plan("when is my exam", LooksConfirmed())  # type: ignore[arg-type]


# ── one query per code ──────────────────────────────────────────────────────


def test_one_query_per_course_code() -> None:
    plan = build_join_plan("when are my final exams", _confirmed("CSE 4101", "EEE 2101"))
    assert plan.codes == ["CSE 4101", "EEE 2101"]
    assert all(q.code in q.text for q in plan.queries)


def test_codes_are_canonicalised_and_deduplicated() -> None:
    plan = build_join_plan("exam date", _confirmed("cse-4101", "CSE 4101", "CS€ 211"))
    assert plan.codes == ["CSE 4101", "CSE 211"]


def test_personal_words_are_stripped_from_the_intent() -> None:
    """A published routine says "exam date", never "my"."""
    assert intent_terms("when is my CSE 4101 final exam") == "when final exam"


def test_other_course_codes_are_stripped_from_the_intent() -> None:
    """Otherwise every per-code query matches every code and the split is pointless."""
    plan = build_join_plan(
        "exam dates for CSE 4101 and EEE 2101", _confirmed("CSE 4101", "EEE 2101")
    )
    cse = next(q for q in plan.queries if q.code == "CSE 4101")
    assert "EEE 2101" not in cse.text
    assert cse.text == "CSE 4101 exam dates"


def test_a_question_of_only_stopwords_still_yields_the_code() -> None:
    query = query_for_code("CSE 4101", "what about mine?")
    assert query == JoinQuery(code="CSE 4101", text="CSE 4101 what about")


def test_bangla_question_terms_survive() -> None:
    """CLAUDE.md #6 symmetry: the Bangla side of a mixed question is not dropped."""
    terms = intent_terms("CSE 4101 পরীক্ষার তারিখ কবে")
    assert "পরীক্ষার" in terms and "তারিখ" in terms
    assert "CSE" not in terms


# ── fan-out cap ─────────────────────────────────────────────────────────────


def test_fanout_is_capped_and_the_overflow_is_reported_not_dropped() -> None:
    cap = get_settings().join_max_codes
    codes = [f"CSE {4100 + i}" for i in range(cap + 3)]
    plan = build_join_plan("exam date", _confirmed(*codes))

    assert len(plan) == cap
    assert plan.dropped_codes == codes[cap:]

    outcome = collect(plan, {code: [_candidate(1, "x")] for code in plan.codes})
    assert outcome.missing_codes == codes[cap:]
    assert not outcome.complete


# ── missing codes ───────────────────────────────────────────────────────────


def test_a_code_with_no_hits_is_reported() -> None:
    """ "Your exams are X and Y" for three registered courses is a wrong answer."""
    plan = build_join_plan("exam date", _confirmed("CSE 4101", "EEE 2101"))
    outcome = collect(plan, {"CSE 4101": [_candidate(1, "CSE 4101 -- 12 Dec")]})

    assert outcome.answered_codes == ["CSE 4101"]
    assert outcome.missing_codes == ["EEE 2101"]
    assert not outcome.complete


def test_complete_outcome_when_every_code_hits() -> None:
    plan = build_join_plan("exam date", _confirmed("CSE 4101", "EEE 2101"))
    outcome = collect(
        plan,
        {"CSE 4101": [_candidate(1, "a")], "EEE 2101": [_candidate(2, "b")]},
    )
    assert outcome.complete
    assert [c.chunk_id for c in outcome.all_candidates()] == [1, 2]


def test_all_candidates_deduplicates_a_shared_chunk() -> None:
    """Two courses on one routine page must not be cited twice."""
    plan = build_join_plan("exam date", _confirmed("CSE 4101", "EEE 2101"))
    shared = _candidate(7, "both courses on one page")
    outcome = collect(plan, {"CSE 4101": [shared], "EEE 2101": [shared]})
    assert [c.chunk_id for c in outcome.all_candidates()] == [7]
