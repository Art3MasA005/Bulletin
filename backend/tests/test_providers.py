"""Provider-layer guarantees.

The privacy setting (CLAUDE.md #10) and the secret-handling behaviour are both
asserted here, because both are invisible when they break: a request without
data_collection deny looks identical to one with it, right up until the
provider trains on a student's routine.
"""

from __future__ import annotations

import json

import httpx
import pytest
from pydantic import BaseModel

from app.config import ConfigError, Settings
from app.providers.base import Message, ProviderError, ProviderUnsupported
from app.providers.openrouter import OpenRouterProvider

FAKE_KEY = "sk-or-v1-fake-key-for-tests-only"


def make_settings(**overrides) -> Settings:
    base = {
        "openrouter_api_key": FAKE_KEY,
        "vision_model": "test/vision",
        "generation_model": "test/gen",
        "extraction_model": "test/extract",
        "embedding_model": "test/embed",
        "embedding_dim": 4,
    }
    base.update(overrides)
    # `_env_file=None` so these settings never inherit the developer's own
    # .env. Without it the suite passes or fails depending on what happens to
    # be configured locally -- adding BULLETIN_GENERATION_MODEL_FALLBACKS to a
    # working .env broke two tests that had nothing to do with the change, and
    # would have broken them only on that one machine.
    return Settings(_env_file=None, **base)


class Capture:
    """Records every request body the provider sends."""

    def __init__(self, response: dict | None = None, status: int = 200):
        self.bodies: list[dict] = []
        self.response = response or {}
        self.status = status

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.bodies.append(json.loads(request.content))
        return httpx.Response(self.status, json=self.response)

    def client(self, settings: Settings) -> httpx.Client:
        return httpx.Client(
            transport=httpx.MockTransport(self.handler),
            base_url=settings.openrouter_base_url,
            headers={"Authorization": f"Bearer {settings.require('openrouter_api_key')}"},
        )


def completion(text: str) -> dict:
    return {"choices": [{"message": {"content": text}}]}


# ── CLAUDE.md #10: data_collection deny on EVERY request ────────────────────


def test_generate_sends_data_collection_deny() -> None:
    settings = make_settings()
    cap = Capture(completion("answer"))
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    list(provider.generate([Message(role="user", content="hi")]))
    assert cap.bodies[0]["provider"]["data_collection"] == "deny"


def test_vision_read_sends_data_collection_deny() -> None:
    """The most sensitive call in the product: a student's personal document."""
    settings = make_settings()
    cap = Capture(completion("page text"))
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    provider.read_page_image(b"\x89PNG-not-really")
    assert cap.bodies[0]["provider"]["data_collection"] == "deny"


def test_structured_extraction_sends_data_collection_deny() -> None:
    class Tiny(BaseModel):
        value: str

    settings = make_settings()
    cap = Capture(completion('{"value": "x"}'))
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    provider.extract_structured(b"png", Tiny, prompt="read it")
    assert cap.bodies[0]["provider"]["data_collection"] == "deny"


def test_embed_sends_data_collection_deny() -> None:
    settings = make_settings()
    cap = Capture({"data": [{"index": 0, "embedding": [0.1, 0.2, 0.3, 0.4]}]})
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    provider.embed(["hello"])
    assert cap.bodies[0]["provider"]["data_collection"] == "deny"


def test_deny_survives_an_explicit_provider_block() -> None:
    """A caller passing provider routing options must not drop the setting."""
    body = OpenRouterProvider._payload(model="m", provider={"order": ["x"]})
    assert body["provider"]["data_collection"] == "deny"
    assert body["provider"]["order"] == ["x"]


# ── secret handling ─────────────────────────────────────────────────────────


def test_api_key_is_not_printed_by_repr() -> None:
    """A plain str here leaks the key into every traceback and CI log."""
    settings = make_settings()
    assert FAKE_KEY not in repr(settings)
    assert FAKE_KEY not in str(settings)
    assert FAKE_KEY not in json.dumps(settings.model_dump(mode="json"), default=str)


