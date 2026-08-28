"""Publish one uploaded document into the index. PRD 7.1, 9, 11.

    uploaded -> extracting -> embedding -> ready
                     \\                       \\
                      '--> failed <-----------'

The status column is the whole point of this module. Ingestion takes tens of
seconds (vision escalation is per page), the upload endpoint returns
immediately (PRD 11), and the admin watching the documents list needs to know
which of "still working" and "gave up" is happening -- DESIGN §6.6 gives those
two states different treatments, so they cannot be collapsed into one.

`failure_reason` is written for a person, not for a log: it is shown in the
documents list and has to say what to do next.

Chunk writes are all-or-nothing per document. A half-written document answers
questions from half a source, which is worse than a document that failed
visibly.
"""

from __future__ import annotations

import logging
from pathlib import Path

from app.config import Settings, get_settings
from app.ingest.chunk import Chunk, chunk_pages
from app.ingest.pipeline import ingest_document
from app.providers.base import Provider, ProviderError

logger = logging.getLogger(__name__)

# One request per batch of chunks: small enough that a failure loses little,
# large enough that a 40-page document is not 40 round trips.
EMBED_BATCH = 32

SET_STATUS_SQL = """
update documents
set status = %(status)s,
    page_count = coalesce(%(page_count)s, page_count),
    lang_detected = coalesce(%(lang)s, lang_detected),
    extraction_method = coalesce(%(method)s::extraction_method, extraction_method),
    extraction_confidence = coalesce(%(confidence)s, extraction_confidence),
    failure_reason = %(failure_reason)s
where id = %(doc_id)s
"""

DELETE_CHUNKS_SQL = "delete from chunks where doc_id = %(doc_id)s"

INSERT_CHUNK_SQL = """
insert into chunks
    (doc_id, institution_id, audience, content, page_no, section, lang,
     extraction_method, embedding)
values
    (%(doc_id)s, %(institution_id)s, %(audience)s, %(content)s, %(page_no)s,
     %(section)s, %(lang)s, %(method)s, %(embedding)s)
"""


def set_status(
    conn,
    *,
    doc_id: str,
    status: str,
    page_count: int | None = None,
    lang: str | None = None,
    method: str | None = None,
    confidence: float | None = None,
    failure_reason: str | None = None,
) -> None:
    with conn.cursor() as cur:
        cur.execute(
            SET_STATUS_SQL,
            {
                "doc_id": doc_id,
                "status": status,
                "page_count": page_count,
                "lang": lang,
                "method": method,
                "confidence": confidence,
                "failure_reason": failure_reason,
            },
        )
    conn.commit()


def _dominant_method(pages) -> tuple[str, float]:
    counts: dict[str, int] = {}
    for page in pages:
        counts[page.method] = counts.get(page.method, 0) + 1
    if not counts:
        return "native_text", 0.0
    method = max(counts, key=counts.get)  # type: ignore[arg-type]
    same = [p for p in pages if p.method == method]
    return method, sum(p.confidence for p in same) / len(same)


def _document_lang(chunks: list[Chunk]) -> str:
    counts: dict[str, int] = {}
    for chunk in chunks:
        counts[chunk.lang] = counts.get(chunk.lang, 0) + 1
    return max(counts, key=counts.get) if counts else "en"  # type: ignore[arg-type]


def embed_chunks(chunks: list[Chunk], provider: Provider, settings: Settings) -> list[list[float]]:
    """Embed every chunk, asserting the configured dimension as it goes."""
    vectors: list[list[float]] = []
    for start in range(0, len(chunks), EMBED_BATCH):
        batch = chunks[start : start + EMBED_BATCH]
        got = provider.embed([c.content for c in batch])
        if len(got) != len(batch):
            raise ProviderError(f"embedded {len(got)} of {len(batch)} chunks")
        for vector in got:
            if len(vector) != settings.embedding_dim:
                raise ProviderError(
                    f"embedding dimension {len(vector)} != BULLETIN_EMBEDDING_DIM "
                    f"{settings.embedding_dim}; the schema and the model disagree"
                )
        vectors.extend(got)
    return vectors


def publish_document(
    pool,
    provider: Provider,
    *,
    doc_id: str,
    institution_id: str,
    audience: str,
    path: Path,
    settings: Settings | None = None,
    cleanup: bool = True,
) -> str:
    """Extract, chunk, embed, and index one document. Returns the final status.

    Runs as a background task, so it never raises into a request: every failure
    ends as `status = failed` with a reason an admin can act on.
    """
    settings = settings or get_settings()

    try:
        with pool.connection() as conn:
            set_status(conn, doc_id=doc_id, status="extracting")

        result = ingest_document(path, provider, settings=settings)

        if result.rejected:
            with pool.connection() as conn:
                set_status(conn, doc_id=doc_id, status="failed", failure_reason=result.rejected)
            logger.warning("publish rejected doc_id=%s code=%s", doc_id, result.reject_code)
            return "failed"

        chunks = chunk_pages(
            [(p.page_no, p.text, p.method) for p in result.pages],
            audience=audience,
            settings=settings,
        )
        if not chunks:
            with pool.connection() as conn:
                set_status(
                    conn,
                    doc_id=doc_id,
                    status="failed",
                    failure_reason=(
                        "Nothing could be read from this document. It may be blank or "
                        "unreadable. Check the file and upload it again."
                    ),
                )
            return "failed"

        method, confidence = _dominant_method(result.pages)
        with pool.connection() as conn:
            set_status(
                conn,
                doc_id=doc_id,
                status="embedding",
                page_count=len(result.pages),
                lang=_document_lang(chunks),
                method=method,
                confidence=confidence,
            )

        vectors = embed_chunks(chunks, provider, settings)

        # One transaction: replace, never append. Re-publishing after a fix
        # must not leave the previous extraction's chunks retrievable next to
        # the new ones.
        with pool.connection() as conn:
            with conn.cursor() as cur:
                cur.execute(DELETE_CHUNKS_SQL, {"doc_id": doc_id})
                for chunk, vector in zip(chunks, vectors, strict=True):
                    cur.execute(
                        INSERT_CHUNK_SQL,
                        {
                            "doc_id": doc_id,
                            "institution_id": institution_id,
                            "audience": audience,
                            "content": chunk.content,
                            "page_no": chunk.page_no,
                            "section": chunk.section,
                            "lang": chunk.lang,
                            "method": chunk.extraction_method,
                            "embedding": str(vector),
                        },
                    )
            conn.commit()
            set_status(conn, doc_id=doc_id, status="ready")

        logger.info(
            "published doc_id=%s pages=%d chunks=%d method=%s",
            doc_id,
            len(result.pages),
            len(chunks),
            method,
        )
        return "ready"

    except Exception as exc:  # noqa: BLE001 -- a background task must not vanish silently
        logger.exception("publish failed doc_id=%s", doc_id)
        try:
            with pool.connection() as conn:
                set_status(
                    conn,
                    doc_id=doc_id,
                    status="failed",
                    failure_reason=(
                        "This document could not be processed. Try uploading it again; "
                        f"if it keeps failing, the file may be damaged. ({exc})"
                    )[:500],
                )
        except Exception:  # noqa: BLE001 - the database may be what failed
            logger.error("could not even record the failure for doc_id=%s", doc_id)
        return "failed"

    finally:
        if cleanup:
            path.unlink(missing_ok=True)
