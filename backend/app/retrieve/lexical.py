"""Lexical retrieval arm. PRD 7.2 step 5.

Two backends, chosen by query language:

  en  -> `to_tsvector('english', ...)` with ts_rank. Postgres has a real English
         stemmer, so BM25-ish ranking works well.
  bn  -> pg_trgm similarity. Postgres ships NO Bangla stemmer or dictionary, so
         tsvector on Bangla degrades to whitespace tokens with no stemming.
         Trigram similarity is script-agnostic and handles the inflectional
         morphology Bangla has plenty of.

Why this arm matters more than it looks (PRD 8.2 step 5): course codes are exact
alphanumeric tokens. Dense retrieval is poor at them -- "CSE 4101" and "CSE 4107"
embed almost identically -- while lexical matching nails them. The routine-join
feature depends on this arm, and Ablation C is designed to prove it.

Known limitation, stated rather than hidden: this arm contributes nothing
cross-lingually. An English query and a Bangla chunk share zero tokens and zero
trigrams, so both backends return empty. That is exactly the gap Strategy B
(query translation) exists to close -- see translate_query.py and PRD 7.2.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from app.bangla.normalize import detect_lang, normalize_for_match
from app.retrieve.audience import Role, allowed_audiences
from app.retrieve.dense import Candidate

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class LexicalPlan:
    """Which backend was chosen and why -- logged, and surfaced in eval reports."""

    backend: str  # "tsvector_en" | "trigram_bn"
    reason: str


# Audience and institution predicates sit in the WHERE clause here too
# (CLAUDE.md #4).
#
# OR, not AND, and that choice is load-bearing. `websearch_to_tsquery` and
# `plainto_tsquery` both AND every content word, so "when do the final
# examinations start" becomes 'final' & 'examin' & 'start' and matches nothing
# unless a chunk happens to contain all three. Measured on the real corpus
# (2026-08-28): that query returned 0 lexical hits while 'final' & 'examin'
# alone returned 4 -- the arm was silently contributing nothing to exactly the
# question shape users type, which would have quietly emptied Ablation C.
#
# The query text is lexed by `to_tsvector` first (so stemming and stopword
# removal match the index side), then its lexemes are quoted and joined with
# ' | '. Nothing user-typed is ever interpolated into `to_tsquery` unquoted,
# and an empty query becomes NULL, which matches no rows instead of raising.
#
# Recall-first is right here: RRF, the reranker, and the score floor all sit
# downstream and handle precision. An arm that returns nothing cannot be
# corrected by anything downstream.
TSVECTOR_SQL = """
with q as (
    select to_tsquery(
        'english',
        nullif(
            array_to_string(
                array(
                    select quote_literal(lexeme)
                    from unnest(tsvector_to_array(to_tsvector('english', %(query)s))) as lexeme
                ),
                ' | '
            ),
            ''
        )
    ) as query
)
select
    c.id,
    c.doc_id::text,
    c.content,
    c.page_no,
    c.section,
    c.lang,
    c.extraction_method::text,
    ts_rank(to_tsvector('english', c.content), q.query) as rank,
    d.title
from chunks c
join documents d on d.id = c.doc_id, q
where c.institution_id = %(institution_id)s
  and c.audience = any(%(audiences)s)
  and to_tsvector('english', c.content) @@ q.query
order by rank desc
limit %(limit)s
"""

TRIGRAM_SQL = """
select
    c.id,
    c.doc_id::text,
    c.content,
    c.page_no,
    c.section,
    c.lang,
    c.extraction_method::text,
    similarity(c.content, %(query)s) as sim,
    d.title
from chunks c
join documents d on d.id = c.doc_id
where c.institution_id = %(institution_id)s
  and c.audience = any(%(audiences)s)
  and c.content %% %(query)s
order by sim desc
limit %(limit)s
"""


def choose_backend(query: str, query_lang: str | None = None) -> LexicalPlan:
    """Pick the lexical backend for this query."""
    lang = query_lang or detect_lang(query)
    if lang == "bn":
        return LexicalPlan(
            backend="trigram_bn",
            reason="Bangla query; Postgres has no Bangla stemmer, so trigram",
        )
    if lang == "mixed":
        # Mixed queries usually carry the alphanumeric tokens that matter most
        # (course codes). Trigram matches those in either script.
        return LexicalPlan(backend="trigram_bn", reason="mixed-script query; trigram covers both")
    return LexicalPlan(backend="tsvector_en", reason="English query; stemmed tsvector")


def build_lexical_query(
    *,
    institution_id: str,
    role: Role | str,
    query: str,
    limit: int,
    query_lang: str | None = None,
) -> tuple[str, dict, LexicalPlan]:
    """Return (sql, params, plan). Query text is normalized through the same
    module ingestion used -- CLAUDE.md #6 symmetry applies to this arm too."""
    plan = choose_backend(query, query_lang)
    audiences = sorted(a.value for a in allowed_audiences(role))
    sql = TRIGRAM_SQL if plan.backend == "trigram_bn" else TSVECTOR_SQL
    params = {
        "institution_id": institution_id,
        "audiences": audiences,
        "query": normalize_for_match(query),
        "limit": limit,
    }
    return sql, params, plan


def search(
    conn,
    *,
    institution_id: str,
    role: Role | str,
    query: str,
    limit: int,
    query_lang: str | None = None,
) -> list[Candidate]:
    sql, params, plan = build_lexical_query(
        institution_id=institution_id,
        role=role,
        query=query,
        limit=limit,
        query_lang=query_lang,
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
            arm="lexical",
        )
        for row in rows
    ]
    logger.info(
        "lexical arm backend=%s (%s) returned=%d",
        plan.backend,
        plan.reason,
        len(results),
    )
    return results
