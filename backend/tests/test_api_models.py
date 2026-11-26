"""The model picker: an allow-list on the server, a key from the client.

The client never names an OpenRouter model. It sends a key from GET /models;
the server maps it to a model id. Anything else would let a signed-in user run
any model on the institution's bill.
"""

from __future__ import annotations

from collections.abc import Iterator, Sequence

import pytest
from fastapi.testclient import TestClient

from app.api.deps import settings_dep
from app.config import ModelChoice, UnknownModel, get_settings
from app.main import create_app
from app.providers.base import Message
from tests.test_api import (
    FakePool,
    StubProvider,
    _secret,
    make_token,
    profile_rows,
    sse_events,
)

CHOICES = [
    ModelChoice(key="gemma", id="google/gemma-default", name="Gemma 4", maker="Google"),
    ModelChoice(key="haiku", id="anthropic/haiku-test", name="Claude Haiku", maker="Anthropic"),
]


class RecordingProvider(StubProvider):
    """Remembers which chain each generation was asked to use."""

    def __init__(self) -> None:
        super().__init__()
        self.chains: list[list[str] | None] = []

    def generate(
        self,
        messages: Sequence[Message],
        *,
        stream: bool = False,
        models: Sequence[str] | None = None,
    ) -> Iterator[str]:
        self.chains.append(list(models) if models is not None else None)
        yield from super().generate(messages, stream=stream)


def settings_with(choices: list[ModelChoice]):
    return get_settings().model_copy(
        update={
            "supabase_jwt_secret": _secret(),
            "generation_model": "google/gemma-default",
            "generation_model_fallbacks": "qwen/fallback",
            "generation_model_choices": choices,
        }
    )


@pytest.fixture
def build():
    def make(*, choices: list[ModelChoice] = CHOICES, provider=None) -> TestClient:
        app = create_app()
        settings = settings_with(choices)
        app.dependency_overrides[settings_dep] = lambda: settings
        app.state.pool = FakePool(profile_rows())
        app.state.pool_error = None
        app.state.provider = provider or StubProvider()
        return TestClient(app)

    return make


def auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {make_token()}"}


# ── the chain ───────────────────────────────────────────────────────────────


def test_a_pick_goes_first_and_the_usual_chain_stays_behind_it() -> None:
    s = settings_with(CHOICES)
    assert s.chain_for("haiku") == [
        "anthropic/haiku-test",
        "google/gemma-default",
        "qwen/fallback",
    ]


def test_picking_the_default_does_not_try_it_twice() -> None:
    assert settings_with(CHOICES).chain_for("gemma") == ["google/gemma-default", "qwen/fallback"]


def test_no_pick_is_the_default_chain() -> None:
    assert settings_with(CHOICES).chain_for(None) == ["google/gemma-default", "qwen/fallback"]


def test_a_key_off_the_list_is_refused_not_quietly_defaulted() -> None:
    with pytest.raises(UnknownModel):
        settings_with(CHOICES).chain_for("gpt-99")


# ── GET /models ─────────────────────────────────────────────────────────────


def test_models_lists_keys_and_names_but_never_model_ids(build) -> None:
    response = build().get("/models", headers=auth())
    assert response.status_code == 200
    models = response.json()["models"]
    assert [m["key"] for m in models] == ["gemma", "haiku"]
    assert models[0]["default"] is True and models[1]["default"] is False
    assert "anthropic/haiku-test" not in response.text


def test_models_needs_a_signed_in_caller(build) -> None:
    assert build().get("/models").status_code == 401


def test_no_choices_configured_means_an_empty_list(build) -> None:
    assert build(choices=[]).get("/models", headers=auth()).json() == {"models": []}


# ── POST /chat with a pick ──────────────────────────────────────────────────


def test_the_picked_model_answers(build) -> None:
    provider = RecordingProvider()
    response = build(provider=provider).post(
        "/chat",
        json={"question": "when do the final examinations start", "model": "haiku"},
        headers=auth(),
    )
    assert response.status_code == 200
    assert dict(sse_events(response.text))["done"]["status"] == "answered"
    assert provider.chains == [["anthropic/haiku-test", "google/gemma-default", "qwen/fallback"]]


def test_without_a_pick_the_default_chain_answers(build) -> None:
    provider = RecordingProvider()
    build(provider=provider).post(
        "/chat",
        json={"question": "when do the final examinations start"},
        headers=auth(),
    )
    assert provider.chains == [None]


def test_an_unknown_model_key_is_refused_before_any_work(build) -> None:
    provider = RecordingProvider()
    response = build(provider=provider).post(
        "/chat",
        json={"question": "when do the final examinations start", "model": "openai/gpt-9"},
        headers=auth(),
    )
    assert response.status_code == 422
    assert provider.chains == []
