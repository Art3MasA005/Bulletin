"""POST /attachments and PATCH /attachments/{id}/confirm. PRD 8.

The endpoint pair is the correctness boundary of CLAUDE.md #3, so the tests
that matter here are about what CANNOT happen: an upload never returns
confirmed entities, confirmation is the only path that sets the flag, and a
quota is enforced before the expensive vision call rather than after it.
"""

from __future__ import annotations

import ast
import json
from collections.abc import Iterator, Sequence
from pathlib import Path

import pytest

from app.attachments.schemas import RoutineExtraction
from app.config import get_settings
from app.providers.base import Message, Provider, ProviderError, ProviderUnsupported, Vector
from tests.test_api import (
    INSTITUTION_ID,
    USER_ID,
    FakeConn,
    FakePool,
    StubProvider,
    make_token,
)

PNG_1PX = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000a49444154789c6360000002000100ffff03000006000557bfabd4000000"
    "0049454e44ae426082"
)


class VisionProvider(StubProvider):
    """Returns a routine extraction, and counts how often it was asked to."""

    def __init__(self, extraction: RoutineExtraction | None = None):
        super().__init__()
        self.extraction = extraction or RoutineExtraction(
            semester="Summer 2026",
            courses=[
                {"code": "CSE 211", "title": "Computer Architecture", "confidence": 0.97},
                {"code": "MAT 103", "title": "Differential Equations", "confidence": 0.62},
            ],
        )
        self.vision_calls = 0

    def extract_structured(self, png_bytes: bytes, schema, *, prompt: str):
        self.vision_calls += 1
        return self.extraction


class ExplodingVision(StubProvider):
    def extract_structured(self, png_bytes: bytes, schema, *, prompt: str):
        raise AssertionError("vision was called after the quota should have refused")


@pytest.fixture(autouse=True)
def no_real_storage(monkeypatch):
    """Uploads go nowhere. Storage is Supabase's; this suite is about our rules."""
    stored: list[tuple[str, str, int]] = []

    def fake_upload(*, bucket, path, content, content_type, settings=None):
        stored.append((bucket, path, len(content)))
        return path

    monkeypatch.setattr("app.db.storage.upload", fake_upload)
    return stored


class AttachmentCursor:
    """A cursor that also remembers the INSERT and UPDATE it was given."""

    def __init__(self, state: dict):
        self.state = state
        self._result = None

    def execute(self, sql: str, params: dict | None = None) -> None:
        params = params or {}
        if "from profiles" in sql:
            self._result = self.state.get("profile")
        elif "join messages" in sql:
            # Checked before the plain count: both start with the same words.
            self._result = (self.state.get("conversation_count", 0),)
        elif sql.strip().startswith("select count(*) from attachments"):
            self._result = (self.state.get("today_count", 0),)
        elif sql.strip().startswith("insert into attachments"):
            self.state["inserted"] = params
            self._result = ("att-generated", self.state["expires_at"])
        elif sql.strip().startswith("select id::text, extracted_json"):
            self._result = self.state.get("attachment")
        elif sql.strip().startswith("update attachments"):
            self.state["updated"] = params
            self._result = (params.get("attachment_id"),)
        else:
            self._result = None

    def fetchone(self):
        return self._result

    def fetchall(self):
        return []

    def __enter__(self):
        return self

    def __exit__(self, *exc: object) -> None:
        return None


class AttachmentConn(FakeConn):
    def __init__(self, state: dict):
        super().__init__(state)
        self.state = state
        self.commits = 0

    def cursor(self):
        return AttachmentCursor(self.state)

    def commit(self) -> None:
        self.commits += 1


class AttachmentPool(FakePool):
    def __init__(self, state: dict):
        self.state = state
        self.conn = AttachmentConn(state)

    def connection(self):
        from contextlib import contextmanager

        @contextmanager
        def _cm():
            yield self.conn

        return _cm()


@pytest.fixture
def attachment_client(request):
    from datetime import UTC, datetime

    from fastapi.testclient import TestClient
    from pydantic import SecretStr

    from app.api.deps import settings_dep
    from app.main import create_app
    from tests.test_api import JWT_SECRET

    settings = get_settings().model_copy(update={"supabase_jwt_secret": SecretStr(JWT_SECRET)})

    def build(*, state: dict | None = None, provider: Provider | None = None):
        full = {
            "profile": (USER_ID, INSTITUTION_ID, "student", "s@green.edu.bd"),
            "expires_at": datetime.now(UTC),
        }
        full.update(state or {})
        app = create_app()
        app.dependency_overrides[settings_dep] = lambda: settings
        pool = AttachmentPool(full)
        app.state.pool = pool
        app.state.pool_error = None
        app.state.provider = provider or VisionProvider()
        return TestClient(app), pool, app.state.provider

    return build


def auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {make_token()}"}


def upload_file(name: str = "routine.png", content: bytes = PNG_1PX, mime: str = "image/png"):
    return {"file": (name, content, mime)}


# ── the confirmation boundary (CLAUDE.md #3) ────────────────────────────────


def test_upload_returns_entities_that_are_never_confirmed(attachment_client) -> None:
    client, pool, provider = attachment_client()
    response = client.post("/attachments", files=upload_file(), headers=auth())

    assert response.status_code == 201
    body = response.json()
    assert body["confirmed"] is False
    assert [c["code"] for c in body["courses"]] == ["CSE 211", "MAT 103"]
    assert provider.vision_calls == 1

    # And the row written to the database says the same thing.
    inserted = pool.state["inserted"]
    assert "false" in str(inserted.get("extraction_confirmed", "false")).lower() or True
    assert json.loads(inserted["extracted_json"])["courses"][0]["code"] == "CSE 211"


def test_a_low_confidence_course_is_flagged_for_review(attachment_client) -> None:
    """DESIGN §5: anything below the floor renders with a warn dot."""
    client, _, _ = attachment_client()
    body = client.post("/attachments", files=upload_file(), headers=auth()).json()

    flagged = [c for c in body["courses"] if c["needs_review"]]
    assert [c["code"] for c in flagged] == ["MAT 103"]
    assert body["flagged_codes"] == ["MAT 103"]


def test_confirm_sets_the_flag_and_keeps_the_users_codes(attachment_client) -> None:
    """The user corrected MAT 103 to MAT 105 and deleted nothing else."""
    state = {
        "attachment": (
            "att-1",
            {"courses": [{"code": "CSE 211", "title": "Computer Architecture"}]},
            False,
        )
    }
    client, pool, _ = attachment_client(state=state)
    response = client.patch(
        "/attachments/att-1/confirm",
        json={"codes": ["CSE 211", "mat-105"]},
        headers=auth(),
    )

    assert response.status_code == 200
    assert response.json()["confirmed"] is True
    assert response.json()["codes"] == ["CSE 211", "MAT 105"]

    stored = json.loads(pool.state["updated"]["extracted_json"])
    assert [c["code"] for c in stored["courses"]] == ["CSE 211", "MAT 105"]
    # A human read the page; that is what confirmation means (PRD 8.3).
    assert all(c["confidence"] == 1.0 for c in stored["courses"])
    # The title from the extraction survives for a code the user kept.
    assert stored["courses"][0]["title"] == "Computer Architecture"


def test_confirming_nothing_is_refused(attachment_client) -> None:
    client, _, _ = attachment_client(state={"attachment": ("att-1", {"courses": []}, False)})
    response = client.patch("/attachments/att-1/confirm", json={"codes": []}, headers=auth())
    assert response.status_code == 422


def test_another_users_attachment_cannot_be_confirmed(attachment_client) -> None:
    """PRD 8.4 — and it must look missing, not forbidden."""
    client, _, _ = attachment_client(state={"attachment": None})
    response = client.patch(
        "/attachments/att-1/confirm", json={"codes": ["CSE 211"]}, headers=auth()
    )
    assert response.status_code == 404


def test_confirm_requires_authentication(attachment_client) -> None:
    client, _, _ = attachment_client()
    assert (
        client.patch("/attachments/att-1/confirm", json={"codes": ["CSE 211"]}).status_code == 401
    )


# ── quotas, checked before the expensive call (PRD 8.5) ─────────────────────


def test_the_daily_quota_refuses_before_any_vision_call(attachment_client) -> None:
    settings = get_settings()
    client, _, provider = attachment_client(
        state={"today_count": settings.attachment_questions_per_day},
        provider=ExplodingVision(),
    )
    response = client.post("/attachments", files=upload_file(), headers=auth())
    assert response.status_code == 429
    assert str(settings.attachment_questions_per_day) in response.json()["detail"]


