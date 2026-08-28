"""Publishing, listing, and removing documents. PRD 4, 7.1, 10, 11.

The rules pinned here: only an admin publishes, `audience` is a required
choice with no default, the upload returns before ingestion runs, and a
document outside the caller's audience is missing rather than forbidden.
"""

from __future__ import annotations

from contextlib import contextmanager
from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from app.api.deps import settings_dep
from app.config import get_settings
from app.main import create_app
from tests.test_api import (
    INSTITUTION_ID,
    JWT_SECRET,
    USER_ID,
    FakeConn,
    FakePool,
    StubProvider,
    make_token,
)

PDF_BYTES = b"%PDF-1.4\n% minimal, never actually parsed in these tests\n"
NOW = datetime.now(UTC)


def document_row(
    doc_id: str = "doc-1",
    *,
    audience: str = "all",
    status_value: str = "ready",
    chunks: int = 12,
) -> tuple:
    return (
        doc_id,
        "Final Examination Notice",
        "notice.pdf",
        audience,
        status_value,
        1,
        "en",
        "native_text",
        0.93,
        None,
        NOW,
        chunks,
    )


class DocumentCursor:
    def __init__(self, state: dict):
        self.state = state
        self._result = None

    def execute(self, sql: str, params: dict | None = None) -> None:
        params = params or {}
        text = " ".join(sql.split())
        if "from profiles" in text:
            self._result = self.state.get("profile")
        elif text.startswith("select count(*) from documents"):
            self._result = (self.state.get("document_count", 0),)
        elif text.startswith("insert into documents"):
            self.state["inserted"] = params
            self._result = ("doc-new", NOW)
        elif text.startswith("delete from documents"):
            self.state["deleted"] = params
            self._result = self.state.get("delete_result")
        elif "from documents d" in text and "d.id = %(doc_id)s" in text:
            self.state["audiences_queried"] = params.get("audiences")
            self._result = self.state.get("document")
        elif "from documents d" in text:
            self.state["audiences_queried"] = params.get("audiences")
            self._result = self.state.get("documents", [])
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


class DocumentConn(FakeConn):
    def __init__(self, state: dict):
        super().__init__(state)
        self.state = state

    def cursor(self):
        return DocumentCursor(self.state)

    def commit(self) -> None:
        self.state["committed"] = True


class DocumentPool(FakePool):
    def __init__(self, state: dict):
        self.state = state
        self.conn = DocumentConn(state)

    def connection(self):
        @contextmanager
        def _cm():
            yield self.conn

        return _cm()


@pytest.fixture(autouse=True)
def no_real_storage(monkeypatch):
    calls: dict[str, list] = {"uploaded": [], "removed": []}

    def fake_upload(*, bucket, path, content, content_type, settings=None):
        calls["uploaded"].append((bucket, path, len(content)))
        return path

    def fake_remove(*, bucket, paths, settings=None):
        calls["removed"].append((bucket, tuple(paths)))
        return len(paths)

    monkeypatch.setattr("app.db.storage.upload", fake_upload)
    monkeypatch.setattr("app.db.storage.remove", fake_remove)
    return calls


@pytest.fixture
def document_client(monkeypatch):
    settings = get_settings().model_copy(update={"supabase_jwt_secret": SecretStr(JWT_SECRET)})
    scheduled: list[dict] = []

    def fake_publish(pool, provider, **kwargs):
        # The background task is asserted on, not executed: running it would
        # parse a PDF and call a model, neither of which this suite is about.
        scheduled.append(kwargs)
        return "ready"

    monkeypatch.setattr("app.api.documents.publish_document", fake_publish)

    def build(role: str = "admin", state: dict | None = None):
        full = {"profile": (USER_ID, INSTITUTION_ID, role, "admin@green.edu.bd")}
        full.update(state or {})
        app = create_app()
        app.dependency_overrides[settings_dep] = lambda: settings
        pool = DocumentPool(full)
        app.state.pool = pool
        app.state.pool_error = None
        app.state.provider = StubProvider()
        return TestClient(app), pool, scheduled

    return build


def auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {make_token()}"}


def upload(name: str = "notice.pdf", content: bytes = PDF_BYTES, mime: str = "application/pdf"):
    return {"file": (name, content, mime)}


# ── publishing is an admin action (PRD 4) ───────────────────────────────────


def test_a_student_cannot_publish(document_client) -> None:
    client, _, scheduled = document_client(role="student")
    response = client.post(
        "/documents",
        files=upload(),
        data={"title": "Notice", "audience": "all"},
        headers=auth(),
    )
    assert response.status_code == 403
    assert scheduled == []


def test_a_teacher_cannot_publish(document_client) -> None:
    client, _, _ = document_client(role="teacher")
    response = client.post(
        "/documents",
        files=upload(),
        data={"title": "Notice", "audience": "all"},
        headers=auth(),
    )
    assert response.status_code == 403


def test_publishing_requires_authentication(document_client) -> None:
    client, _, _ = document_client()
    assert (
        client.post(
            "/documents", files=upload(), data={"title": "Notice", "audience": "all"}
        ).status_code
        == 401
    )


# ── audience is a required choice (DESIGN §6.7) ─────────────────────────────


def test_audience_is_required(document_client) -> None:
    """A forgotten field must not quietly mean "everyone"."""
    client, _, _ = document_client()
    response = client.post("/documents", files=upload(), data={"title": "Notice"}, headers=auth())
    assert response.status_code == 422


