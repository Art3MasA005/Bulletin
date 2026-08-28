"""Dense retrieval arm: pgvector cosine over HNSW. PRD 7.2 step 5.

The audience predicate and the institution predicate are both in the WHERE
clause of the vector search itself -- never applied to its output. CLAUDE.md #4:

    "Restrict candidate chunks by the caller's role BEFORE vector search.
    Post-filtering leaks through the not-found boundary."

Concretely, `ORDER BY embedding <=> %s LIMIT 20` after a filtered WHERE returns
the 20 nearest chunks the caller is allowed to see. Filtering afterwards would
return the 20 nearest chunks overall and then delete some, so a student asking
about a teacher-only policy gets a short list where an unrelated question gets a
full one -- and the reranker and score floor would both have seen forbidden text.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from app.retrieve.audience import Role, allowed_audiences

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Candidate:
    """One retrieved chunk with its score. Shared by both arms so fuse.py can
    combine them without knowing which produced what."""

    chunk_id: int
    doc_id: str
    content: str
    page_no: int
    section: str | None
    lang: str
    extraction_method: str
    score: float
    # The published title, joined from `documents`. The Source Card (DESIGN §4)
    # leads with it; without it the card falls back to the chunk's section
    # heading, which on a scanned notice is a line of OCR noise. Defaulted so a
    # candidate can still be built in a test without inventing a document.
    doc_title: str | None = None
    arm: str = "dense"


# `<=>` is pgvector's cosine DISTANCE (0 = identical), so similarity is 1 - it.
# Selecting the similarity directly keeps the score floor comparison in
# PRD 7.2 step 7 the right way round.
DENSE_SQL = """
select
    c.id,
    c.doc_id::text,
    c.content,
    c.page_no,
    c.section,
    c.lang,
    c.extraction_method::text,
    1 - (c.embedding <=> %(query_vec)s::vector) as similarity,
    d.title
from chunks c
join documents d on d.id = c.doc_id
where c.institution_id = %(institution_id)s
  and c.audience = any(%(audiences)s)
order by c.embedding <=> %(query_vec)s::vector
limit %(limit)s
"""


def build_dense_query(
    *,
    institution_id: str,
    role: Role | str,
    query_vector: list[float],
    limit: int,
) -> tuple[str, dict]:
    """Return (sql, params) for the dense arm.

    Separated from execution so tests can assert the predicate is present in the
    query text itself, without a live database.
    """
    audiences = sorted(a.value for a in allowed_audiences(role))
    params = {
        "institution_id": institution_id,
        "audiences": audiences,
        "query_vec": query_vector,
        "limit": limit,
    }
    return DENSE_SQL, params


def search(
    conn,
    *,
    institution_id: str,
    role: Role | str,
    query_vector: list[float],
    limit: int,
) -> list[Candidate]:
    """Run the dense arm against an open psycopg connection."""
    sql, params = build_dense_query(
        institution_id=institution_id, role=role, query_vector=query_vector, limit=limit
    )
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    results = [
        Candidate(
            chunk_id=row[0],
            doc_id=row[1],
            content=row[2],
            page_no=row[3],
            section=row[4],
            lang=row[5],
            extraction_method=row[6],
            score=float(row[7]),
            doc_title=row[8] if len(row) > 8 else None,
            arm="dense",
        )
        for row in rows
    ]
    logger.info(
        "dense arm institution=%s role=%s returned=%d top=%.4f",
        institution_id,
        role,
        len(results),
        results[0].score if results else 0.0,
    )
    return results
