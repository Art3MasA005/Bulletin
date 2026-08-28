"""The retrieval pipeline, PRD 7.2 steps 1-6, in one place.

    condense -> detect language -> normalize -> audience filter IN the query
      -> dense + lexical, 20 each -> RRF -> rerank 20 to 5

Step 7 (the score floor) and steps 8-9 (generation, streaming) live in
`generate/answer.py`, because the floor gate has to be structurally unable to
reach a provider and that guarantee belongs next to the code that would do the
calling.

Everything the ablations need is on the returned object: both arms' raw
results, the fused order with per-arm ranks, which rerank path ran, and the
dense score of every finalist. A pipeline that returns only the final five
cannot explain why a config won.
"""

from __future__ import annotations

import logging
from collections.abc import Sequence
from dataclasses import dataclass, field

from app.attachments.join import JoinOutcome, JoinPlan
from app.config import Settings, get_settings
from app.generate.condense import CondensedQuery, condense
from app.providers.base import Message, Provider, ProviderError
from app.retrieve import dense as dense_arm
from app.retrieve import lexical as lexical_arm
from app.retrieve.audience import Role
from app.retrieve.dense import Candidate
from app.retrieve.fuse import FusedCandidate, reciprocal_rank_fusion
from app.retrieve.rerank import RerankOutcome, rerank
from app.retrieve.translate_query import TranslatedQuery, translate

logger = logging.getLogger(__name__)


@dataclass
class RetrievalResult:
    """Everything one retrieval produced, including how it got there."""

    query: CondensedQuery
    dense: list[Candidate] = field(default_factory=list)
    lexical: list[Candidate] = field(default_factory=list)
    fused: list[FusedCandidate] = field(default_factory=list)
    finalists: list[Candidate] = field(default_factory=list)
    rerank_outcome: RerankOutcome | None = None
    errors: list[str] = field(default_factory=list)

    # Strategy B only (PRD §7.2). `strategy` is what actually ran, which is
    # not always what was asked for: a rejected translation falls back to A,
    # and an ablation that could not see that would credit B with A's numbers.
    strategy: str = "A"
    translation: TranslatedQuery | None = None
    dense_translated: list[Candidate] = field(default_factory=list)
    lexical_translated: list[Candidate] = field(default_factory=list)

    @property
    def dense_scores(self) -> dict[int, float]:
        """Dense similarity by chunk id -- what the score floor is compared against."""
        return {c.chunk_id: c.score for c in self.dense}

    def summary(self) -> str:
        path = self.rerank_outcome.path if self.rerank_outcome else "none"
        extra = ""
        if self.strategy == "B":
            translated = self.translation.lang if self.translation and self.translation.ok else "-"
            extra = (
                f" strategy=B->{translated} dense_t={len(self.dense_translated)} "
                f"lexical_t={len(self.lexical_translated)}"
            )
        return (
            f"lang={self.query.lang} dense={len(self.dense)} lexical={len(self.lexical)} "
            f"fused={len(self.fused)} finalists={len(self.finalists)} rerank={path}{extra}"
        )


def _embed_query(provider: Provider, text: str, settings: Settings) -> list[float] | None:
    """Embed the query, or return None so the lexical arm can carry the search.

    An embedding failure is not fatal: on a course-code query the lexical arm
    alone often answers correctly (PRD 8.2 step 5). Losing dense retrieval is
    worth reporting, not worth a 500.
    """
    try:
        vectors = provider.embed([text])
    except ProviderError as exc:
        logger.warning("query embedding failed, dense arm skipped: %s", exc)
        return None
    if not vectors:
        return None
    vector = vectors[0]
    if len(vector) != settings.embedding_dim:
        logger.error(
            "query embedding dim %d != BULLETIN_EMBEDDING_DIM %d; dense arm skipped",
            len(vector),
            settings.embedding_dim,
        )
        return None
    return vector


