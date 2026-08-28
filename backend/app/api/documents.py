"""Publishing and listing institutional documents. PRD 7.1, 9, 10, 11.

    POST   /documents        upload and publish        (admin)
    GET    /documents        list, with status         (any member)
    GET    /documents/{id}   one, with status          (any member)
    DELETE /documents/{id}   remove it and its chunks  (admin)

The upload returns immediately with `status: uploaded` and does the work in a
background task (PRD 11), because ingestion runs vision per page and a phone
cannot hold a request open for a minute.

`audience` has no default, here or in the schema. DESIGN §6.7 makes the
selector a required choice in the publish flow for the same reason the column
has no default: whoever publishes a document must decide who may read it, and a
forgotten field must not quietly mean "everyone".
"""

from __future__ import annotations

import logging
import tempfile
from datetime import datetime
from pathlib import Path

from fastapi import (
    APIRouter,
    BackgroundTasks,
    File,
    Form,
    HTTPException,
    Request,
    UploadFile,
    status,
)
from pydantic import BaseModel

from app.api.deps import CallerDep, ConnDep, ProviderDep, SettingsDep
from app.config import Settings
from app.db import storage
from app.ingest.extract import IMAGE_SUFFIXES, PDF_SUFFIXES
from app.ingest.publish import publish_document
from app.retrieve.audience import Audience, Role, allowed_audiences

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/documents", tags=["documents"])

ACCEPTED_SUFFIXES = PDF_SUFFIXES | IMAGE_SUFFIXES
# Starlette renamed both constants; the numbers are the stable thing.
HTTP_413_TOO_LARGE = 413
HTTP_422_INVALID = 422

_FILE = File(...)
_TITLE = Form(...)
_AUDIENCE = Form(...)

COUNT_SQL = "select count(*) from documents where institution_id = %(institution_id)s"

INSERT_SQL = """
insert into documents
    (institution_id, uploaded_by, title, filename, mime_type, storage_path,
     audience, status)
values
    (%(institution_id)s, %(uploaded_by)s, %(title)s, %(filename)s, %(mime_type)s,
     %(storage_path)s, %(audience)s, 'uploaded')
returning id::text, created_at
"""

LIST_SQL = """
select d.id::text, d.title, d.filename, d.audience::text, d.status::text,
       d.page_count, d.lang_detected, d.extraction_method::text,
       d.extraction_confidence, d.failure_reason, d.created_at,
       (select count(*) from chunks c where c.doc_id = d.id) as chunk_count
from documents d
where d.institution_id = %(institution_id)s
  and d.audience = any(%(audiences)s)
order by d.created_at desc
limit %(limit)s
"""

GET_SQL = LIST_SQL.replace(
    "and d.audience = any(%(audiences)s)",
    "and d.audience = any(%(audiences)s) and d.id = %(doc_id)s",
).replace("limit %(limit)s", "")

DELETE_SQL = """
delete from documents
where id = %(doc_id)s and institution_id = %(institution_id)s
returning storage_path
"""


class Document(BaseModel):
    """A document as the admin list renders it (DESIGN §6.6)."""

    id: str
    title: str
    filename: str
    audience: str
    status: str
    page_count: int | None = None
    lang_detected: str | None = None
    extraction_method: str | None = None
    extraction_confidence: float | None = None
    failure_reason: str | None = None
    chunk_count: int = 0
    created_at: datetime


class DocumentList(BaseModel):
    documents: list[Document]
    total: int


def _row_to_document(row) -> Document:
    return Document(
        id=row[0],
        title=row[1],
        filename=row[2],
        audience=row[3],
        status=row[4],
        page_count=row[5],
        lang_detected=row[6],
        extraction_method=row[7],
        extraction_confidence=row[8],
        failure_reason=row[9],
        created_at=row[10],
        chunk_count=row[11],
    )


def _require_admin(caller) -> None:
    if caller.role is not Role.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only an administrator can publish or remove documents.",
        )


def _validate(upload: UploadFile, content: bytes, settings: Settings) -> str:
    suffix = Path(upload.filename or "").suffix.lower()
    if suffix not in ACCEPTED_SUFFIXES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Publish a PDF or an image.",
        )
    if not content:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="The uploaded file is empty."
        )
    size_mb = len(content) / (1024 * 1024)
    if size_mb > settings.max_upload_mb:
        raise HTTPException(
            status_code=HTTP_413_TOO_LARGE,
            detail=(f"This file is {size_mb:.1f} MB. The limit is {settings.max_upload_mb} MB."),
        )
    return suffix