def test_an_unknown_audience_is_refused(document_client) -> None:
    client, _, _ = document_client()
    response = client.post(
        "/documents",
        files=upload(),
        data={"title": "Notice", "audience": "everyone"},
        headers=auth(),
    )
    assert response.status_code == 422
    assert "audience must be one of" in response.json()["detail"]


@pytest.mark.parametrize("audience", ["all", "students", "teachers", "admin_only"])
def test_every_valid_audience_is_accepted_and_stored(document_client, audience: str) -> None:
    client, pool, scheduled = document_client()
    response = client.post(
        "/documents",
        files=upload(),
        data={"title": "Notice", "audience": audience},
        headers=auth(),
    )
    assert response.status_code == 202
    assert response.json()["audience"] == audience
    assert pool.state["inserted"]["audience"] == audience
    # The chunks written later inherit the same audience.
    assert scheduled[-1]["audience"] == audience


# ── the upload returns before the work happens (PRD 11) ─────────────────────


def test_the_upload_returns_immediately_with_a_pending_status(document_client) -> None:
    client, _, scheduled = document_client()
    response = client.post(
        "/documents",
        files=upload(),
        data={"title": "Final Examination Notice", "audience": "all"},
        headers=auth(),
    )
    assert response.status_code == 202
    body = response.json()
    assert body["status"] == "uploaded"
    assert body["chunk_count"] == 0
    # ...and the real work was handed to a background task.
    assert scheduled and scheduled[-1]["doc_id"] == "doc-new"


def test_the_file_is_stored_before_the_row(document_client, no_real_storage) -> None:
    client, pool, _ = document_client()
    client.post(
        "/documents",
        files=upload(),
        data={"title": "Notice", "audience": "all"},
        headers=auth(),
    )
    bucket, path, size = no_real_storage["uploaded"][-1]
    assert bucket == "documents"
    assert size == len(PDF_BYTES)
    assert pool.state["inserted"]["storage_path"] == f"documents/{path}"


# ── limits (PRD §10) ────────────────────────────────────────────────────────


def test_the_document_cap_is_enforced(document_client) -> None:
    settings = get_settings()
    client, _, scheduled = document_client(
        state={"document_count": settings.documents_per_institution}
    )
    response = client.post(
        "/documents",
        files=upload(),
        data={"title": "One more", "audience": "all"},
        headers=auth(),
    )
    assert response.status_code == 429
    assert str(settings.documents_per_institution) in response.json()["detail"]
    assert scheduled == []


def test_an_oversized_document_is_refused(document_client) -> None:
    settings = get_settings()
    client, _, _ = document_client()
    big = b"x" * ((settings.max_upload_mb + 1) * 1024 * 1024)
    response = client.post(
        "/documents",
        files=upload(content=big),
        data={"title": "Huge", "audience": "all"},
        headers=auth(),
    )
    assert response.status_code == 413


def test_a_non_document_file_is_refused(document_client) -> None:
    client, _, _ = document_client()
    response = client.post(
        "/documents",
        files={"file": ("notes.docx", b"x", "application/msword")},
        data={"title": "Notes", "audience": "all"},
        headers=auth(),
    )
    assert response.status_code == 415


# ── listing and reading, audience-filtered in the query ─────────────────────


def test_the_list_is_filtered_by_the_callers_audience(document_client) -> None:
    client, pool, _ = document_client(
        role="student", state={"documents": [document_row(), document_row("doc-2")]}
    )
    body = client.get("/documents", headers=auth()).json()

    assert body["total"] == 2
    assert body["documents"][0]["status"] == "ready"
    # A student's query asks only for the audiences a student may read.
    assert pool.state["audiences_queried"] == ["all", "students"]


def test_an_admin_sees_every_audience(document_client) -> None:
    client, pool, _ = document_client(role="admin", state={"documents": []})
    client.get("/documents", headers=auth())
    assert pool.state["audiences_queried"] == ["admin_only", "all", "students", "teachers"]


def test_a_document_outside_the_audience_is_missing_not_forbidden(document_client) -> None:
    """A 403 would confirm the document exists -- the same leak as retrieval."""
    client, _, _ = document_client(role="student", state={"document": None})
    response = client.get("/documents/doc-secret", headers=auth())
    assert response.status_code == 404


def test_a_failed_document_reports_why(document_client) -> None:
    """DESIGN §6.6 gives "failed" its own treatment, so the reason must survive."""
    row = list(document_row(status_value="failed", chunks=0))
    row[9] = "Only 12 characters could be read from this document."
    client, _, _ = document_client(state={"document": tuple(row)})
    body = client.get("/documents/doc-1", headers=auth()).json()
    assert body["status"] == "failed"
    assert "12 characters" in body["failure_reason"]


# ── deletion ────────────────────────────────────────────────────────────────


def test_only_an_admin_can_delete(document_client) -> None:
    client, _, _ = document_client(role="teacher")
    assert client.delete("/documents/doc-1", headers=auth()).status_code == 403


def test_deleting_removes_the_row_and_the_file(document_client, no_real_storage) -> None:
    client, pool, _ = document_client(state={"delete_result": ("documents/inst/abc.pdf",)})
    response = client.delete("/documents/doc-1", headers=auth())

    assert response.status_code == 204
    assert pool.state["deleted"]["doc_id"] == "doc-1"
    assert no_real_storage["removed"] == [("documents", ("inst/abc.pdf",))]


def test_deleting_something_that_is_not_there_is_a_404(document_client) -> None:
    client, _, _ = document_client(state={"delete_result": None})
    assert client.delete("/documents/doc-1", headers=auth()).status_code == 404
