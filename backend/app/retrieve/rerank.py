"""Rerank 20 -> 5. PRD 7.2 step 6.

PRD 6 lists reranking as the one capability whose fallback is "skip and measure
the cost". That is not a licence to ignore it -- it is an instruction to make
the skip explicit and countable, which is what RerankOutcome is for. Every
result records which path ran, so an ablation table can state what reranking
was worth on this corpus instead of assuming it helped.

Order of preference:

  1. A provider that implements `rerank` (a local cross-encoder;
     bge-reranker-v2-m3 per PRD 6 -- OpenRouter has no rerank endpoint).
  2. Skip: keep the fused RRF order and truncate.

A provider failure is a skip, never an error surfaced to the user. A ranked
list from RRF is a perfectly serviceable answer; a 500 because a reranker was
briefly unavailable is not.
"""

from __future__ import annotations

import logging
from collections.abc import Sequence
from dataclasses import dataclass

from app.config import Settings, get_settings
from app.providers.base import Provider, ProviderError
from app.retrieve.dense import Candidate
from app.retrieve.fuse import FusedCandidate

logger = logging.getLogger(__name__)


@dataclass
class RerankOutcome:
    """The reranked finalists and how they were chosen.

    `path` is one of "cross_encoder" or "skipped". `reason` explains a skip in
    words that belong in an ablation report, not in a stack trace.
    """

    candidates: list[Candidate]
    path: str
    reason: str
    scores: list[float] | None = None

    @property
    def reranked(self) -> bool:
        return self.path == "cross_encoder"


def _fused_order(fused: Sequence[FusedCandidate], limit: int) -> list[Candidate]:
    return [item.candidate for item in fused[:limit]]


def rerank(
    fused: Sequence[FusedCandidate],
    *,
    query: str,
    provider: Provider | None = None,
    settings: Settings | None = None,
    top_k: int | None = None,
) -> RerankOutcome:
    """Cut the fused candidate list down to the finalists the answer cites.

    With no provider -- the measured-skip configuration -- this is a truncation
    of the RRF order, which is exactly what the ablation compares against.
    """
    settings = settings or get_settings()
    limit = top_k if top_k is not None else settings.rerank_top_k

    if not fused:
        return RerankOutcome(candidates=[], path="skipped", reason="nothing to rerank")

    if provider is None:
        return RerankOutcome(
            candidates=_fused_order(fused, limit),
            path="skipped",
            reason="no rerank provider configured (PRD 6: skip and measure)",
        )

    docs = [item.candidate.content for item in fused]
    try:
        scores = provider.rerank(query, docs)
    except ProviderError as exc:
        # Includes ProviderUnsupported, which is the expected outcome on
        # OpenRouter and is not a bug.
        logger.info("rerank skipped: %s", exc)
        return RerankOutcome(
            candidates=_fused_order(fused, limit),
            path="skipped",
            reason=f"provider skip: {exc}",
        )

    if len(scores) != len(docs):
        # A misaligned score list would silently reorder the answer's sources
        # against the wrong documents. Refuse it rather than trust it.
        logger.warning("rerank returned %d scores for %d docs; skipping", len(scores), len(docs))
        return RerankOutcome(
            candidates=_fused_order(fused, limit),
            path="skipped",
            reason=f"score/doc mismatch: {len(scores)} vs {len(docs)}",
        )

    # Ties broken by chunk_id so ablation runs reproduce exactly.
    ordered = sorted(
        zip(scores, fused, strict=True),
        key=lambda pair: (-pair[0], pair[1].chunk_id),
    )[:limit]

    logger.info(
        "reranked in=%d out=%d top=%.4f", len(docs), len(ordered), ordered[0][0] if ordered else 0.0
    )
    return RerankOutcome(
        candidates=[item.candidate for _, item in ordered],
        path="cross_encoder",
        reason=f"{provider.name} cross-encoder",
        scores=[score for score, _ in ordered],
    )