@router.post("", response_model=Document, status_code=status.HTTP_202_ACCEPTED)
def publish(
    request: Request,
    background: BackgroundTasks,
    caller: CallerDep,
    conn: ConnDep,
    provider: ProviderDep,
    settings: SettingsDep,
    file: UploadFile = _FILE,
    title: str = _TITLE,
    audience: str = _AUDIENCE,
) -> Document:
    """Store the file, return immediately, and ingest in the background."""
    _require_admin(caller)

    try:
        audience_value = Audience(audience).value
    except ValueError as exc:
        raise HTTPException(
            status_code=HTTP_422_INVALID,
            detail=f"audience must be one of {[a.value for a in Audience]}",
        ) from exc

    content = file.file.read()
    suffix = _validate(file, content, settings)

    with conn.cursor() as cur:
        cur.execute(COUNT_SQL, {"institution_id": caller.institution_id})
        if cur.fetchone()[0] >= settings.documents_per_institution:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    f"This institution has reached the limit of "
                    f"{settings.documents_per_institution} documents."
                ),
            )

    path = storage.object_path(
        user_id=caller.institution_id, filename=file.filename or f"document{suffix}"
    )
    try:
        storage.upload(
            bucket=storage.DOCUMENTS_BUCKET,
            path=path,
            content=content,
            content_type=file.content_type or "application/pdf",
            settings=settings,
        )
    except storage.StorageError as exc:
        logger.error("document upload failed institution=%s: %s", caller.institution_id, exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The file could not be stored. Try again.",
        ) from exc

    with conn.cursor() as cur:
        cur.execute(
            INSERT_SQL,
            {
                "institution_id": caller.institution_id,
                "uploaded_by": caller.user_id,
                "title": title.strip() or (file.filename or "Untitled"),
                "filename": file.filename or f"document{suffix}",
                "mime_type": file.content_type or "application/pdf",
                "storage_path": f"{storage.DOCUMENTS_BUCKET}/{path}",
                "audience": audience_value,
            },
        )
        doc_id, created_at = cur.fetchone()
    conn.commit()

    # The background task cannot use this request's connection, so it takes the
    # pool. The bytes are staged on disk because extraction needs a file (a PDF
    # page is rendered from it); publish_document deletes it when it is done.
    staged = Path(tempfile.mkdtemp(prefix="bulletin-doc-")) / f"upload{suffix}"
    staged.write_bytes(content)
    background.add_task(
        publish_document,
        getattr(request.app.state, "pool", None),
        provider,
        doc_id=doc_id,
        institution_id=caller.institution_id,
        audience=audience_value,
        path=staged,
        settings=settings,
    )

    logger.info(
        "document accepted id=%s institution=%s audience=%s by=%s",
        doc_id,
        caller.institution_id,
        audience_value,
        caller.user_id,
    )
    return Document(
        id=doc_id,
        title=title.strip() or (file.filename or "Untitled"),
        filename=file.filename or f"document{suffix}",
        audience=audience_value,
        status="uploaded",
        created_at=created_at,
    )


@router.get("", response_model=DocumentList)
def list_documents(caller: CallerDep, conn: ConnDep, limit: int = 100) -> DocumentList:
    """Documents this caller may see. The audience filter is in the query."""
    audiences = sorted(a.value for a in allowed_audiences(caller.role))
    with conn.cursor() as cur:
        cur.execute(
            LIST_SQL,
            {
                "institution_id": caller.institution_id,
                "audiences": audiences,
                "limit": min(int(limit), 500),
            },
        )
        rows = cur.fetchall()
    documents = [_row_to_document(row) for row in rows]
    return DocumentList(documents=documents, total=len(documents))


@router.get("/{doc_id}", response_model=Document)
def get_document(doc_id: str, caller: CallerDep, conn: ConnDep) -> Document:
    """One document. Out of audience is 404, never 403.

    A 403 would confirm that a teacher-scoped document exists, which is the
    same leak the retrieval filter exists to prevent (PRD §4).
    """
    audiences = sorted(a.value for a in allowed_audiences(caller.role))
    with conn.cursor() as cur:
        cur.execute(
            GET_SQL,
            {
                "institution_id": caller.institution_id,
                "audiences": audiences,
                "doc_id": doc_id,
            },
        )
        row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="document not found")
    return _row_to_document(row)


@router.delete("/{doc_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_document(doc_id: str, caller: CallerDep, conn: ConnDep, settings: SettingsDep) -> None:
    """Remove a document, its chunks (by cascade), and its stored file."""
    _require_admin(caller)

    with conn.cursor() as cur:
        cur.execute(DELETE_SQL, {"doc_id": doc_id, "institution_id": caller.institution_id})
        row = cur.fetchone()
    conn.commit()

    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="document not found")

    # The row is gone either way; a storage failure here leaves an orphaned
    # object, which is worth a log and not worth failing the request.
    bucket, _, object_path = str(row[0]).partition("/")
    if object_path:
        try:
            storage.remove(bucket=bucket, paths=[object_path], settings=settings)
        except storage.StorageError as exc:
            logger.warning("document row deleted but file remains: %s", exc)

    logger.info("document deleted id=%s by=%s", doc_id, caller.user_id)
