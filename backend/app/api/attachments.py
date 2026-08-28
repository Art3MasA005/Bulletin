"""Chat attachments: upload, extract, confirm. PRD 8.

The endpoint pair here is the correctness boundary CLAUDE.md #3 describes:

    POST   /attachments            -> entities, ALWAYS unconfirmed
    PATCH  /attachments/{id}/confirm -> the user's corrected entities

Nothing between them can be skipped. `POST` never sets `extraction_confirmed`,
and `PATCH` is the only place in the codebase that sets it true. A join answer
requires that flag (`/chat` checks it), so a client that forgets to confirm
gets a 409, not a wrong exam date.

Three more rules from PRD 8, enforced here:

  * **Nothing an attachment produces reaches `chunks`.** There is no embed call
    in this module and there must never be one (CLAUDE.md #2).
  * **The image is private and expires.** It goes to a private bucket with
    `image_expires_at` seven days out (PRD 8.4); only the extracted JSON is
    kept with the message.
  * **Quotas are checked before the vision call**, not after. Vision is the
    most expensive operation in the product (PRD 8.5).
"""

from __future__ import annotations

import json
import logging
import tempfile
from datetime import UTC, datetime, timedelta
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status
from pydantic import BaseModel, Field

from app.api.deps import CallerDep, ConnDep, ProviderDep, SettingsDep
from app.attachments.extract_entities import extract_routine
from app.attachments.schemas import ConfirmedEntities, CourseEntry, normalize_course_code
from app.config import Settings
from app.db import storage
from app.ingest.extract import IMAGE_SUFFIXES, PDF_SUFFIXES

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/attachments", tags=["attachments"])

# Module-level singletons: FastAPI wants these as defaults, ruff (B008) wants
# no call in a default argument. Both are satisfied by naming them once.
_FILE = File(...)
_CONVERSATION_ID = Form(default=None)

ACCEPTED_SUFFIXES = IMAGE_SUFFIXES | PDF_SUFFIXES

# Starlette renamed this constant; the number is the stable thing.
HTTP_413_TOO_LARGE = 413

COUNT_TODAY_SQL = """
select count(*) from attachments
where user_id = %(user_id)s and created_at >= now() - interval '1 day'
"""

COUNT_IN_CONVERSATION_SQL = """
select count(*) from attachments a
join messages m on m.id = a.message_id
where m.conversation_id = %(conversation_id)s
"""

INSERT_SQL = """
insert into attachments
    (user_id, institution_id, storage_path, mime_type, extracted_json,
     extraction_confirmed, image_expires_at)
values
    (%(user_id)s, %(institution_id)s, %(storage_path)s, %(mime_type)s,
     %(extracted_json)s, false, %(expires_at)s)
returning id::text, image_expires_at
"""

SELECT_SQL = """
select id::text, extracted_json, extraction_confirmed
from attachments
where id = %(attachment_id)s and user_id = %(user_id)s
"""

CONFIRM_SQL = """
update attachments
set extracted_json = %(extracted_json)s, extraction_confirmed = true
where id = %(attachment_id)s and user_id = %(user_id)s
returning id::text
"""


class ExtractedCourse(BaseModel):
    """One course as the confirmation UI renders it (DESIGN §5)."""

    code: str
    title: str | None = None
    section: str | None = None
    confidence: float
    needs_review: bool


class AttachmentCreated(BaseModel):
    """The POST response. Deliberately has no "answer" field.

    An attachment upload produces a question to confirm, never an answer.
    """

    attachment_id: str
    confirmed: bool = Field(default=False, description="Always false here; confirm separately")
    semester: str | None = None
    section: str | None = None
    courses: list[ExtractedCourse] = Field(default_factory=list)
    flagged_codes: list[str] = Field(default_factory=list)
    ok: bool
    reason: str
    image_expires_at: datetime


class ConfirmRequest(BaseModel):
    """What the user actually confirmed, after editing the chips."""

    codes: list[str] = Field(min_length=1, max_length=64)


class ConfirmResponse(BaseModel):
    attachment_id: str
    confirmed: bool
    codes: list[str]


def _check_quota(conn, *, user_id: str, conversation_id: str | None, settings: Settings) -> None:
    """PRD 8.5 limits, checked BEFORE the vision call."""
    with conn.cursor() as cur:
        cur.execute(COUNT_TODAY_SQL, {"user_id": user_id})
        today = cur.fetchone()[0]
        if today >= settings.attachment_questions_per_day:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    f"You have reached today's limit of "
                    f"{settings.attachment_questions_per_day} attachments. Try tomorrow."
                ),
            )

        if conversation_id:
            cur.execute(COUNT_IN_CONVERSATION_SQL, {"conversation_id": conversation_id})
            in_conversation = cur.fetchone()[0]
            if in_conversation >= settings.attachments_per_conversation:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=(
                        f"A conversation can hold "
                        f"{settings.attachments_per_conversation} attachments. "
                        "Start a new conversation for more."
                    ),
                )


def _validate_upload(upload: UploadFile, content: bytes, settings: Settings) -> str:
    """Return the suffix, or raise the 4xx the client should show."""
    suffix = Path(upload.filename or "").suffix.lower()
    if suffix not in ACCEPTED_SUFFIXES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Attach a photo or a PDF of your routine.",
        )
    size_mb = len(content) / (1024 * 1024)
    if size_mb > settings.attachment_max_mb:
        raise HTTPException(
            status_code=HTTP_413_TOO_LARGE,
            detail=(
                f"This file is {size_mb:.1f} MB. The limit is "
                f"{settings.attachment_max_mb} MB. Take a smaller photo and try again."
            ),
        )
    if not content:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="The uploaded file is empty."
        )
    return suffix


