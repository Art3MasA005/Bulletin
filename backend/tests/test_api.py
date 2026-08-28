"""The HTTP surface: authentication, the SSE contract, and the join guard.

Two of the three non-negotiable CLAUDE.md rules reach the API here:

  * #3 -- a join answer cannot be generated from an unconfirmed attachment,
    now at the endpoint rather than only at the type.
  * #9 -- below the score floor, the not-found response is streamed WITHOUT
    calling the LLM. Asserted with a provider that raises on contact.

Nothing here talks to Supabase or OpenRouter: the pool and the provider are
fakes on `app.state`, which is exactly how the real app holds them.
"""

from __future__ import annotations

import json
from collections.abc import Iterator, Sequence
from contextlib import contextmanager

import jwt
import pytest
from fastapi.testclient import TestClient

from app.api.deps import settings_dep
from app.config import get_settings
from app.main import create_app
from app.providers.base import Message, Provider, ProviderError, ProviderUnsupported, Vector

# 32+ bytes: PyJWT warns below the RFC 7518 minimum for HS256.
JWT_SECRET = "test-secret-not-a-real-one-0123456789"
USER_ID = "11111111-1111-1111-1111-111111111111"
INSTITUTION_ID = "22222222-2222-2222-2222-222222222222"


def make_token(
    *, sub: str = USER_ID, expired: bool = False, audience: str = "authenticated"
) -> str:
    import time

    now = int(time.time())
    payload = {
        "sub": sub,
        "aud": audience,
        "exp": now - 60 if expired else now + 3600,
        "iat": now - 10,
        # Deliberately a lie: the role in the token must never be trusted.
        "user_metadata": {"role": "admin"},
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


# ── fakes ───────────────────────────────────────────────────────────────────


class FakeCursor:
    """Returns canned rows keyed by the shape of the SQL."""

    def __init__(self, rows: dict[str, object]):
        self._rows = rows
        self._result: object = None

    def execute(self, sql: str, params: dict | None = None) -> None:
        text = " ".join(sql.split())
        if "from profiles" in text:
            self._result = self._rows.get("profile")
        elif "from messages m" in text and "count(*)" in text:
            self._result = (self._rows.get("questions_today", 0),)
        elif text.startswith("select id::text from conversations"):
            self._result = self._rows.get("conversation")
        elif text.startswith("insert into conversations"):
            self._rows["created_conversation"] = params
            self._result = ("conv-1",)
        elif text.startswith("insert into messages"):
            self._rows.setdefault("messages", []).append(params)
            self._result = ("msg-1",)
        elif text.startswith("update attachments set message_id"):
            self._result = None
        elif "from attachments" in text:
            self._result = self._rows.get("attachment")
        elif "from chunks" in text:
            self._result = self._rows.get("chunks", [])
        else:
            self._result = None

    def fetchone(self):
        result = self._result
        return result[0] if isinstance(result, list) and result else result

    def fetchall(self):
        return self._result if isinstance(self._result, list) else []

    def __enter__(self):
        return self

    def __exit__(self, *exc: object) -> None:
        return None


class FakeConn:
    def __init__(self, rows: dict[str, object]):
        self.rows = rows

    def cursor(self):
        return FakeCursor(self.rows)

    def rollback(self) -> None:
        return None

    def commit(self) -> None:
        return None


class FakePool:
    def __init__(self, rows: dict[str, object]):
        self.rows = rows

    @contextmanager
    def connection(self):
        yield FakeConn(self.rows)

    def close(self) -> None:
        return None


class StubProvider(Provider):
    """Embeds and generates without a network."""

    name = "stub"

    def __init__(self, reply: str = "Final exams start 05 September 2026 [1]."):
        self.reply = reply
        self.generate_calls = 0

    def embed(self, texts: Sequence[str]) -> list[Vector]:
        dim = get_settings().embedding_dim
        return [[0.01] * dim for _ in texts]

    def rerank(self, query: str, docs: Sequence[str]) -> list[float]:
        raise ProviderUnsupported("rerank")

    def generate(self, messages: Sequence[Message], *, stream: bool = False) -> Iterator[str]:
        self.generate_calls += 1
        yield self.reply

    def read_page_image(self, png_bytes: bytes, *, lang_hint: str = "auto") -> str:
        raise ProviderUnsupported("vision")

    def extract_structured(self, png_bytes: bytes, schema, *, prompt: str):
        raise ProviderUnsupported("structured")


class ExplodingProvider(StubProvider):
    """Any generation call is a test failure (CLAUDE.md #9)."""

    def generate(self, messages: Sequence[Message], *, stream: bool = False) -> Iterator[str]:
        raise AssertionError("the LLM was called below the retrieval score floor")


def chunk_row(chunk_id: int, content: str, score: float) -> tuple:
    """A row shaped like the dense/lexical arms' SELECT."""
    return (chunk_id, "doc-1", content, 3, None, "en", "native_text", score)


@pytest.fixture
def client_factory():
    settings = get_settings().model_copy(update={"supabase_jwt_secret": _secret()})

    def build(*, rows: dict[str, object], provider: Provider | None = None) -> TestClient:
        app = create_app()
        app.dependency_overrides[settings_dep] = lambda: settings
        # The lifespan is deliberately NOT run: it opens a real connection pool
        # to Supabase, which would put a network call and a live database into
        # every unit test (and exhaust the pooler when the suite runs beside an
        # eval). The state it would build is supplied here instead.
        app.state.pool = FakePool(rows)
        app.state.pool_error = None
        app.state.provider = provider or StubProvider()
        return TestClient(app)

    return build


def _secret():
    from pydantic import SecretStr

    return SecretStr(JWT_SECRET)


def profile_rows(role: str = "student", **extra) -> dict[str, object]:
    rows: dict[str, object] = {
        "profile": (USER_ID, INSTITUTION_ID, role, "student@green.edu.bd"),
        "chunks": [
            chunk_row(1, "Final Examinations of Summer 2026 will be held from 05 September.", 0.72)
        ],
    }
    rows.update(extra)
    return rows


def sse_events(text: str) -> list[tuple[str, dict]]:
    """Parse an SSE body into (event, payload) pairs."""
    events = []
    for block in text.strip().split("\n\n"):
        name, payload = None, None
        for line in block.splitlines():
            if line.startswith("event: "):
                name = line[len("event: ") :]
            elif line.startswith("data: "):
                payload = json.loads(line[len("data: ") :])
        if name:
            events.append((name, payload or {}))
    return events


# ── health ──────────────────────────────────────────────────────────────────


def test_health_reports_dependencies(client_factory) -> None:
    client = client_factory(rows=profile_rows())
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert "database" in body and "models" in body and "auth" in body


# ── authentication ──────────────────────────────────────────────────────────


def test_chat_requires_a_token(client_factory) -> None:
    client = client_factory(rows=profile_rows())
    response = client.post("/chat", json={"question": "when are finals"})
    assert response.status_code == 401
    assert "Authorization" in response.json()["detail"]


def test_a_malformed_authorization_header_is_rejected(client_factory) -> None:
    client = client_factory(rows=profile_rows())
    response = client.post("/chat", json={"question": "q"}, headers={"Authorization": make_token()})
    assert response.status_code == 401
    assert "Bearer" in response.json()["detail"]


def test_an_expired_token_is_rejected(client_factory) -> None:
    client = client_factory(rows=profile_rows())
    response = client.post(
        "/chat",
        json={"question": "q"},
        headers={"Authorization": f"Bearer {make_token(expired=True)}"},
    )
    assert response.status_code == 401
    assert "expired" in response.json()["detail"]


def test_a_token_signed_with_another_key_is_rejected(client_factory) -> None:
    client = client_factory(rows=profile_rows())
    forged = jwt.encode({"sub": USER_ID, "aud": "authenticated", "exp": 9999999999}, "other-key")
    response = client.post(
        "/chat", json={"question": "q"}, headers={"Authorization": f"Bearer {forged}"}
    )
    assert response.status_code == 401


def test_a_user_without_a_profile_cannot_query(client_factory) -> None:
    """Signed in, but has not joined an institution (PRD 4)."""
    client = client_factory(rows={"profile": None})
    response = client.post(
        "/chat",
        json={"question": "q"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert response.status_code == 401
    assert "institution" in response.json()["detail"]


def test_an_unknown_role_in_the_database_fails_closed(client_factory) -> None:
    client = client_factory(rows=profile_rows(role="superuser"))
    response = client.post(
        "/chat",
        json={"question": "q"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert response.status_code == 401


def test_the_role_comes_from_the_database_not_the_token(client_factory) -> None:
    """The token claims role=admin; the profile says student.

    A client can write its own `user_metadata`, so trusting the token here
    would let a student widen their own audience set (CLAUDE.md #4).
    """
    from app.api.auth import caller_from_token
    from app.retrieve.audience import Role

    settings = get_settings().model_copy(update={"supabase_jwt_secret": _secret()})
    caller = caller_from_token(FakeConn(profile_rows()), make_token(), settings)
    assert caller.role is Role.STUDENT
    assert caller.institution_id == INSTITUTION_ID


# ── the SSE contract ────────────────────────────────────────────────────────


def test_a_grounded_answer_streams_citations_then_text(client_factory) -> None:
    provider = StubProvider()
    client = client_factory(rows=profile_rows(), provider=provider)
    response = client.post(
        "/chat",
        json={"question": "when do the final examinations start"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")

    events = sse_events(response.text)
    names = [name for name, _ in events]
    # meta first (the conversation id the client keeps), then the sources, then
    # the answer text, then a terminal status.
    assert names[0] == "meta"
    assert names[1] == "citations"
    assert "delta" in names
    assert names[-1] == "done"
    assert dict(events)["meta"]["conversation_id"]

    citations = events[1][1]["citations"]
    assert citations and citations[0]["n"] == 1 and citations[0]["page_no"] == 3
    assert dict(events)["done"]["status"] == "answered"
    assert provider.generate_calls == 1


def test_below_the_floor_nothing_reaches_the_model(client_factory) -> None:
    """CLAUDE.md #9, at the HTTP boundary."""
    weak = {
        "profile": (USER_ID, INSTITUTION_ID, "student", "s@x.bd"),
        "chunks": [chunk_row(1, "Library opening hours are 9 to 5.", 0.10)],
    }
    client = client_factory(rows=weak, provider=ExplodingProvider())
    response = client.post(
        "/chat",
        json={"question": "how much is the hostel fee"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert response.status_code == 200
    events = dict(sse_events(response.text))
    assert events["done"]["status"] == "not_found"
    assert "Nothing in the published documents" in events["delta"]["text"]


def test_a_generation_failure_becomes_an_error_event_not_a_broken_stream(
    client_factory,
) -> None:
    class Failing(StubProvider):
        def generate(self, messages, *, stream=False):
            raise ProviderError("upstream 502", status=502, retryable=True)
            yield  # pragma: no cover

    client = client_factory(rows=profile_rows(), provider=Failing())
    response = client.post(
        "/chat",
        json={"question": "when do the final examinations start"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    events = dict(sse_events(response.text))
    assert "error" in events
    assert events["error"]["retryable"] is True


# ── the join guard (CLAUDE.md #3) ───────────────────────────────────────────


def test_an_unconfirmed_attachment_cannot_produce_an_answer(client_factory) -> None:
    rows = profile_rows(attachment=("att-1", False, {"courses": [{"code": "CSE 4101"}]}))
    client = client_factory(rows=rows, provider=ExplodingProvider())
    response = client.post(
        "/chat",
        json={"question": "when are my exams", "attachment_id": "att-1"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert response.status_code == 409
    assert "confirmation" in response.json()["detail"]


def test_another_users_attachment_is_not_found_rather_than_forbidden(client_factory) -> None:
    """PRD 8.4: it must be indistinguishable from an attachment that does not exist."""
    client = client_factory(rows=profile_rows(attachment=None))
    response = client.post(
        "/chat",
        json={"question": "when are my exams", "attachment_id": "someone-elses"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert response.status_code == 404


def test_a_confirmed_attachment_produces_a_join_answer(client_factory) -> None:
    rows = profile_rows(
        attachment=("att-1", True, {"courses": [{"code": "CSE 4101", "confidence": 0.99}]}),
    )
    rows["chunks"] = [chunk_row(9, "CSE 4101 Software Engineering — 14 December, 9:00 AM", 0.66)]
    provider = StubProvider("CSE 4101 is on 14 December [1].")
    client = client_factory(rows=rows, provider=provider)
    response = client.post(
        "/chat",
        json={"question": "when are my exams", "attachment_id": "att-1"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert response.status_code == 200
    events = dict(sse_events(response.text))
    assert events["done"]["status"] == "answered"
    assert provider.generate_calls == 1


# ── request validation ──────────────────────────────────────────────────────


def test_an_empty_question_is_rejected_before_any_work(client_factory) -> None:
    client = client_factory(rows=profile_rows(), provider=ExplodingProvider())
    response = client.post(
        "/chat", json={"question": ""}, headers={"Authorization": f"Bearer {make_token()}"}
    )
    assert response.status_code == 422


# ── persistence and the daily cap (PRD §10) ─────────────────────────────────


def test_the_question_and_the_answer_are_both_stored(client_factory) -> None:
    """A conversation the user can scroll tomorrow, and the citations with it."""
    rows = profile_rows()
    client = client_factory(rows=rows)
    response = client.post(
        "/chat",
        json={"question": "when do the final examinations start"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert response.status_code == 200

    stored = rows["messages"]
    assert [m["role"] for m in stored] == ["user", "assistant"]
    assert stored[0]["content"] == "when do the final examinations start"
    assert "05 September 2026" in stored[1]["content"]
    # The assistant row carries the sources; the user row carries none.
    assert stored[0]["citations"] == "[]"
    assert json.loads(stored[1]["citations"])[0]["page_no"] == 3


def test_a_new_conversation_is_titled_from_the_question(client_factory) -> None:
    rows = profile_rows()
    client = client_factory(rows=rows)
    client.post(
        "/chat",
        json={"question": "when do the final examinations start"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert rows["created_conversation"]["title"] == "when do the final examinations start"


def test_an_existing_conversation_is_continued_not_duplicated(client_factory) -> None:
    rows = profile_rows(conversation=("conv-existing",))
    client = client_factory(rows=rows)
    response = client.post(
        "/chat",
        json={"question": "and when do they end", "conversation_id": "conv-existing"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert dict(sse_events(response.text))["meta"]["conversation_id"] == "conv-existing"
    assert "created_conversation" not in rows


def test_the_not_found_answer_is_stored_too(client_factory) -> None:
    """The user should see their refused question in history, not a gap."""
    rows = {
        "profile": (USER_ID, INSTITUTION_ID, "student", "s@x.bd"),
        "chunks": [chunk_row(1, "Library opening hours are 9 to 5.", 0.10)],
    }
    client = client_factory(rows=rows, provider=ExplodingProvider())
    client.post(
        "/chat",
        json={"question": "how much is the hostel fee"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    stored = rows["messages"]
    assert [m["role"] for m in stored] == ["user", "assistant"]
    assert "Nothing in the published documents" in stored[1]["content"]


def test_the_daily_question_cap_refuses_before_any_retrieval(client_factory) -> None:
    settings = get_settings()
    rows = profile_rows(questions_today=settings.questions_per_day)
    client = client_factory(rows=rows, provider=ExplodingProvider())
    response = client.post(
        "/chat",
        json={"question": "one more question"},
        headers={"Authorization": f"Bearer {make_token()}"},
    )
    assert response.status_code == 429
    assert str(settings.questions_per_day) in response.json()["detail"]
    assert "messages" not in rows, "a refused question must not be stored"
