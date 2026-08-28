"""Conversation history and the source-viewer URL. PRD 9, DESIGN §6.5."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from app.api.deps import settings_dep
from app.config import get_settings
from app.main import create_app
from tests.test_api import INSTITUTION_ID, JWT_SECRET, USER_ID, FakeConn, FakePool, make_token

NOW = datetime.now(UTC)


class HistoryCursor:
    def __init__(self, state: dict):
        self.state = state
        self._result = None

    def execute(self, sql: str, params: dict | None = None) -> None:
        params = params or {}
        text = " ".join(sql.split())
        if "from profiles" in text:
            self._result = self.state.get("profile")
        elif text.startswith("select c.id::text, c.title"):
            self.state["listed_for"] = params.get("user_id")
            self._result = self.state.get("conversations", [])
        elif text.startswith("select id::text, title, created_at from conversations"):
            self._result = self.state.get("conversation")
        elif text.startswith("select m.id::text"):
            self._result = self.state.get("messages", [])
        elif text.startswith("delete from conversations"):
            self.state["deleted"] = params
            self._result = self.state.get("delete_result")
        elif "from documents" in text:
            self.state["audiences_queried"] = params.get("audiences")
            self._result = self.state.get("document")
        else:
            self._result = None

    def fetchone(self):
        result = self._result
        if isinstance(result, list):
            return result[0] if result else None
        return result

    def fetchall(self):
        return self._result if isinstance(self._result, list) else []

    def __enter__(self):
        return self

    def __exit__(self, *exc: object) -> None:
        return None


class HistoryConn(FakeConn):
    def __init__(self, state: dict):
        super().__init__(state)
        self.state = state

    def cursor(self):
        return HistoryCursor(self.state)

    def commit(self) -> None:
        self.state["committed"] = True


class HistoryPool(FakePool):
    def __init__(self, state: dict):
        self.state = state
        self.conn = HistoryConn(state)

    def connection(self):
        @contextmanager
        def _cm():
            yield self.conn

        return _cm()


@pytest.fixture(autouse=True)
def fake_signing(monkeypatch):
    signed: list[tuple[str, str, int]] = []

    def fake_signed_url(*, bucket, path, expires_in=3600, settings=None):
        signed.append((bucket, path, expires_in))
        return f"https://storage.test/{bucket}/{path}?token=signed&exp={expires_in}"

    monkeypatch.setattr("app.db.storage.signed_url", fake_signed_url)
    return signed


@pytest.fixture
def history_client():
    settings = get_settings().model_copy(update={"supabase_jwt_secret": SecretStr(JWT_SECRET)})

    def build(role: str = "student", state: dict | None = None):
        full = {"profile": (USER_ID, INSTITUTION_ID, role, "s@green.edu.bd")}
        full.update(state or {})
        app = create_app()
        app.dependency_overrides[settings_dep] = lambda: settings
        pool = HistoryPool(full)
        app.state.pool = pool
        app.state.pool_error = None
        app.state.provider = None
        return TestClient(app), pool

    return build


def auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {make_token()}"}


# ── the conversation list ───────────────────────────────────────────────────


def test_the_list_is_scoped_to_the_caller(history_client) -> None:
    rows = [
        (
            "conv-1",
            "When do finals start?",
            NOW,
            4,
            "The Final Examinations start on 05 September 2026 [1].",
        )
    ]
    client, pool = history_client(state={"conversations": rows})
    body = client.get("/conversations", headers=auth()).json()

    assert body["total"] == 1
    assert body["conversations"][0]["message_count"] == 4
    assert body["conversations"][0]["last_answer"].startswith("The Final Examinations")
    assert pool.state["listed_for"] == USER_ID


def test_a_long_answer_is_previewed_not_returned_whole(history_client) -> None:
    """The list row shows a preview; the full text lives in the conversation."""
    rows = [("conv-1", "Title", NOW, 2, "x" * 500)]
    client, _ = history_client(state={"conversations": rows})
    preview = client.get("/conversations", headers=auth()).json()["conversations"][0]["last_answer"]
    assert preview.endswith("…")
    assert len(preview) <= 121


def test_an_empty_history_is_an_empty_list_not_a_404(history_client) -> None:
    client, _ = history_client(state={"conversations": []})
    response = client.get("/conversations", headers=auth())
    assert response.status_code == 200
    assert response.json() == {"conversations": [], "total": 0}


# ── one conversation ────────────────────────────────────────────────────────


def test_messages_come_back_with_their_citations(history_client) -> None:
    state = {
        "conversation": ("conv-1", "When do finals start?", NOW),
        "messages": [
            ("m1", "user", "when do finals start", "en", [], NOW),
            (
                "m2",
                "assistant",
                "They start on 05 September 2026 [1].",
                "en",
                [{"n": 1, "page_no": 1, "doc_id": "doc-1", "snippet": "…"}],
                NOW,
            ),
        ],
    }
    client, _ = history_client(state=state)
    body = client.get("/conversations/conv-1", headers=auth()).json()

    assert [m["role"] for m in body["messages"]] == ["user", "assistant"]
    assert body["messages"][1]["citations"][0]["page_no"] == 1
    assert body["messages"][0]["citations"] == []


def test_someone_elses_conversation_is_missing_not_forbidden(history_client) -> None:
    client, _ = history_client(state={"conversation": None})
    assert client.get("/conversations/conv-other", headers=auth()).status_code == 404


def test_history_requires_authentication(history_client) -> None:
    client, _ = history_client()
    assert client.get("/conversations").status_code == 401


def test_a_conversation_can_be_deleted(history_client) -> None:
    client, pool = history_client(state={"delete_result": ("conv-1",)})
    assert client.delete("/conversations/conv-1", headers=auth()).status_code == 204
    assert pool.state["deleted"]["user_id"] == USER_ID


def test_deleting_someone_elses_conversation_is_a_404(history_client) -> None:
    client, _ = history_client(state={"delete_result": None})
    assert client.delete("/conversations/conv-other", headers=auth()).status_code == 404


# ── the source viewer (DESIGN §6.5) ─────────────────────────────────────────


def test_the_source_url_is_signed_and_expires(history_client, fake_signing) -> None:
    client, _ = history_client(
        state={"document": ("documents/inst/notice.pdf", "Final Examination Notice", 3)}
    )
    body = client.get("/documents/doc-1/file?page=2", headers=auth()).json()

    assert body["page_no"] == 2
    assert body["page_count"] == 3
    assert "token=signed" in body["url"]
    assert body["expires_in"] > 0
    bucket, path, expires = fake_signing[0]
    assert (bucket, path) == ("documents", "inst/notice.pdf")
    assert expires == body["expires_in"]


def test_the_file_of_an_out_of_audience_document_is_a_404(history_client) -> None:
    """Same rule as retrieval: a 403 would confirm the document exists."""
    client, pool = history_client(role="student", state={"document": None})
    assert client.get("/documents/doc-secret/file", headers=auth()).status_code == 404
    assert pool.state["audiences_queried"] == ["all", "students"]


def test_a_locally_indexed_document_says_it_has_no_file(history_client) -> None:
    """`tools/ingest_corpus.py` indexes without uploading; that is not a 503."""
    client, _ = history_client(state={"document": ("local://notice.pdf", "Notice", 1)})
    response = client.get("/documents/doc-1/file", headers=auth())
    assert response.status_code == 409
    assert "nothing to open" in response.json()["detail"]


def test_a_page_below_one_is_clamped(history_client) -> None:
    client, _ = history_client(state={"document": ("documents/inst/notice.pdf", "Notice", 3)})
    body = client.get("/documents/doc-1/file?page=0", headers=auth()).json()
    assert body["page_no"] == 1
