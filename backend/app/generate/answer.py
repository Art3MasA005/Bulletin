"""Grounded answer generation. PRD 7.2 steps 7-9.

Everything here exists to keep one promise: every sentence the user reads is
traceable to a published page of their own institution.

  * **The floor gate runs before the provider, not after.** CLAUDE.md #9:
    below RETRIEVAL_SCORE_FLOOR, return the not-found response WITHOUT calling
    the LLM. `plan_answer` returns a plan with no messages in that case, and
    `stream_answer` has no code path that reaches a provider from it -- so the
    guarantee is structural rather than a remembered `if`.

  * **Citations are built from the retrieved chunks, not parsed out of the
    model's prose.** A model that invents "[4]" cannot invent a source: the
    terminal SSE event carries the citation list this module assembled.

  * **The snippet is in the source's own language** (PRD 7.2). A Bangla notice
    answering an English question shows Bangla in the Source Card, so the user
    can check the claim against the page.

The attachment join adds one rule (PRD 8.2 step 6): the attachment establishes
which questions to ask and is never cited as authority, and any confirmed
course code with no published match is stated outright rather than omitted.
"""

from __future__ import annotations

import logging
import re
from collections.abc import Iterator, Mapping, Sequence
from dataclasses import dataclass, field

from app.attachments.join import JoinOutcome
from app.config import Settings, get_settings
from app.providers.base import Message, Provider
from app.retrieve.dense import Candidate

logger = logging.getLogger(__name__)

# Enough of the source to verify the claim, short enough to render in a Source
# Card without a scroll (DESIGN 4).
SNIPPET_CHARS = 240

# DESIGN 8: "The not-found copy says nothing was FOUND -- not that the answer
# does not exist." The distinction is the honest one: the system knows what it
# retrieved, never what the institution has.
NOT_FOUND: dict[str, str] = {
    "en": ("Nothing in the published documents covers this. Try rephrasing, or ask the office."),
    "bn": (
        "প্রকাশিত নথিপত্রে এই বিষয়ে কিছু পাওয়া যায়নি। প্রশ্নটি অন্যভাবে জিজ্ঞাসা করুন, অথবা অফিসে যোগাযোগ করুন।"
    ),
}

ANSWER_SYSTEM = (
    "You answer questions about one institution's published documents.\n\n"
    "Rules:\n"
    "- Use ONLY the numbered context blocks below. You have no other knowledge "
    "of this institution.\n"
    "- Cite the block you used after each fact, as [1], [2]. Every factual "
    "sentence needs a citation.\n"
    "- If the context does not contain the answer, say exactly that. Do not "
    "reason toward a likely answer.\n"
    "- Never state a date, fee, or deadline that is not printed in the "
    "context.\n"
    "- Answer in {language}, even when the sources are in another language.\n"
    "- Be brief. This is read on a phone."
)

JOIN_SYSTEM = (
    "\n- The course list came from a document the student attached. It tells "
    "you which courses to look up; it is NOT a source and must never be cited."
    "\n- Answer per course code, in the order given."
    "\n- For any course code listed as having no published information, say so "
    "explicitly by code. Do not omit it and do not guess."
)

_LANGUAGE_NAME = {"en": "English", "bn": "Bangla", "mixed": "the language of the question"}

# A course code as it appears in a query: two-to-five letters, optional
# separator, three-to-five digits. Matches the canonical form written by
# attachments.schemas.normalize_course_code.
_CODE = re.compile(r"\b([A-Za-z]{2,5})[\s'`-]?(\d{3,5})\b")


class NotGrounded(RuntimeError):
    """A caller tried to generate from a plan that did not clear the floor."""


@dataclass(frozen=True)
class Citation:
    """One numbered source, as it reaches the client in the terminal SSE event."""

    n: int
    chunk_id: int
    doc_id: str
    title: str | None
    page_no: int
    section: str | None
    lang: str
    snippet: str

    def as_dict(self) -> dict[str, object]:
        return {
            "n": self.n,
            "chunk_id": self.chunk_id,
            "doc_id": self.doc_id,
            "title": self.title,
            "page_no": self.page_no,
            "section": self.section,
            "lang": self.lang,
            "snippet": self.snippet,
        }


@dataclass
class AnswerPlan:
    """What will be sent to the model, or the not-found response instead.

    `grounded=False` means the messages list is empty and the answer text is
    already decided. There is no path from this state to a provider call.
    """

    grounded: bool
    query_lang: str
    messages: list[Message] = field(default_factory=list)
    citations: list[Citation] = field(default_factory=list)
    fallback_text: str = ""
    reason: str = ""


def _snippet(content: str, *, limit: int = SNIPPET_CHARS) -> str:
    """First `limit` characters of the source, in the source's own language."""
    text = " ".join(content.split())
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + "…"


def build_context(candidates: Sequence[Candidate]) -> tuple[str, list[Citation]]:
    """Numbered context blocks plus the citation list they correspond to.

    Numbering is 1-based and shared: block [3] in the prompt is citation n=3 in
    the terminal event, so a client can map a citation marker in streamed text
    to a Source Card without parsing anything.
    """
    blocks: list[str] = []
    citations: list[Citation] = []

    for n, candidate in enumerate(candidates, start=1):
        header = f"[{n}] page {candidate.page_no}"
        if candidate.section:
            header += f" — {candidate.section}"
        blocks.append(f"{header}\n{candidate.content.strip()}")
        citations.append(
            Citation(
                n=n,
                chunk_id=candidate.chunk_id,
                doc_id=candidate.doc_id,
                title=candidate.doc_title,
                page_no=candidate.page_no,
                section=candidate.section,
                lang=candidate.lang,
                snippet=_snippet(candidate.content),
            )
        )

    return "\n\n".join(blocks), citations


