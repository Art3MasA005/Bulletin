"""Retrieval arms and fusion.

The live-database assertions belong to Phase 4 against a seeded corpus. What is
testable now -- and is where the correctness boundary actually lives -- is that
the audience predicate is IN the generated SQL, and that fusion is rank-based
and deterministic.
"""

from __future__ import annotations

import pytest

from app.bangla.normalize import normalize_for_match
from app.retrieve.audience import Role
from app.retrieve.dense import Candidate, build_dense_query
from app.retrieve.fuse import RRF_K, above_floor, reciprocal_rank_fusion
from app.retrieve.lexical import build_lexical_query, choose_backend


def candidate(cid: int, score: float = 0.5, arm: str = "dense") -> Candidate:
    return Candidate(
        chunk_id=cid,
        doc_id=f"doc-{cid}",
        content=f"content {cid}",
        page_no=1,
        section=None,
        lang="en",
        extraction_method="native_text",
        score=score,
        arm=arm,
    )


# ── CLAUDE.md #4: the filter is IN the query ────────────────────────────────


def test_dense_query_filters_audience_in_the_where_clause() -> None:
    sql, params = build_dense_query(
        institution_id="inst-1", role=Role.STUDENT, query_vector=[0.1] * 4, limit=20
    )
    where = sql[sql.index("where") : sql.index("order by")]
    assert "audience = any(%(audiences)s)" in where
    assert "institution_id" in where
    assert params["audiences"] == ["all", "students"]


def test_dense_query_orders_after_filtering_not_before() -> None:
    """The LIMIT must apply to already-filtered rows, or it is post-filtering."""
    sql, _ = build_dense_query(
        institution_id="i", role=Role.STUDENT, query_vector=[0.1] * 4, limit=20
    )
    assert sql.index("where") < sql.index("order by") < sql.index("limit")


def test_dense_query_excludes_teacher_audiences_for_a_student() -> None:
    _, params = build_dense_query(
        institution_id="i", role=Role.STUDENT, query_vector=[0.1] * 4, limit=20
    )
    assert "teachers" not in params["audiences"]
    assert "admin_only" not in params["audiences"]


def test_teacher_gets_a_wider_audience_set() -> None:
    _, params = build_dense_query(
        institution_id="i", role=Role.TEACHER, query_vector=[0.1] * 4, limit=20
    )
    assert params["audiences"] == ["all", "students", "teachers"]


def test_lexical_query_also_filters_audience() -> None:
    """Both arms filter. An unfiltered second arm would reopen the leak."""
    for role, expected in (
        (Role.STUDENT, ["all", "students"]),
        # sorted(): "admin_only" precedes "all" because 'd' < 'l'.
        (Role.ADMIN, ["admin_only", "all", "students", "teachers"]),
    ):
        sql, params, _ = build_lexical_query(
            institution_id="i", role=role, query="exam date", limit=20
        )
        assert "audience = any(%(audiences)s)" in sql
        assert params["audiences"] == expected


def test_no_query_interpolates_values_into_sql() -> None:
    """Parameterised throughout -- values reach the driver, not the SQL text."""
    sql, params = build_dense_query(
        institution_id="inst-secret", role=Role.STUDENT, query_vector=[0.1] * 4, limit=20
    )
    assert "inst-secret" not in sql
    lex_sql, lex_params, _ = build_lexical_query(
        institution_id="inst-secret", role=Role.STUDENT, query="drop table", limit=20
    )
    assert "inst-secret" not in lex_sql
    assert "drop table" not in lex_sql


# ── lexical backend selection ───────────────────────────────────────────────


def test_english_query_uses_stemmed_tsvector() -> None:
    assert choose_backend("When do final exams start?").backend == "tsvector_en"


def test_bangla_query_uses_trigram() -> None:
    """Postgres ships no Bangla stemmer; tsvector would not stem at all."""
    plan = choose_backend("পরীক্ষা কবে শুরু হবে")
    assert plan.backend == "trigram_bn"
    assert "stemmer" in plan.reason


def test_mixed_script_query_uses_trigram() -> None:
    assert choose_backend("CSE 4101 পরীক্ষা কবে").backend == "trigram_bn"


def test_lexical_query_is_normalized_like_ingestion() -> None:
    """CLAUDE.md #6 symmetry applies to the lexical arm too."""
    _, params, _ = build_lexical_query(
        institution_id="i", role=Role.STUDENT, query="২০২৬ CSE-4101", limit=20
    )
    assert "2026" in params["query"], "Bangla digits must fold for matching"
    assert "cse 4101" in params["query"]


# ── RRF ─────────────────────────────────────────────────────────────────────