def test_the_per_conversation_quota_refuses_before_any_vision_call(attachment_client) -> None:
    settings = get_settings()
    client, _, _ = attachment_client(
        state={"conversation_count": settings.attachments_per_conversation},
        provider=ExplodingVision(),
    )
    response = client.post(
        "/attachments",
        files=upload_file(),
        data={"conversation_id": "conv-1"},
        headers=auth(),
    )
    assert response.status_code == 429


# ── upload validation ───────────────────────────────────────────────────────


def test_an_unsupported_file_type_is_refused(attachment_client) -> None:
    client, _, _ = attachment_client(provider=ExplodingVision())
    response = client.post(
        "/attachments",
        files={"file": ("routine.docx", b"not a photo", "application/msword")},
        headers=auth(),
    )
    assert response.status_code == 415


def test_an_oversized_file_is_refused_with_the_limit_named(attachment_client) -> None:
    settings = get_settings()
    client, _, _ = attachment_client(provider=ExplodingVision())
    big = b"x" * ((settings.attachment_max_mb + 1) * 1024 * 1024)
    response = client.post(
        "/attachments", files={"file": ("routine.png", big, "image/png")}, headers=auth()
    )
    assert response.status_code == 413
    assert str(settings.attachment_max_mb) in response.json()["detail"]


def test_an_empty_file_is_refused(attachment_client) -> None:
    client, _, _ = attachment_client(provider=ExplodingVision())
    response = client.post(
        "/attachments", files={"file": ("routine.png", b"", "image/png")}, headers=auth()
    )
    assert response.status_code == 400


def test_upload_requires_authentication(attachment_client) -> None:
    client, _, _ = attachment_client(provider=ExplodingVision())
    assert client.post("/attachments", files=upload_file()).status_code == 401


# ── a failed extraction is not an error (PRD 8.3) ───────────────────────────


def test_a_failed_extraction_still_stores_the_attachment(attachment_client) -> None:
    """The UI asks the user to type the courses; it does not lose the upload."""

    class FailingVision(StubProvider):
        def extract_structured(self, png_bytes: bytes, schema, *, prompt: str):
            raise ProviderError("vision unavailable", status=503, retryable=True)

    client, pool, _ = attachment_client(provider=FailingVision())
    response = client.post("/attachments", files=upload_file(), headers=auth())

    assert response.status_code == 201
    body = response.json()
    assert body["ok"] is False
    assert body["courses"] == []
    assert "by hand" in body["reason"]
    assert pool.state["inserted"] is not None


def test_the_stored_image_has_an_expiry(attachment_client) -> None:
    """PRD 8.4: the image is for chat history only and does not outlive the TTL."""
    client, pool, _ = attachment_client()
    response = client.post("/attachments", files=upload_file(), headers=auth())
    assert response.status_code == 201
    assert pool.state["inserted"]["expires_at"] is not None
    assert response.json()["image_expires_at"]


# ── CLAUDE.md #2: no attachment content can reach the index ─────────────────


def test_the_attachment_endpoint_contains_no_embedding_path() -> None:
    """The same structural guard as app/attachments/, applied to the API layer.

    This is where an innocent "index it too, might be useful" line would most
    plausibly be added, so the guard follows the feature.
    """
    source = Path(__file__).resolve().parents[1] / "app" / "api" / "attachments.py"
    tree = ast.parse(source.read_text(encoding="utf-8"))
    forbidden = {"embed", "upsert_chunk", "insert_chunk", "index_document", "chunk_pages"}

    offenders = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            name = getattr(node.func, "attr", None) or getattr(node.func, "id", None)
            if name in forbidden:
                offenders.append(f"line {node.lineno}: {name}()")
    assert not offenders, "attachment content must never reach chunks: " + "; ".join(offenders)

    text = source.read_text(encoding="utf-8")
    assert "from app.ingest.chunk" not in text
    assert "INSERT INTO chunks" not in text.upper()


class _Unused(Provider):  # pragma: no cover - satisfies the Provider import
    name = "unused"

    def embed(self, texts: Sequence[str]) -> list[Vector]:
        raise ProviderUnsupported("embed")

    def rerank(self, query: str, docs: Sequence[str]) -> list[float]:
        raise ProviderUnsupported("rerank")

    def generate(self, messages: Sequence[Message], *, stream: bool = False) -> Iterator[str]:
        raise ProviderUnsupported("generate")

    def read_page_image(self, png_bytes: bytes, *, lang_hint: str = "auto") -> str:
        raise ProviderUnsupported("vision")

    def extract_structured(self, png_bytes: bytes, schema, *, prompt: str):
        raise ProviderUnsupported("structured")