def not_found_text(query_lang: str) -> str:
    """The not-found copy in the query's language."""
    return NOT_FOUND.get(query_lang, NOT_FOUND["en"])


def _exact_code_match(query: str, content: str) -> bool:
    """Whether a course code in the query appears verbatim in this chunk.

    The one case where a low cosine score is not evidence of irrelevance: "CSE
    4101" and "CSE 4107" embed almost identically, so dense similarity is a
    poor signal on exactly the tokens the routine join depends on (PRD 8.2
    step 5). An exact token match in the lexical arm is stronger evidence than
    the cosine number, and gating it away would break the join feature.
    """
    codes = {f"{m.group(1).upper()}{m.group(2)}" for m in _CODE.finditer(query)}
    if not codes:
        return False
    haystack = {f"{m.group(1).upper()}{m.group(2)}" for m in _CODE.finditer(content)}
    return bool(codes & haystack)


def clears_floor(
    candidates: Sequence[Candidate],
    *,
    query: str,
    dense_scores: Mapping[int, float] | None = None,
    settings: Settings | None = None,
) -> tuple[bool, str]:
    """Whether anything retrieved is good enough to answer from. CLAUDE.md #9.

    The floor is compared against DENSE similarity, never the fused RRF score
    (~1/60 by construction, no absolute meaning) and never ts_rank (a different
    scale entirely). `dense_scores` supplies the similarity for candidates that
    arrived through fusion and have since lost their arm-level score.
    """
    settings = settings or get_settings()
    floor = settings.retrieval_score_floor

    if not candidates:
        return False, "no candidates retrieved"

    best = 0.0
    for candidate in candidates:
        score = (dense_scores or {}).get(candidate.chunk_id)
        if score is None and candidate.arm == "dense":
            score = candidate.score
        if score is not None:
            best = max(best, score)
        if _exact_code_match(query, candidate.content):
            return True, f"exact course-code match in chunk {candidate.chunk_id}"

    if best >= floor:
        return True, f"top dense similarity {best:.3f} >= floor {floor:.2f}"
    return False, f"top dense similarity {best:.3f} < floor {floor:.2f}"


def _join_context(outcome: JoinOutcome) -> str:
    """The confirmed course list, as instruction rather than as evidence."""
    lines = [f"Confirmed course codes: {', '.join(outcome.by_code)}"]
    if outcome.missing_codes:
        lines.append("No published information was found for: " + ", ".join(outcome.missing_codes))
    return "\n".join(lines)


def plan_answer(
    question: str,
    candidates: Sequence[Candidate],
    *,
    query_lang: str,
    dense_scores: Mapping[int, float] | None = None,
    join: JoinOutcome | None = None,
    settings: Settings | None = None,
) -> AnswerPlan:
    """Assemble the generation request, or the not-found response.

    Returns a plan with `grounded=False` and no messages when the floor gate
    fails -- the LLM is not called, which is the point of the gate.
    """
    settings = settings or get_settings()
    ok, reason = clears_floor(
        candidates, query=question, dense_scores=dense_scores, settings=settings
    )

    if not ok:
        logger.info("floor gate refused query_lang=%s reason=%s", query_lang, reason)
        return AnswerPlan(
            grounded=False,
            query_lang=query_lang,
            fallback_text=not_found_text(query_lang),
            reason=reason,
        )

    blocks, citations = build_context(candidates)
    system = ANSWER_SYSTEM.format(language=_LANGUAGE_NAME.get(query_lang, _LANGUAGE_NAME["mixed"]))
    if join is not None:
        system += JOIN_SYSTEM

    user_parts = []
    if join is not None:
        user_parts.append(_join_context(join))
    user_parts.append(f"Context:\n{blocks}")
    user_parts.append(f"Question: {question}")

    logger.info(
        "answer plan query_lang=%s blocks=%d join=%s reason=%s",
        query_lang,
        len(citations),
        bool(join),
        reason,
    )
    return AnswerPlan(
        grounded=True,
        query_lang=query_lang,
        messages=[
            Message(role="system", content=system),
            Message(role="user", content="\n\n".join(user_parts)),
        ],
        citations=citations,
        reason=reason,
    )


def stream_answer(
    plan: AnswerPlan,
    *,
    provider: Provider | None = None,
    stream: bool = True,
    models: Sequence[str] | None = None,
) -> Iterator[str]:
    """Yield the answer text for a plan.

    An ungrounded plan yields the not-found copy and never touches `provider`
    -- pass provider=None to prove it.
    """
    if not plan.grounded:
        yield plan.fallback_text
        return

    if provider is None:
        raise NotGrounded("a grounded plan needs a provider to generate from")

    if models is None:
        yield from provider.generate(plan.messages, stream=stream)
    else:
        yield from provider.generate(plan.messages, stream=stream, models=models)
