"""Conversation and message persistence, and the daily question quota.

Kept out of `chat.py` so the route stays what CLAUDE.md asks for -- parse,
delegate, serialize -- and so the write that happens AFTER the stream finishes
has an obvious home.

The ordering matters and is easy to get wrong:

    quota check -> conversation -> user message  (before the response starts)
    ...stream...
    assistant message + citations                (after the last token)

The assistant row cannot be written before the answer exists, and the request's
pooled connection is gone by then -- FastAPI closes `yield` dependencies around
the response, not around the streamed body. So the post-stream write takes a
fresh connection from the pool, which lives on `app.state` and outlives the
request.
"""

from __future__ import annotations

import json
import logging

from fastapi import HTTPException, status

from app.config import Settings

logger = logging.getLogger(__name__)

COUNT_TODAY_SQL = """
select count(*) from messages m
join conversations c on c.id = m.conversation_id
where c.user_id = %(user_id)s
  and m.role = 'user'
  and m.created_at >= now() - interval '1 day'
"""

FIND_CONVERSATION_SQL = """
select id::text from conversations
where id = %(conversation_id)s and user_id = %(user_id)s
"""

CREATE_CONVERSATION_SQL = """
insert into conversations (user_id, institution_id, title)
values (%(user_id)s, %(institution_id)s, %(title)s)
returning id::text
"""

INSERT_MESSAGE_SQL = """
insert into messages (conversation_id, role, content, query_lang, citations)
values (%(conversation_id)s, %(role)s, %(content)s, %(query_lang)s, %(citations)s)
returning id::text
"""

LINK_ATTACHMENT_SQL = """
update attachments set message_id = %(message_id)s
where id = %(attachment_id)s and user_id = %(user_id)s
"""

# A conversation is titled from its first question, trimmed to something that
# fits a list row (DESIGN §6).
TITLE_CHARS = 60


def enforce_daily_quota(conn, *, user_id: str, settings: Settings) -> None:
    """PRD §10: 50 questions per user per day. A friendly cap, not a paywall."""
    with conn.cursor() as cur:
        cur.execute(COUNT_TODAY_SQL, {"user_id": user_id})
        asked = cur.fetchone()[0]
    if asked >= settings.questions_per_day:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"You have asked {settings.questions_per_day} questions today, "
                "which is the daily limit. It resets in 24 hours."
            ),
        )


def title_from(question: str) -> str:
    text = " ".join(question.split())
    return text[:TITLE_CHARS] + ("…" if len(text) > TITLE_CHARS else "")


def open_conversation(
    conn, *, user_id: str, institution_id: str, conversation_id: str | None, question: str
) -> str:
    """Return the conversation to write into, creating one if needed.

    An unknown or someone else's conversation id starts a new conversation
    rather than raising: the id comes from a client that may have been
    reinstalled, and losing the thread is better than losing the question.
    """
    if conversation_id:
        with conn.cursor() as cur:
            cur.execute(
                FIND_CONVERSATION_SQL,
                {"conversation_id": conversation_id, "user_id": user_id},
            )
            row = cur.fetchone()
        if row is not None:
            return row[0]
        logger.info(
            "conversation %s not found for user %s; starting a new one",
            conversation_id,
            user_id,
        )

    with conn.cursor() as cur:
        cur.execute(
            CREATE_CONVERSATION_SQL,
            {
                "user_id": user_id,
                "institution_id": institution_id,
                "title": title_from(question),
            },
        )
        new_id = cur.fetchone()[0]
    conn.commit()
    return new_id


def record_question(
    conn,
    *,
    conversation_id: str,
    question: str,
    query_lang: str,
    attachment_id: str | None = None,
    user_id: str | None = None,
) -> str:
    """Store the user's turn, and attach the routine to it if there was one."""
    with conn.cursor() as cur:
        cur.execute(
            INSERT_MESSAGE_SQL,
            {
                "conversation_id": conversation_id,
                "role": "user",
                "content": question,
                "query_lang": query_lang,
                "citations": "[]",
            },
        )
        message_id = cur.fetchone()[0]

        if attachment_id and user_id:
            cur.execute(
                LINK_ATTACHMENT_SQL,
                {
                    "message_id": message_id,
                    "attachment_id": attachment_id,
                    "user_id": user_id,
                },
            )
    conn.commit()
    return message_id


def record_answer(
    pool,
    *,
    conversation_id: str,
    text: str,
    query_lang: str,
    citations: list[dict],
) -> str | None:
    """Store the assistant's turn once the stream has finished.

    Takes the POOL, not a connection: this runs after the response body, when
    the request's connection is already returned. Failure is logged and
    swallowed -- the user has read the answer by now, and raising here would
    only break a stream that already succeeded.
    """
    if pool is None:
        return None
    try:
        with pool.connection() as conn, conn.cursor() as cur:
            cur.execute(
                INSERT_MESSAGE_SQL,
                {
                    "conversation_id": conversation_id,
                    "role": "assistant",
                    "content": text,
                    "query_lang": query_lang,
                    "citations": json.dumps(citations, ensure_ascii=False),
                },
            )
            message_id = cur.fetchone()[0]
            conn.commit()
        return message_id
    except Exception as exc:  # noqa: BLE001 -- never break a delivered answer
        logger.error("could not store the answer for conversation %s: %s", conversation_id, exc)
        return None
