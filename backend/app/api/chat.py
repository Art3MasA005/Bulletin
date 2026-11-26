"""POST /chat -- the full pipeline, streamed. PRD 7.2 steps 1-9.

Shape of the handler, and why it is this shape:

    retrieve (database)  ->  plan (floor gate)  ->  StreamingResponse (model)

Everything that touches the database happens BEFORE the response starts. A
dependency-provided connection is not safe to use inside a streaming generator
-- FastAPI closes `yield` dependencies around the response, not around the body
-- and the pipeline does not need one there anyway: the generator only needs the
already-assembled prompt.

It also means a request that must be refused (unauthenticated, unconfirmed
attachment, nothing above the score floor) is refused with a real status code
before a single byte of stream is committed.

SSE events, in order:

    event: citations   the sources, assembled from the retrieved chunks
    event: delta       answer text, many
    event: done        {"status": "answered" | "not_found"}
    event: error       only if generation fails mid-stream

Citations go first, not last as PRD 7.2 step 9 suggests, for one reason: they
are known before generation starts, and a client that has them up front can
render the Source Cards while the answer streams instead of after it.
"""

from __future__ import annotations

import json
import logging
from collections.abc import Iterator

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.api.conversations import (
    enforce_daily_quota,
    open_conversation,
    record_answer,
    record_question,
)
from app.api.deps import CallerDep, ConnDep, ProviderDep, SettingsDep
from app.attachments.join import UnconfirmedJoin, build_join_plan, require_confirmation
from app.attachments.schemas import ConfirmedEntities
from app.config import UnknownModel
from app.generate.answer import AnswerPlan, plan_answer, stream_answer
from app.providers.base import Message, Provider, ProviderError
from app.retrieve.pipeline import retrieve, retrieve_for_join

logger = logging.getLogger(__name__)

router = APIRouter(tags=["chat"])

ATTACHMENT_SQL = """
select a.id::text, a.extraction_confirmed, a.extracted_json
from attachments a
where a.id = %(attachment_id)s and a.user_id = %(user_id)s
"""


class ChatTurn(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    content: str


class ChatRequest(BaseModel):
    question: str = Field(min_length=1, max_length=2000)
    history: list[ChatTurn] = Field(default_factory=list, max_length=20)
    # Omit to start a new conversation; the id comes back in the `meta` event.
    conversation_id: str | None = None
    # Present only for the routine join. The attachment must already be
    # confirmed (CLAUDE.md #3); this endpoint refuses it otherwise.
    attachment_id: str | None = None
    # A key from GET /models; omit for the default. Never a raw model id.
    model: str | None = Field(default=None, max_length=40)


class ModelOption(BaseModel):
    key: str
    name: str
    maker: str
    cost: str
    default: bool


class ModelsResponse(BaseModel):
    models: list[ModelOption]


def _sse(event: str, payload: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"


def _load_confirmed(conn, *, attachment_id: str, user_id: str) -> ConfirmedEntities:
    """Load a confirmed attachment, or refuse. CLAUDE.md #3, PRD 8.3.

    The user_id predicate is in the query, not applied to its result: another
    student's attachment must be indistinguishable from one that does not
    exist (PRD 8.4).
    """
    with conn.cursor() as cur:
        cur.execute(ATTACHMENT_SQL, {"attachment_id": attachment_id, "user_id": user_id})
        row = cur.fetchone()

    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="attachment not found")

    require_confirmation({"id": row[0], "extraction_confirmed": row[1]})

    payload = row[2] or {}
    codes = [c.get("code", "") for c in payload.get("courses", []) if c.get("code")]
    if not codes:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="no course codes were confirmed for this attachment",
        )
    return ConfirmedEntities(attachment_id=row[0], codes=codes, confirmed=True)


