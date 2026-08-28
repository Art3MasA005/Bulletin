"""Reranking, and the measured skip. PRD 6, PRD 7.2 step 6."""

from __future__ import annotations

from collections.abc import Iterator, Sequence

from app.config import get_settings
from app.providers.base import Message, Provider, ProviderError, ProviderUnsupported, Vector
from app.retrieve.dense import Candidate
from app.retrieve.fuse import reciprocal_rank_fusion
from app.retrieve.rerank import rerank


class _Reranker(Provider):
    name = "stub-reranker"

    def __init__(self, scores: list[float] | None = None, *, error: Exception | None = None):
        self.scores = scores
        self.error = error
        self.calls = 0

    def rerank(self, query: str, docs: Sequence[str]) -> list[float]:
        self.calls += 1
        if self.error is not None:
            raise self.error
        assert self.scores is not None
        return self.scores

    def embed(self, texts: Sequence[str]) -> list[Vector]:  # pragma: no cover
        raise ProviderUnsupported("embed")

    def generate(  # pragma: no cover
        self, messages: Sequence[Message], *, stream: bool = False
    ) -> Iterator[str]:
        raise ProviderUnsupported("generate")

    def read_page_image(self, png_bytes: bytes, *, lang_hint: str = "auto") -> str:
        raise ProviderUnsupported("vision")  # pragma: no cover

    def extract_structured(self, png_bytes: bytes, schema, *, prompt: str):
        raise ProviderUnsupported("structured")  # pragma: no cover


def _candidate(chunk_id: int, score: float = 0.5, arm: str = "dense") -> Candidate:
    return Candidate(
        chunk_id=chunk_id,
        doc_id="doc-1",
        content=f"chunk {chunk_id}",
        page_no=1,
        section=None,
        lang="en",
        extraction_method="native_text",
        score=score,
        arm=arm,
    )


def _fused(n: int):
    arm = [_candidate(i) for i in range(1, n + 1)]
    return reciprocal_rank_fusion({"dense": arm})


def test_no_provider_truncates_the_fused_order_and_says_so() -> None:
    """PRD 6's fallback is "skip and measure the cost" -- so the skip is named."""
    outcome = rerank(_fused(8), query="exam date", top_k=5)
    assert [c.chunk_id for c in outcome.candidates] == [1, 2, 3, 4, 5]
    assert not outcome.reranked
    assert "skip and measure" in outcome.reason


def test_a_provider_without_rerank_is_a_skip_not_an_error() -> None:
    """OpenRouter has no rerank endpoint. That is the expected path, not a bug."""
    provider = _Reranker(error=ProviderUnsupported("no rerank endpoint"))
    outcome = rerank(_fused(6), query="exam date", provider=provider, top_k=3)
    assert outcome.path == "skipped"
    assert [c.chunk_id for c in outcome.candidates] == [1, 2, 3]


def test_a_provider_failure_degrades_instead_of_500ing() -> None:
    provider = _Reranker(error=ProviderError("upstream 502", status=502, retryable=True))
    outcome = rerank(_fused(6), query="exam date", provider=provider, top_k=3)
    assert outcome.path == "skipped"
    assert len(outcome.candidates) == 3


def test_cross_encoder_reorders() -> None:
    provider = _Reranker(scores=[0.1, 0.9, 0.5, 0.2])
    outcome = rerank(_fused(4), query="exam date", provider=provider, top_k=3)
    assert [c.chunk_id for c in outcome.candidates] == [2, 3, 4]
    assert outcome.reranked
    assert outcome.scores == [0.9, 0.5, 0.2]


def test_a_misaligned_score_list_is_refused_not_trusted() -> None:
    """Fewer scores than docs would attach rankings to the wrong sources."""
    provider = _Reranker(scores=[0.9, 0.1])
    outcome = rerank(_fused(4), query="exam date", provider=provider, top_k=4)
    assert outcome.path == "skipped"
    assert "mismatch" in outcome.reason
    assert [c.chunk_id for c in outcome.candidates] == [1, 2, 3, 4]


def test_ties_are_broken_deterministically() -> None:
    """An unstable order makes ablation runs irreproducible."""
    provider = _Reranker(scores=[0.5, 0.5, 0.5, 0.5])
    first = rerank(_fused(4), query="q", provider=provider, top_k=2)
    second = rerank(_fused(4), query="q", provider=provider, top_k=2)
    assert (
        [c.chunk_id for c in first.candidates] == [c.chunk_id for c in second.candidates] == [1, 2]
    )


def test_empty_input_does_not_call_the_provider() -> None:
    provider = _Reranker(scores=[])
    outcome = rerank([], query="q", provider=provider)
    assert outcome.candidates == []
    assert provider.calls == 0


def test_default_top_k_comes_from_settings() -> None:
    outcome = rerank(_fused(30), query="q")
    assert len(outcome.candidates) == get_settings().rerank_top_k