def _run_arms(
    conn,
    *,
    result: RetrievalResult,
    text: str,
    lang: str,
    institution_id: str,
    role: Role | str,
    provider: Provider,
    settings: Settings,
    label: str,
) -> tuple[list[Candidate], list[Candidate]]:
    """Run the dense and lexical arms for one query text.

    Either arm may come back empty and that is not an error: the lexical arm
    returning nothing on a cross-lingual query is the whole reason Strategy B
    exists. A *failing* arm is recorded on the result and the other one
    carries the search.
    """
    dense: list[Candidate] = []
    lexical: list[Candidate] = []

    vector = _embed_query(provider, text, settings)
    if vector is None:
        result.errors.append(f"{label}dense arm skipped: no query embedding")
    else:
        dense = dense_arm.search(
            conn,
            institution_id=institution_id,
            role=role,
            query_vector=vector,
            limit=settings.retrieve_top_k,
        )

    try:
        lexical = lexical_arm.search(
            conn,
            institution_id=institution_id,
            role=role,
            query=text,
            limit=settings.retrieve_top_k,
            query_lang=lang,
        )
    except Exception as exc:  # noqa: BLE001 -- one arm failing must not lose the other
        logger.warning("%slexical arm failed: %s", label, exc)
        result.errors.append(f"{label}lexical arm failed: {exc}")
        conn.rollback()

    return dense, lexical


def retrieve(
    conn,
    *,
    question: str,
    institution_id: str,
    role: Role | str,
    provider: Provider,
    history: Sequence[Message] | None = None,
    settings: Settings | None = None,
    rerank_provider: Provider | None = None,
    strategy: str | None = None,
) -> RetrievalResult:
    """Run the hybrid retrieval pipeline for one question.

    The audience predicate is inside both arms' SQL (CLAUDE.md #4); this
    function never filters a result list.
    """
    settings = settings or get_settings()
    strategy = (strategy or settings.cross_lingual_strategy).upper()
    query = condense(question, history, provider=provider)
    result = RetrievalResult(query=query, strategy="A")

    result.dense, result.lexical = _run_arms(
        conn,
        result=result,
        text=query.text,
        lang=query.lang,
        institution_id=institution_id,
        role=role,
        provider=provider,
        settings=settings,
        label="",
    )

    arms: dict[str, list[Candidate]] = {"dense": result.dense, "lexical": result.lexical}

    if strategy == "B":
        # PRD §7.2 Strategy B. The translation is validated before it is used;
        # a rejected one leaves `strategy` at "A", which is what actually ran.
        variant = translate(query.text, provider=provider, source_lang=query.lang)
        result.translation = variant
        if variant.ok:
            result.strategy = "B"
            result.dense_translated, result.lexical_translated = _run_arms(
                conn,
                result=result,
                text=variant.text,
                lang=variant.lang,
                institution_id=institution_id,
                role=role,
                provider=provider,
                settings=settings,
                label="translated ",
            )
            arms["dense_translated"] = result.dense_translated
            arms["lexical_translated"] = result.lexical_translated
        else:
            result.errors.append(f"strategy B fell back to A: {variant.reason}")

    result.fused = reciprocal_rank_fusion(arms)
    outcome = rerank(result.fused, query=query.text, provider=rerank_provider, settings=settings)
    result.rerank_outcome = outcome
    result.finalists = outcome.candidates

    logger.info("retrieval %s", result.summary())
    return result


def retrieve_for_join(
    conn,
    *,
    plan: JoinPlan,
    institution_id: str,
    role: Role | str,
    provider: Provider,
    settings: Settings | None = None,
    rerank_provider: Provider | None = None,
) -> tuple[JoinOutcome, dict[str, RetrievalResult]]:
    """One retrieval per confirmed course code. PRD 8.2 step 5.

    Returns the JoinOutcome the generator needs (including the codes that
    found nothing) and the per-code retrieval detail for eval and debugging.
    """
    from app.attachments.join import collect

    settings = settings or get_settings()
    per_code: dict[str, RetrievalResult] = {}
    hits: dict[str, list[Candidate]] = {}

    for join_query in plan.queries:
        result = retrieve(
            conn,
            question=join_query.text,
            institution_id=institution_id,
            role=role,
            provider=provider,
            settings=settings,
            rerank_provider=rerank_provider,
        )
        per_code[join_query.code] = result
        hits[join_query.code] = result.finalists

    outcome = collect(plan, hits)
    logger.info(
        "join retrieval attachment_id=%s answered=%d missing=%d",
        plan.attachment_id,
        len(outcome.answered_codes),
        len(outcome.missing_codes),
    )
    return outcome, per_code