def test_rrf_uses_rank_not_raw_score() -> None:
    """Dense cosine (~0.9) and trigram sim (~0.05) are not comparable numbers.

    Here the lexical arm's raw scores are tiny, but its rank-1 document must
    still win against a dense rank-3 document with a huge raw score.
    """
    dense = [candidate(1, 0.95), candidate(2, 0.94), candidate(3, 0.93)]
    lexical = [candidate(3, 0.02, "lexical"), candidate(9, 0.01, "lexical")]
    fused = reciprocal_rank_fusion({"dense": dense, "lexical": lexical})
    # Chunk 3 is rank 3 in dense and rank 1 in lexical -> appears in both.
    assert fused[0].chunk_id == 3
    assert fused[0].found_in_both


def test_agreement_across_arms_beats_a_single_strong_arm() -> None:
    dense = [candidate(1), candidate(2)]
    lexical = [candidate(2, arm="lexical"), candidate(3, arm="lexical")]
    fused = reciprocal_rank_fusion({"dense": dense, "lexical": lexical})
    assert fused[0].chunk_id == 2, "found by both arms must outrank rank-1-in-one"


def test_rrf_score_formula() -> None:
    fused = reciprocal_rank_fusion({"dense": [candidate(1)]})
    assert fused[0].rrf_score == pytest.approx(1.0 / (RRF_K + 1))


def test_empty_lexical_arm_is_harmless() -> None:
    """The cross-lingual case: lexical returns nothing, dense carries the query."""
    dense = [candidate(1), candidate(2)]
    fused = reciprocal_rank_fusion({"dense": dense, "lexical": []})
    assert [f.chunk_id for f in fused] == [1, 2]
    assert not fused[0].found_in_both


def test_all_arms_empty_produces_no_candidates() -> None:
    assert reciprocal_rank_fusion({"dense": [], "lexical": []}) == []


def test_ranks_are_retained_for_ablation_reporting() -> None:
    fused = reciprocal_rank_fusion(
        {"dense": [candidate(5), candidate(7)], "lexical": [candidate(7, arm="lexical")]}
    )
    by_id = {f.chunk_id: f for f in fused}
    assert by_id[7].ranks == {"dense": 2, "lexical": 1}
    assert by_id[5].ranks == {"dense": 1}


def test_ordering_is_deterministic_on_ties() -> None:
    """Irreproducible ordering would make ablation runs non-comparable."""
    a = reciprocal_rank_fusion({"x": [candidate(3)], "y": [candidate(1)]})
    b = reciprocal_rank_fusion({"y": [candidate(1)], "x": [candidate(3)]})
    assert [f.chunk_id for f in a] == [f.chunk_id for f in b] == [1, 3]


def test_limit_truncates_after_fusion() -> None:
    dense = [candidate(i) for i in range(1, 11)]
    assert len(reciprocal_rank_fusion({"dense": dense}, limit=5)) == 5


# ── the score floor (CLAUDE.md #9) ──────────────────────────────────────────


def test_score_floor_uses_dense_similarity_not_the_rrf_score() -> None:
    """RRF scores are ~1/60 by construction; thresholding them is meaningless."""
    weak = [candidate(1, 0.10), candidate(2, 0.08)]
    fused = reciprocal_rank_fusion({"dense": weak})
    by_id = {c.chunk_id: c for c in weak}
    assert not above_floor(fused, by_id, floor=0.35)


def test_a_strong_hit_clears_the_floor() -> None:
    strong = [candidate(1, 0.82)]
    fused = reciprocal_rank_fusion({"dense": strong})
    assert above_floor(fused, {1: strong[0]}, floor=0.35)


def test_no_candidates_never_clears_the_floor() -> None:
    assert not above_floor([], {}, floor=0.35)


# ── the lexical arm must not AND every content word ────────────────────────


def test_english_lexical_query_uses_or_semantics() -> None:
    """AND across content words silently empties the arm on real questions.

    Measured on the real corpus: "when do the final examinations start" becomes
    'final' & 'examin' & 'start' under websearch_to_tsquery and matched nothing,
    while the same query with OR matched 45 chunks. An arm returning nothing
    cannot be rescued by RRF, the reranker, or the score floor downstream.
    """
    sql, _, plan = build_lexical_query(
        institution_id="inst-1", role=Role.STUDENT, query="when do final exams start", limit=20
    )
    assert plan.backend == "tsvector_en"
    assert "websearch_to_tsquery" not in sql, "websearch_to_tsquery ANDs every term"
    assert "plainto_tsquery" not in sql, "plainto_tsquery ANDs every term too"
    assert "' | '" in sql, "lexemes must be joined with OR"


def test_lexical_query_never_interpolates_user_text_into_to_tsquery() -> None:
    """The OR expression is built from lexemes, quoted, inside SQL -- not in Python."""
    sql, params, _ = build_lexical_query(
        institution_id="inst-1", role=Role.STUDENT, query="drop table chunks", limit=20
    )
    assert "quote_literal" in sql
    assert params["query"] == normalize_for_match("drop table chunks")


def test_an_empty_query_yields_no_rows_rather_than_an_error() -> None:
    """to_tsquery('') raises; NULL simply matches nothing."""
    sql, _, _ = build_lexical_query(institution_id="inst-1", role=Role.STUDENT, query="", limit=20)
    assert "nullif(" in sql
