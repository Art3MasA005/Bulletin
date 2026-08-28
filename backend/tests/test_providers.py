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
    return Settings(**base)


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


def test_http_error_is_wrapped_with_retryability() -> None:
    settings = make_settings()
    cap = Capture({"error": "rate limited"}, status=429)
    provider = OpenRouterProvider(settings, client=cap.client(settings))
    with pytest.raises(ProviderError) as exc:
        list(provider.generate([Message(role="user", content="hi")]))
    assert exc.value.retryable is True
    assert exc.value.status == 429
