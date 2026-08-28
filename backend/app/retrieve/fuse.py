"""Reciprocal Rank Fusion. PRD 7.2 step 5.

RRF combines ranked lists using only RANK, never the raw scores:

    score(d) = sum over arms of  1 / (k + rank_arm(d))

That matters here more than usual. The dense arm returns cosine similarity
(roughly 0.4-0.9 in practice) and the lexical arm returns ts_rank or trigram
similarity (often 0.01-0.4). Those numbers are not comparable, and any attempt
to normalize them into a shared range bakes in an arbitrary weighting that
shifts with corpus and language. Ranks are comparable by construction.

k=60 is the value from the original RRF paper and the usual default. It damps
the influence of the top rank enough that a document appearing at rank 3 in both
arms beats one appearing at rank 1 in a single arm -- which is the whole point of
fusing, and matters especially for cross-lingual queries where the lexical arm
returns nothing at all.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from app.retrieve.dense import Candidate

logger = logging.getLogger(__name__)

RRF_K = 60


@dataclass
class FusedCandidate:
    """A candidate with its fused score and the per-arm ranks that produced it.

    The ranks are kept because Ablation A compares arms, and a fused score with
    no provenance cannot explain why one config beat another.
    """

    candidate: Candidate
    rrf_score: float
    ranks: dict[str, int] = field(default_factory=dict)

    @property
    def chunk_id(self) -> int:
        return self.candidate.chunk_id

    @property
    def content(self) -> str:
        return self.candidate.content

    @property
    def found_in_both(self) -> bool:
        return len(self.ranks) > 1


def reciprocal_rank_fusion(
    arms: dict[str, list[Candidate]],
    *,
    k: int = RRF_K,
    limit: int | None = None,
) -> list[FusedCandidate]:
    """Fuse ranked lists from named arms.

    `arms` maps an arm name to its ranked candidates, best first. An empty list
    is fine and contributes nothing -- which is exactly what happens to the
    lexical arm on a cross-lingual query.
    """
    scores: dict[int, float] = {}
    ranks: dict[int, dict[str, int]] = {}
    best: dict[int, Candidate] = {}

    for arm_name, candidates in arms.items():
        for position, candidate in enumerate(candidates, start=1):
            cid = candidate.chunk_id
            scores[cid] = scores.get(cid, 0.0) + 1.0 / (k + position)
            ranks.setdefault(cid, {})[arm_name] = position
            # Keep the first-seen full record; content is identical across arms.
            best.setdefault(cid, candidate)

    fused = [
        FusedCandidate(candidate=best[cid], rrf_score=score, ranks=ranks[cid])
        for cid, score in scores.items()
    ]
    # Ties broken by chunk_id so the ordering is deterministic -- an unstable
    # sort would make ablation runs irreproducible.
    fused.sort(key=lambda f: (-f.rrf_score, f.chunk_id))

    if limit is not None:
        fused = fused[:limit]

    both = sum(1 for f in fused if f.found_in_both)
    logger.info(
        "rrf fused arms=%s in=%s out=%d in_both_arms=%d",
        list(arms),
        {name: len(c) for name, c in arms.items()},
        len(fused),
        both,
    )
    return fused


def above_floor(
    fused: list[FusedCandidate], candidates_by_id: dict[int, Candidate], floor: float
) -> bool:
    """Whether any candidate clears the retrieval score floor.

    PRD 7.2 step 7 / CLAUDE.md #9: below RETRIEVAL_SCORE_FLOOR, return the
    not-found response WITHOUT calling the LLM. The floor is compared against
    the dense similarity, not the RRF score -- RRF scores are ~1/60 by
    construction and carry no absolute meaning, so thresholding them would be
    meaningless.
    """
    for item in fused:
        original = candidates_by_id.get(item.chunk_id)
        if original is not None and original.score >= floor:
            return True
    return False