def test_require_unwraps_the_secret_for_actual_use() -> None:
    assert make_settings().require("openrouter_api_key") == FAKE_KEY


def test_missing_key_names_the_env_var() -> None:
    settings = make_settings(openrouter_api_key="")
    with pytest.raises(ConfigError, match="BULLETIN_OPENROUTER_API_KEY"):
        settings.require("openrouter_api_key")


def test_missing_model_id_fails_fast_and_names_the_var() -> None:
    """Better than a stale default that 400s opaquely at request time."""
    settings = make_settings(vision_model="")
    provider = OpenRouterProvider(settings, client=Capture().client(settings))
    with pytest.raises(ConfigError, match="BULLETIN_VISION_MODEL"):
        provider.read_page_image(b"png")


# ── response handling ───────────────────────────────────────────────────────


def test_embedding_dimension_mismatch_is_loud() -> None:
    """CLAUDE.md: changing dimensions needs a migration and a re-index."""
    settings = make_settings(embedding_dim=1024)
    cap = Capture({"data": [{"index": 0, "embedding": [0.1, 0.2, 0.3, 0.4]}]})
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    with pytest.raises(ProviderError, match="migration"):
        provider.embed(["hello"])


def test_embeddings_keep_input_order() -> None:
    settings = make_settings()
    cap = Capture(
        {
            "data": [
                {"index": 1, "embedding": [1.0, 1.0, 1.0, 1.0]},
                {"index": 0, "embedding": [0.0, 0.0, 0.0, 0.0]},
            ]
        }
    )
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    assert provider.embed(["a", "b"])[0] == [0.0, 0.0, 0.0, 0.0]


def test_json_wrapped_in_code_fence_is_parsed() -> None:
    class Tiny(BaseModel):
        value: str

    settings = make_settings()
    cap = Capture(completion('```json\n{"value": "fenced"}\n```'))
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    assert provider.extract_structured(b"png", Tiny, prompt="p").value == "fenced"


def test_schema_violation_raises_rather_than_half_filling() -> None:
    """The confirmation UI depends on per-field confidence being real."""

    class Tiny(BaseModel):
        value: str

    settings = make_settings()
    cap = Capture(completion('{"wrong_field": 1}'))
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    with pytest.raises(ProviderError, match="did not match the schema"):
        provider.extract_structured(b"png", Tiny, prompt="p")


def test_rerank_is_unsupported_not_silently_wrong() -> None:
    """PRD 6 puts reranking on a local model; skipping must be a visible choice."""
    settings = make_settings()
    provider = OpenRouterProvider(settings, client=Capture().client(settings))
    with pytest.raises(ProviderUnsupported):
        provider.rerank("q", ["a", "b"])


def test_http_error_is_wrapped_with_retryability(monkeypatch) -> None:
    # Without this the test sleeps through the real backoff -- 14 seconds of a
    # 30-second suite spent waiting for a retry whose timing is not under test.
    monkeypatch.setattr("app.providers.openrouter.time.sleep", lambda _: None)
    settings = make_settings()
    cap = Capture({"error": "rate limited"}, status=429)
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    with pytest.raises(ProviderError) as exc:
        list(provider.generate([Message(role="user", content="hi")]))
    assert exc.value.retryable is True
    assert exc.value.status == 429


# ── streaming retries (the chat path) ───────────────────────────────────────


class StreamCapture:
    """Serves a scripted sequence of streaming responses, one per attempt."""

    def __init__(self, *responses: tuple[int, str]) -> None:
        self.responses = list(responses)
        self.attempts = 0

    def handler(self, request: httpx.Request) -> httpx.Response:
        status, body = self.responses[min(self.attempts, len(self.responses) - 1)]
        self.attempts += 1
        return httpx.Response(status, text=body)

    def client(self, settings: Settings) -> httpx.Client:
        return httpx.Client(
            transport=httpx.MockTransport(self.handler),
            base_url=settings.openrouter_base_url,
            headers={"Authorization": f"Bearer {settings.require('openrouter_api_key')}"},
        )


