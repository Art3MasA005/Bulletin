"""Conversation history, and the file behind a citation. PRD 9, DESIGN §6.5.

    GET    /conversations              the list the home screen shows
    GET    /conversations/{id}         one conversation with its messages
    DELETE /conversations/{id}         the user removes it
    GET    /documents/{id}/file        a time-limited URL for the source viewer

Every query here is scoped by `user_id` (conversations) or by the caller's
audience (documents), inside the SQL. A conversation belonging to someone else
is missing, not forbidden -- the same rule the retrieval filter follows, for
the same reason.

The source viewer needs the file itself, and the file lives in a private
bucket. The client never gets a permanent URL: this endpoint checks that the
caller may read that document and then signs a URL that expires.
"""

from __future__ import annotations

import logging
from datetime import datetime

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from app.api.deps import CallerDep, ConnDep, SettingsDep
from app.db import storage
from app.retrieve.audience import allowed_audiences

logger = logging.getLogger(__name__)

router = APIRouter(tags=["history"])

# How long a source-viewer URL stays valid. Long enough to open the PDF and
# scroll it, short enough that a shared link stops working.
SIGNED_URL_SECONDS = 900

LIST_CONVERSATIONS_SQL = """
select c.id::text, c.title, c.created_at,
       (select count(*) from messages m where m.conversation_id = c.id),
       (select m.content from messages m
         where m.conversation_id = c.id and m.role = 'assistant'
         order by m.created_at desc limit 1)
from conversations c
where c.user_id = %(user_id)s
order by c.created_at desc
limit %(limit)s
"""

GET_CONVERSATION_SQL = """
select id::text, title, created_at from conversations
where id = %(conversation_id)s and user_id = %(user_id)s
"""

MESSAGES_SQL = """
select m.id::text, m.role, m.content, m.query_lang, m.citations, m.created_at
from messages m
join conversations c on c.id = m.conversation_id
where m.conversation_id = %(conversation_id)s and c.user_id = %(user_id)s
order by m.created_at
"""

DELETE_CONVERSATION_SQL = """
delete from conversations
where id = %(conversation_id)s and user_id = %(user_id)s
returning id::text
"""

DOCUMENT_FILE_SQL = """
select storage_path, title, page_count
from documents
where id = %(doc_id)s
  and institution_id = %(institution_id)s
  and audience = any(%(audiences)s)
"""

PREVIEW_CHARS = 120


class ConversationSummary(BaseModel):
    id: str
    title: str | None = None
    message_count: int
    last_answer: str | None = None
    created_at: datetime


class ConversationList(BaseModel):
    conversations: list[ConversationSummary]
    total: int


class MessageOut(BaseModel):
    id: str
    role: str
    content: str
    query_lang: str | None = None
    citations: list[dict] = Field(default_factory=list)
    created_at: datetime


class ConversationDetail(BaseModel):
    id: str
    title: str | None = None
    created_at: datetime
    messages: list[MessageOut]


class SourceFile(BaseModel):
    """What the source viewer needs: where the file is, and which page to open."""

    document_id: str
    title: str
    page_no: int
    page_count: int | None = None
    url: str
    expires_in: int = SIGNED_URL_SECONDS


def _preview(text: str | None) -> str | None:
    if not text:
        return None
    flat = " ".join(text.split())
    return flat[:PREVIEW_CHARS] + ("…" if len(flat) > PREVIEW_CHARS else "")


@router.get("/conversations", response_model=ConversationList)
def list_conversations(caller: CallerDep, conn: ConnDep, limit: int = 50) -> ConversationList:
    with conn.cursor() as cur:
        cur.execute(
            LIST_CONVERSATIONS_SQL,
            {"user_id": caller.user_id, "limit": min(int(limit), 200)},
        )
        rows = cur.fetchall()

    conversations = [
        ConversationSummary(
            id=row[0],
            title=row[1],
            created_at=row[2],
            message_count=row[3],
            last_answer=_preview(row[4]),
        )
        for row in rows
    ]
    return ConversationList(conversations=conversations, total=len(conversations))


@router.get("/conversations/{conversation_id}", response_model=ConversationDetail)
def get_conversation(conversation_id: str, caller: CallerDep, conn: ConnDep) -> ConversationDetail:
    """One conversation and every message in it, oldest first."""
    with conn.cursor() as cur:
        cur.execute(
            GET_CONVERSATION_SQL,
            {"conversation_id": conversation_id, "user_id": caller.user_id},
        )
        row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="conversation not found")

    with conn.cursor() as cur:
        cur.execute(
            MESSAGES_SQL,
            {"conversation_id": conversation_id, "user_id": caller.user_id},
        )
        message_rows = cur.fetchall()

    return ConversationDetail(
        id=row[0],
        title=row[1],
        created_at=row[2],
        messages=[
            MessageOut(
                id=m[0],
                role=m[1],
                content=m[2],
                query_lang=m[3],
                citations=m[4] or [],
                created_at=m[5],
            )
            for m in message_rows
        ],
    )


@router.delete("/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_conversation(conversation_id: str, caller: CallerDep, conn: ConnDep) -> None:
    """Remove a conversation and, by cascade, its messages and attachments."""
    with conn.cursor() as cur:
        cur.execute(
            DELETE_CONVERSATION_SQL,
            {"conversation_id": conversation_id, "user_id": caller.user_id},
        )
        row = cur.fetchone()
    conn.commit()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="conversation not found")
    logger.info("conversation deleted id=%s user=%s", conversation_id, caller.user_id)


@router.get("/documents/{doc_id}/file", response_model=SourceFile, tags=["documents"])
def document_file(
    doc_id: str,
    caller: CallerDep,
    conn: ConnDep,
    settings: SettingsDep,
    page: int = 1,
) -> SourceFile:
    """A signed, expiring URL for the document behind a citation.

    The audience predicate is in the query, so a student asking for the file of
    a teacher-scoped document gets the same 404 as for one that does not exist.
    """
    audiences = sorted(a.value for a in allowed_audiences(caller.role))
    with conn.cursor() as cur:
        cur.execute(
            DOCUMENT_FILE_SQL,
            {
                "doc_id": doc_id,
                "institution_id": caller.institution_id,
                "audiences": audiences,
            },
        )
        row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="document not found")

    storage_path, title, page_count = row
    bucket, _, object_path = str(storage_path).partition("/")
    if str(storage_path).startswith("local://") or not object_path:
        # A document indexed by `tools/ingest_corpus.py` was never uploaded --
        # its path is `local://<filename>`. Saying so is honest; signing a URL
        # for a bucket named "local:" would fail later as a confusing 503.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This document was indexed from a local file and has nothing to open.",
        )

    try:
        url = storage.signed_url(
            bucket=bucket,
            path=object_path,
            expires_in=SIGNED_URL_SECONDS,
            settings=settings,
        )
    except storage.StorageError as exc:
        logger.error("could not sign %s: %s", storage_path, exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The source file cannot be opened right now.",
        ) from exc

    return SourceFile(
        document_id=doc_id,
        title=title,
        page_no=max(1, int(page)),
        page_count=page_count,
        url=url,
    )
