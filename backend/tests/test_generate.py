"""Condensing and grounded answering. PRD 7.2 steps 1-9.

The load-bearing test in this file is the floor gate: CLAUDE.md #9 says that
below RETRIEVAL_SCORE_FLOOR the not-found response is returned WITHOUT calling
the LLM. It is asserted here by handing the generator a provider that raises on
contact.
"""

from __future__ import annotations

from collections.abc import Iterator, Sequence

import pytest

from app.attachments.join import build_join_plan, collect
from app.attachments.schemas import ConfirmedEntities
from app.config import get_settings
from app.generate.answer import (
    NOT_FOUND,
    AnswerPlan,
    NotGrounded,
    build_context,
    clears_floor,
    not_found_text,
    plan_answer,
    stream_answer,
)
from app.generate.condense import MAX_CONDENSED_CHARS, condense
from app.providers.base import Message, Provider, ProviderError, ProviderUnsupported, Vector
from app.retrieve.dense import Candidate

SETTINGS = get_settings()


class _Stub(Provider):
    """A provider that returns a scripted answer and records what it was sent."""

    name = "stub"

    def __init__(self, reply: str = "ok", *, fail: bool = False) -> None:
        self.reply = reply
        self.fail = fail
        self.calls: list[list[Message]] = []

    def embed(self, texts: Sequence[str]) -> list[Vector]:  # pragma: no cover
        raise ProviderUnsupported("embed")

    def rerank(self, query: str, docs: Sequence[str]) -> list[float]:  # pragma: no cover
        raise ProviderUnsupported("rerank")

    def generate(self, messages: Sequence[Message], *, stream: bool = False) -> Iterator[str]:
        self.calls.append(list(messages))
        if self.fail:
            raise ProviderError("upstream 502", status=502, retryable=True)
        yield self.reply

    def read_page_image(self, png_bytes: bytes, *, lang_hint: str = "auto") -> str:
        raise ProviderUnsupported("vision")  # pragma: no cover

    def extract_structured(self, png_bytes: bytes, schema, *, prompt: str):
        raise ProviderUnsupported("structured")  # pragma: no cover


class _Exploding(Provider):
    """Any contact at all is a test failure."""

    name = "exploding"

    def _boom(self, *_: object, **__: object):
        raise AssertionError("the LLM was called below the retrieval score floor")

    embed = rerank = generate = read_page_image = extract_structured = _boom  # type: ignore[assignment]


def _candidate(
    chunk_id: int = 1,
    *,
    content: str = "Final examinations begin on 12 December 2026.",
    score: float = 0.80,
    arm: str = "dense",
    lang: str = "en",
    page_no: int = 3,
    section: str | None = None,
) -> Candidate:
    return Candidate(
        chunk_id=chunk_id,
        doc_id="doc-1",
        content=content,
        page_no=page_no,
        section=section,
        lang=lang,
        extraction_method="native_text",
        score=score,
        arm=arm,
    )


# ── CLAUDE.md #9: the floor gate ────────────────────────────────────────────


def test_below_the_floor_no_llm_call_happens() -> None:
    weak = _candidate(score=SETTINGS.retrieval_score_floor - 0.05)
    plan = plan_answer("what is the hostel fee", [weak], query_lang="en")

    assert not plan.grounded
    assert plan.messages == []
    assert "".join(stream_answer(plan, provider=_Exploding())) == NOT_FOUND["en"]


def test_no_candidates_is_a_not_found_not_a_crash() -> None:
    plan = plan_answer("anything", [], query_lang="en")
    assert not plan.grounded
    assert "no candidates" in plan.reason


def test_not_found_copy_follows_the_query_language() -> None:
    plan = plan_answer("হোস্টেল ফি কত", [], query_lang="bn")
    assert "".join(stream_answer(plan)) == NOT_FOUND["bn"]
    assert not_found_text("de") == NOT_FOUND["en"]


def test_above_the_floor_generates() -> None:
    stub = _Stub("Final exams start 12 December [1].")
    plan = plan_answer("when do final exams start", [_candidate()], query_lang="en")

    assert plan.grounded
    assert "".join(stream_answer(plan, provider=stub)) == "Final exams start 12 December [1]."
    assert len(stub.calls) == 1