def sse(*texts: str) -> str:
    lines = [f'data: {{"choices":[{{"delta":{{"content":"{t}"}}}}]}}' for t in texts]
    return "\n".join(lines) + "\ndata: [DONE]\n"


def test_a_rate_limited_stream_is_retried_before_the_first_token(monkeypatch) -> None:
    """The failure that reached a user as "the answer could not be completed".

    `_post` has always retried a 429; the streaming path had no backoff at
    all, so one transient upstream limit killed the whole answer.
    """
    monkeypatch.setattr("app.providers.openrouter.time.sleep", lambda _: None)
    settings = make_settings(provider_max_retries=3)
    cap = StreamCapture((429, '{"error":"rate limited"}'), (200, sse("Exams ", "start ", "5 Sep")))
    provider = OpenRouterProvider(settings, client=cap.client(settings))

    out = "".join(provider.generate([Message(role="user", content="hi")], stream=True))

    assert out == "Exams start 5 Sep"
    assert cap.attempts == 2


class _BreakingStream(httpx.SyncByteStream):
    """A body that delivers some bytes and then loses the connection."""

    def __init__(self, chunks: list[bytes]) -> None:
        self.chunks = chunks

    def __iter__(self):
        yield from self.chunks
        raise httpx.ReadError("connection lost")


def test_a_stream_that_already_emitted_tokens_is_never_replayed(monkeypatch) -> None:
    """Retrying mid-answer would make the user watch it write itself twice.

    The break has to be a real transport failure, not a malformed `data:`
    line: malformed lines are skipped by design, so a test built on one would
    pass without ever reaching the guard it claims to check.
    """
    monkeypatch.setattr("app.providers.openrouter.time.sleep", lambda _: None)
    settings = make_settings(provider_max_retries=3)

    attempts = 0
    first_delta = b'data: {"choices":[{"delta":{"content":"Exams "}}]}\n'

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            return httpx.Response(200, stream=_BreakingStream([first_delta]))
        return httpx.Response(200, text=sse("restarted"))

    client = httpx.Client(
        transport=httpx.MockTransport(handler),
        base_url=settings.openrouter_base_url,
    )
    provider = OpenRouterProvider(settings, client=client)

    seen: list[str] = []
    with pytest.raises(ProviderError):
        for delta in provider.generate([Message(role="user", content="hi")], stream=True):
            seen.append(delta)

    assert seen == ["Exams "]
    assert attempts == 1  # the half-written answer was not restarted


def test_a_stream_gives_up_after_the_configured_attempts(monkeypatch) -> None:
    monkeypatch.setattr("app.providers.openrouter.time.sleep", lambda _: None)
    settings = make_settings(provider_max_retries=2)
    cap = StreamCapture((429, '{"error":"rate limited"}'))
    provider = OpenRouterProvider(settings, client=cap.client(settings))

    with pytest.raises(ProviderError) as exc:
        list(provider.generate([Message(role="user", content="hi")], stream=True))

    assert exc.value.status == 429
    assert cap.attempts == 2


def test_a_non_retryable_stream_error_is_not_retried(monkeypatch) -> None:
    """A 400 is a bad request; sending it again just wastes the user's time."""
    monkeypatch.setattr("app.providers.openrouter.time.sleep", lambda _: None)
    settings = make_settings(provider_max_retries=3)
    cap = StreamCapture((400, '{"error":"bad request"}'))
    provider = OpenRouterProvider(settings, client=cap.client(settings))

    with pytest.raises(ProviderError):
        list(provider.generate([Message(role="user", content="hi")], stream=True))

    assert cap.attempts == 1


# ── the model chain (a rate-limited model is unavailable, not slow) ─────────