def _stream(
    plan: AnswerPlan,
    provider: Provider,
    *,
    pool,
    conversation_id: str,
    models: list[str] | None = None,
) -> Iterator[str]:
    """Serialize one answer as SSE, then persist it. Never raises."""
    yield _sse("meta", {"conversation_id": conversation_id, "query_lang": plan.query_lang})
    yield _sse("citations", {"citations": [c.as_dict() for c in plan.citations]})

    citations = [c.as_dict() for c in plan.citations]

    if not plan.grounded:
        # CLAUDE.md #9: the not-found response, with no provider call at all.
        yield _sse("delta", {"text": plan.fallback_text})
        record_answer(
            pool,
            conversation_id=conversation_id,
            text=plan.fallback_text,
            query_lang=plan.query_lang,
            citations=[],
        )
        yield _sse("done", {"status": "not_found", "reason": plan.reason})
        return

    pieces: list[str] = []
    try:
        for piece in stream_answer(plan, provider=provider, stream=True, models=models):
            if piece:
                pieces.append(piece)
                yield _sse("delta", {"text": piece})
    except ProviderError as exc:
        logger.warning("generation failed mid-stream: %s", exc)
        yield _sse("error", {"detail": "the answer could not be completed", "retryable": True})
        return

    # Written after the last token, from a fresh pooled connection: the
    # request's connection is already closed by now (see api/conversations.py).
    record_answer(
        pool,
        conversation_id=conversation_id,
        text="".join(pieces),
        query_lang=plan.query_lang,
        citations=citations,
    )
    yield _sse("done", {"status": "answered"})


@router.get("/models", response_model=ModelsResponse)
def models(caller: CallerDep, settings: SettingsDep) -> ModelsResponse:
    """The models the picker offers. Empty when none are configured."""
    del caller  # signed-in only; the list itself is the same for everyone
    default = settings.generation_model
    return ModelsResponse(
        models=[
            ModelOption(key=c.key, name=c.name, maker=c.maker, cost=c.cost, default=c.id == default)
            for c in settings.generation_model_choices
        ]
    )


@router.post("/chat")
def chat(
    body: ChatRequest,
    request: Request,
    caller: CallerDep,
    conn: ConnDep,
    provider: ProviderDep,
    settings: SettingsDep,
) -> StreamingResponse:
    """Answer a question from the caller's institution, streamed."""
    history = [Message(role=t.role, content=t.content) for t in body.history]

    # Before the quota is spent or anything retrieved: a stale client asking
    # for a model that is gone learns it at once.
    try:
        chain = settings.chain_for(body.model) if body.model else None
    except UnknownModel as exc:
        raise HTTPException(
            status_code=422,
            detail="that model is no longer offered; pick another",
        ) from exc

    # PRD 10, before any retrieval or model call.
    enforce_daily_quota(conn, user_id=caller.user_id, settings=settings)

    if body.attachment_id:
        try:
            confirmed = _load_confirmed(
                conn, attachment_id=body.attachment_id, user_id=caller.user_id
            )
        except UnconfirmedJoin as exc:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc

        join_plan = build_join_plan(body.question, confirmed, settings=settings)
        outcome, _ = retrieve_for_join(
            conn,
            plan=join_plan,
            institution_id=caller.institution_id,
            role=caller.role,
            provider=provider,
            settings=settings,
        )
        candidates = outcome.all_candidates()
        plan = plan_answer(
            body.question,
            candidates,
            query_lang="en",
            join=outcome,
            settings=settings,
        )
    else:
        result = retrieve(
            conn,
            question=body.question,
            institution_id=caller.institution_id,
            role=caller.role,
            provider=provider,
            history=history,
            settings=settings,
        )
        plan = plan_answer(
            result.query.text,
            result.finalists,
            query_lang=result.query.lang,
            dense_scores=result.dense_scores,
            settings=settings,
        )

    conversation_id = open_conversation(
        conn,
        user_id=caller.user_id,
        institution_id=caller.institution_id,
        conversation_id=body.conversation_id,
        question=body.question,
    )
    record_question(
        conn,
        conversation_id=conversation_id,
        question=body.question,
        query_lang=plan.query_lang,
        attachment_id=body.attachment_id,
        user_id=caller.user_id,
    )

    logger.info(
        "chat user=%s institution=%s conversation=%s grounded=%s citations=%d model=%s",
        caller.user_id,
        caller.institution_id,
        conversation_id,
        plan.grounded,
        len(plan.citations),
        body.model or "default",
    )
    return StreamingResponse(
        _stream(
            plan,
            provider,
            pool=getattr(request.app.state, "pool", None),
            conversation_id=conversation_id,
            models=chain,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            # Proxies that buffer would defeat streaming entirely.
            "X-Accel-Buffering": "no",
        },
    )