def test_a_grounded_plan_without_a_provider_raises_rather_than_faking_an_answer() -> None:
    plan = plan_answer("when do final exams start", [_candidate()], query_lang="en")
    with pytest.raises(NotGrounded):
        list(stream_answer(plan, provider=None))


def test_lexical_only_candidate_uses_the_dense_score_map() -> None:
    """A fused candidate has lost its arm-level score; the map supplies it."""
    lexical = _candidate(chunk_id=9, arm="lexical", score=0.02)
    below = plan_answer("hostel fee", [lexical], query_lang="en")
    assert not below.grounded

    above = plan_answer("hostel fee", [lexical], query_lang="en", dense_scores={9: 0.71})
    assert above.grounded


def test_exact_course_code_match_clears_the_floor_despite_a_low_cosine() -> None:
    """PRD 8.2 step 5: dense similarity is a poor signal on course codes.

    "CSE 4101" and "CSE 4107" embed almost identically, so gating an exact
    lexical match on cosine would break the routine join outright.
    """
    hit = _candidate(
        content="CSE 4101 Software Engineering — 14 December, 9:00 AM",
        score=0.11,
        arm="lexical",
    )
    ok, reason = clears_floor([hit], query="CSE 4101 exam date")
    assert ok and "exact course-code" in reason


def test_a_different_course_code_does_not_clear_the_floor() -> None:
    hit = _candidate(content="CSE 4107 Compiler Design — 16 December", score=0.11, arm="lexical")
    ok, _ = clears_floor([hit], query="CSE 4101 exam date")
    assert not ok


# ── citations ───────────────────────────────────────────────────────────────


def test_context_numbering_matches_citation_numbering() -> None:
    """A [3] in streamed text must map to citation n=3 without parsing prose."""
    blocks, citations = build_context([_candidate(1), _candidate(2), _candidate(3)])
    assert [c.n for c in citations] == [1, 2, 3]
    for citation in citations:
        assert f"[{citation.n}]" in blocks


def test_citation_snippet_stays_in_the_source_language() -> None:
    """PRD 7.2: the user verifies the claim against the page as printed."""
    bn = _candidate(content="চূড়ান্ত পরীক্ষা ১২ ডিসেম্বর শুরু হবে।", lang="bn")
    plan = plan_answer("when do final exams start", [bn], query_lang="en")
    assert plan.citations[0].snippet.startswith("চূড়ান্ত")
    assert plan.citations[0].lang == "bn"


def test_answer_language_is_the_query_language_not_the_source_language() -> None:
    bn = _candidate(content="চূড়ান্ত পরীক্ষা ১২ ডিসেম্বর শুরু হবে।", lang="bn")
    plan = plan_answer("when do final exams start", [bn], query_lang="en")
    assert "Answer in English" in plan.messages[0].content


def test_long_snippets_are_truncated_for_the_source_card() -> None:
    plan = plan_answer("fees", [_candidate(content="x " * 400)], query_lang="en")
    assert plan.citations[0].snippet.endswith("…")
    assert len(plan.citations[0].snippet) <= 241


def test_the_prompt_forbids_outside_knowledge() -> None:
    plan = plan_answer("when do final exams start", [_candidate()], query_lang="en")
    system = plan.messages[0].content
    assert "ONLY the numbered context" in system
    assert "no other knowledge" in system


# ── the join answer ─────────────────────────────────────────────────────────


def _outcome(hits: dict[str, list[Candidate]], *codes: str):
    confirmed = ConfirmedEntities(attachment_id="att-1", codes=list(codes), confirmed=True)
    plan = build_join_plan("when are my exams", confirmed)
    return collect(plan, hits)


def test_join_answer_states_the_codes_with_no_published_match() -> None:
    """Silently omitting a course is a wrong answer, not a partial one."""
    hit = _candidate(content="CSE 4101 Software Engineering — 14 December")
    outcome = _outcome({"CSE 4101": [hit]}, "CSE 4101", "EEE 2101")

    plan = plan_answer("when are my exams", [hit], query_lang="en", join=outcome)
    user = plan.messages[1].content
    assert "No published information was found for: EEE 2101" in user
    assert "say so" in plan.messages[0].content


def test_join_prompt_forbids_citing_the_attachment() -> None:
    """PRD 8.2 step 6: the routine says which questions to ask, not the answers."""
    hit = _candidate(content="CSE 4101 Software Engineering — 14 December")
    outcome = _outcome({"CSE 4101": [hit]}, "CSE 4101")
    plan = plan_answer("when are my exams", [hit], query_lang="en", join=outcome)
    assert "never be cited" in plan.messages[0].content