def test_the_chain_always_starts_with_the_configured_model() -> None:
    """A bad fallback list may degrade an answer; it must never silently
    replace the model the evaluation numbers were measured on."""
    settings = make_settings(generation_model_fallbacks="b/second, c/third")
    assert settings.generation_chain == ["test/gen", "b/second", "c/third"]


def test_blank_and_duplicate_fallbacks_are_dropped() -> None:
    settings = make_settings(generation_model_fallbacks=" , test/gen , b/second , b/second ")
    assert settings.generation_chain == ["test/gen", "b/second"]


def test_no_fallbacks_configured_is_just_the_one_model() -> None:
    assert make_settings().generation_chain == ["test/gen"]


def test_a_rate_limited_model_falls_straight_through_to_the_next(monkeypatch) -> None:
    """The measured failure: `qwen/qwen3.8-flash` has exactly one provider, so
    a 429 there has nowhere to route and backoff only queues for the same full
    pool. The second model is the fix — and it must be tried with no sleep."""

    def no_sleep(_seconds: float) -> None:
        raise AssertionError("the chain must be exhausted before any backoff")

    monkeypatch.setattr("app.providers.openrouter.time.sleep", no_sleep)
    settings = make_settings(generation_model_fallbacks="b/second")

    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        seen.append(model)
        if model == "test/gen":
            return httpx.Response(429, json={"error": "rate limited"})
        return httpx.Response(200, text=sse("answered by the fallback"))

    client = httpx.Client(
        transport=httpx.MockTransport(handler), base_url=settings.openrouter_base_url
    )
    provider = OpenRouterProvider(settings, client=client)

    out = "".join(provider.generate([Message(role="user", content="hi")], stream=True))

    assert out == "answered by the fallback"
    assert seen == ["test/gen", "b/second"]


def test_the_backoff_only_starts_once_every_model_has_failed(monkeypatch) -> None:
    slept: list[float] = []
    monkeypatch.setattr("app.providers.openrouter.time.sleep", slept.append)
    settings = make_settings(generation_model_fallbacks="b/second", provider_max_retries=2)

    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(json.loads(request.content)["model"])
        return httpx.Response(429, json={"error": "rate limited"})

    client = httpx.Client(
        transport=httpx.MockTransport(handler), base_url=settings.openrouter_base_url
    )
    provider = OpenRouterProvider(settings, client=client)

    with pytest.raises(ProviderError):
        list(provider.generate([Message(role="user", content="hi")], stream=True))

    # Both models, then one sleep, then both models again.
    assert seen == ["test/gen", "b/second", "test/gen", "b/second"]
    assert len(slept) == 1


def test_the_non_streaming_path_uses_the_chain_too(monkeypatch) -> None:
    """condense() and translate_query() are non-streaming, and a failure there
    degrades retrieval silently rather than showing an error."""
    monkeypatch.setattr("app.providers.openrouter.time.sleep", lambda _: None)
    settings = make_settings(generation_model_fallbacks="b/second")

    def handler(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        if model == "test/gen":
            return httpx.Response(429, json={"error": "rate limited"})
        return httpx.Response(200, json=completion("fallback answer"))

    client = httpx.Client(
        transport=httpx.MockTransport(handler), base_url=settings.openrouter_base_url
    )
    provider = OpenRouterProvider(settings, client=client)

    assert "".join(provider.generate([Message(role="user", content="hi")])) == "fallback answer"


def test_every_model_in_the_chain_still_denies_data_collection() -> None:
    """CLAUDE.md #10 applies to the fallback as much as to the primary."""
    settings = make_settings(generation_model_fallbacks="b/second")
    cap = Capture(completion("ok"))
    provider = OpenRouterProvider(settings, client=cap.client(settings))

    list(provider.generate([Message(role="user", content="hi")]))

    assert all(b["provider"]["data_collection"] == "deny" for b in cap.bodies)