@router.post("", response_model=AttachmentCreated, status_code=status.HTTP_201_CREATED)
def create_attachment(
    caller: CallerDep,
    conn: ConnDep,
    provider: ProviderDep,
    settings: SettingsDep,
    file: UploadFile = _FILE,
    conversation_id: str | None = _CONVERSATION_ID,
) -> AttachmentCreated:
    """Read a routine into typed entities and return them UNCONFIRMED."""
    content = file.file.read()
    suffix = _validate_upload(file, content, settings)
    _check_quota(conn, user_id=caller.user_id, conversation_id=conversation_id, settings=settings)

    path = storage.object_path(user_id=caller.user_id, filename=file.filename or f"routine{suffix}")
    try:
        storage.upload(
            bucket=storage.ATTACHMENTS_BUCKET,
            path=path,
            content=content,
            content_type=file.content_type or "application/octet-stream",
            settings=settings,
        )
    except storage.StorageError as exc:
        logger.error("attachment upload failed user=%s: %s", caller.user_id, exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The file could not be stored. Try again.",
        ) from exc

    # The vision model reads bytes from disk (an attachment may be a PDF whose
    # first page has to be rendered), so the upload is staged in a temp file
    # that is removed as soon as the read finishes.
    with tempfile.TemporaryDirectory() as tmp:
        staged = Path(tmp) / f"attachment{suffix}"
        staged.write_bytes(content)
        result = extract_routine(staged, provider, attachment_id="pending", settings=settings)

    expires_at = datetime.now(UTC) + timedelta(days=settings.attachment_image_ttl_days)
    payload = result.extraction.model_dump(mode="json")

    with conn.cursor() as cur:
        cur.execute(
            INSERT_SQL,
            {
                "user_id": caller.user_id,
                "institution_id": caller.institution_id,
                "storage_path": f"{storage.ATTACHMENTS_BUCKET}/{path}",
                "mime_type": file.content_type or "application/octet-stream",
                "extracted_json": json.dumps(payload, ensure_ascii=False),
                "expires_at": expires_at,
            },
        )
        attachment_id, stored_expiry = cur.fetchone()
    conn.commit()

    floor = settings.extraction_confidence_floor
    logger.info(
        "attachment stored id=%s user=%s courses=%d flagged=%d ok=%s",
        attachment_id,
        caller.user_id,
        len(result.extraction.courses),
        len(result.flagged_codes),
        result.ok,
    )
    return AttachmentCreated(
        attachment_id=attachment_id,
        semester=result.extraction.semester,
        section=result.extraction.section,
        courses=[
            ExtractedCourse(
                code=c.code,
                title=c.title,
                section=c.section,
                confidence=c.confidence,
                needs_review=c.needs_review(floor),
            )
            for c in result.extraction.courses
        ],
        flagged_codes=result.flagged_codes,
        ok=result.ok,
        reason=result.reason,
        image_expires_at=stored_expiry,
    )


@router.patch("/{attachment_id}/confirm", response_model=ConfirmResponse)
def confirm_attachment(
    attachment_id: str,
    body: ConfirmRequest,
    caller: CallerDep,
    conn: ConnDep,
) -> ConfirmResponse:
    """Accept the user's corrected course codes. The ONLY place confirmation happens.

    The codes stored are the ones the user confirmed, not the ones the model
    read: a corrected code must survive into the join query, and an extracted
    code the user deleted must not.
    """
    import json

    with conn.cursor() as cur:
        cur.execute(SELECT_SQL, {"attachment_id": attachment_id, "user_id": caller.user_id})
        row = cur.fetchone()
    if row is None:
        # Another user's attachment is indistinguishable from a missing one.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="attachment not found")

    # Validating through ConfirmedEntities normalizes every code the same way
    # the index did, and refuses an empty list (CLAUDE.md #3).
    confirmed = ConfirmedEntities(attachment_id=attachment_id, codes=body.codes, confirmed=True)

    stored = row[1] or {}
    by_code = {normalize_course_code(c.get("code", "")): c for c in stored.get("courses", [])}
    courses = []
    for code in confirmed.codes:
        original = by_code.get(code, {})
        courses.append(
            CourseEntry(
                code=code,
                title=original.get("title"),
                section=original.get("section"),
                # A code the user typed or corrected is certain by definition:
                # a human read the printed page. That is the entire point of
                # the confirmation step (PRD 8.3).
                confidence=1.0,
            ).model_dump(mode="json")
        )
    stored["courses"] = courses

    with conn.cursor() as cur:
        cur.execute(
            CONFIRM_SQL,
            {
                "attachment_id": attachment_id,
                "user_id": caller.user_id,
                "extracted_json": json.dumps(stored, ensure_ascii=False),
            },
        )
        updated = cur.fetchone()
    conn.commit()

    if updated is None:  # pragma: no cover - the select above already proved it exists
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="attachment not found")

    logger.info(
        "attachment confirmed id=%s user=%s codes=%d",
        attachment_id,
        caller.user_id,
        len(confirmed.codes),
    )
    return ConfirmResponse(attachment_id=attachment_id, confirmed=True, codes=list(confirmed.codes))