def test_join_below_the_floor_still_refuses() -> None:
    """The join path does not get its own exemption from the gate."""
    weak = _candidate(content="Library opening hours", score=0.10, arm="dense")
    outcome = _outcome({"CSE 4101": [weak]}, "CSE 4101")
    plan = plan_answer("when are my exams", [weak], query_lang="en", join=outcome)
    assert not plan.grounded


# ── condensing ──────────────────────────────────────────────────────────────


def test_no_history_means_no_llm_call() -> None:
    stub = _Stub("rewritten")
    result = condense("when is the final exam", provider=stub)
    assert result.text == "when is the final exam"
    assert not result.rewritten
    assert stub.calls == []


def test_a_follow_up_is_rewritten_against_history() -> None:
    stub = _Stub("When is the Summer 2026 final exam?")
    history = [
        Message(role="user", content="what is in the Summer 2026 routine"),
        Message(role="assistant", content="It lists the final examinations."),
    ]
    result = condense("when is it?", history, provider=stub)
    assert result.rewritten
    assert result.text == "When is the Summer 2026 final exam?"


def test_a_condenser_that_answers_instead_of_rewriting_is_ignored() -> None:
    """A bad rewrite silently retrieves for a question the user never asked."""
    stub = _Stub("x" * (MAX_CONDENSED_CHARS + 1))
    history = [Message(role="user", content="earlier question")]
    result = condense("when is it?", history, provider=stub)
    assert not result.rewritten
    assert result.text == "when is it?"
    assert "looks like an answer" in result.reason


def test_an_empty_rewrite_falls_back_to_the_question() -> None:
    stub = _Stub("   ")
    history = [Message(role="user", content="earlier question")]
    assert condense("when is it?", history, provider=stub).text == "when is it?"


def test_a_rewrite_that_changes_language_is_rejected() -> None:
    """CLAUDE.md #6: the answer language follows the query language."""
    stub = _Stub("চূড়ান্ত পরীক্ষা কবে?")
    history = [Message(role="user", content="what is in the routine")]
    result = condense("when is it?", history, provider=stub)
    assert not result.rewritten
    assert "changed the language" in result.reason


def test_a_provider_failure_degrades_to_the_raw_question() -> None:
    stub = _Stub(fail=True)
    history = [Message(role="user", content="earlier question")]
    result = condense("when is it?", history, provider=stub)
    assert result.text == "when is it?"
    assert result.reason.startswith("error:")


def test_query_language_is_detected() -> None:
    assert condense("when is the final exam").lang == "en"
    assert condense("চূড়ান্ত পরীক্ষা কবে").lang == "bn"


def test_only_recent_turns_are_sent() -> None:
    stub = _Stub("Standalone question?")
    history = [Message(role="user", content=f"q{i}") for i in range(20)]
    condense("when is it?", history, provider=stub, turns=2)
    sent = stub.calls[0]
    # system + 2 turns * 2 messages + the question
    assert len(sent) == 1 + 4 + 1


def test_answer_plan_is_inert_by_default() -> None:
    """A default-constructed plan cannot accidentally look grounded."""
    plan = AnswerPlan(grounded=False, query_lang="en")
    assert plan.messages == [] and plan.citations == []


def test_a_citation_carries_the_document_title() -> None:
    """DESIGN §4: the Source Card leads with the document's title.

    Without it the card falls back to the chunk's section heading, which on a
    scanned notice is a line of OCR noise -- "Date: 10'hAugust,2026" is what a
    student actually saw on the emulator before this was carried through.
    """
    candidate = Candidate(
        chunk_id=1,
        doc_id="doc-1",
        content="Final examinations begin on 12 December 2026.",
        page_no=3,
        section="Date: 10'hAugust,2026",
        lang="en",
        extraction_method="native_text",
        score=0.8,
        doc_title="Final Examination Notice, Summer 2026",
    )

    plan = plan_answer("when do finals start", [candidate], query_lang="en")
    citation = plan.citations[0]
    assert citation.title == "Final Examination Notice, Summer 2026"
    assert citation.as_dict()["title"] == "Final Examination Notice, Summer 2026"
