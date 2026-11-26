"""Institution creation, invite-code join, and /me. PRD 4.

The rules worth pinning: one institution per account, everyone joins as a
student regardless of who forwarded the code, and a wrong invite code cannot be
distinguished from an unknown one.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from app.api.deps import settings_dep
from app.config import get_settings
from app.main import create_app
from tests.test_api import INSTITUTION_ID, JWT_SECRET, USER_ID, FakeConn, FakePool, make_token


class InstitutionCursor:
    def __init__(self, state: dict):
        self.state = state
        self._result = None

    def execute(self, sql: str, params: dict | None = None) -> None:
        params = params or {}
        text = " ".join(sql.split())
        if text.startswith("select p.display_name, i.name"):
            self._result = self.state.get("me_details")
        elif text.startswith("update profiles set display_name"):
            self.state["renamed"] = params
            details = self.state.get("me_details") or (None, None, None)
            self.state["me_details"] = (params["display_name"], *details[1:])
            self._result = None
        elif text.startswith("select i.name, p.role::text"):
            self._result = self.state.get("membership")
        elif text.startswith("select id::text, name from institutions"):
            self.state["looked_up_code"] = params.get("code")
            self._result = self.state.get("institution_by_code")
        elif text.startswith("insert into institutions"):
            self.state["created_institution"] = params
            self._result = (INSTITUTION_ID,)
        elif text.startswith("insert into profiles"):
            self.state["created_profile"] = params
            self._result = (params.get("user_id"),)
        elif "from profiles p where" in text:
            self._result = self.state.get("profile")
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


class InstitutionConn(FakeConn):
    def __init__(self, state: dict):
        super().__init__(state)
        self.state = state

    def cursor(self):
        return InstitutionCursor(self.state)

    def commit(self) -> None:
        self.state["committed"] = True


class InstitutionPool(FakePool):
    def __init__(self, state: dict):
        self.state = state
        self.conn = InstitutionConn(state)

    def connection(self):
        from contextlib import contextmanager

        @contextmanager
        def _cm():
            yield self.conn

        return _cm()


@pytest.fixture
def client_for():
    settings = get_settings().model_copy(update={"supabase_jwt_secret": SecretStr(JWT_SECRET)})

    def build(state: dict | None = None):
        app = create_app()
        app.dependency_overrides[settings_dep] = lambda: settings
        pool = InstitutionPool(state or {})
        app.state.pool = pool
        app.state.pool_error = None
        app.state.provider = None
        return TestClient(app), pool

    return build


def auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {make_token()}"}


# ── creating an institution ─────────────────────────────────────────────────


def test_the_creator_becomes_the_admin(client_for) -> None:
    client, pool = client_for()
    response = client.post("/institutions", json={"name": "Green University"}, headers=auth())

    assert response.status_code == 201
    body = response.json()
    assert body["role"] == "admin"
    assert len(body["invite_code"]) >= 6
    assert pool.state["created_profile"]["role"] == "admin"


def test_the_invite_code_avoids_ambiguous_characters(client_for) -> None:
    """It is read off a screen and typed on a phone."""
    client, _ = client_for()
    code = client.post("/institutions", json={"name": "X University"}, headers=auth()).json()[
        "invite_code"
    ]
    assert not set(code) & set("O0I1")


def test_creating_a_second_institution_is_refused(client_for) -> None:
    """One institution per account (PRD 4): moving would move every conversation."""
    client, _ = client_for({"membership": ("Green University", "student")})
    response = client.post("/institutions", json={"name": "Another"}, headers=auth())
    assert response.status_code == 409
    assert "already belongs" in response.json()["detail"]


def test_creating_requires_authentication(client_for) -> None:
    # A valid body, so this asserts the auth check and not the validator.
    client, _ = client_for()
    assert client.post("/institutions", json={"name": "Green University"}).status_code == 401


# ── joining by invite code ──────────────────────────────────────────────────


def test_join_by_code_creates_a_student(client_for) -> None:
    client, pool = client_for({"institution_by_code": (INSTITUTION_ID, "Green University")})
    response = client.post("/institutions/join", json={"invite_code": "ptkqctgf"}, headers=auth())

    assert response.status_code == 200
    assert response.json()["role"] == "student"
    assert response.json()["institution_name"] == "Green University"
    # Codes are matched uppercase, so the user can type either case.
    assert pool.state["looked_up_code"] == "PTKQCTGF"
    assert pool.state["created_profile"]["role"] == "student"


def test_an_invite_code_never_grants_a_role(client_for) -> None:
    """A code travels by screenshot; a code that granted teacher would grant it
    to whoever forwarded the screenshot."""
    client, pool = client_for({"institution_by_code": (INSTITUTION_ID, "Green University")})
    client.post(
        "/institutions/join",
        json={"invite_code": "PTKQCTGF", "display_name": "Impostor"},
        headers=auth(),
    )
    assert pool.state["created_profile"]["role"] == "student"


def test_an_unknown_code_is_a_flat_404(client_for) -> None:
    client, _ = client_for({"institution_by_code": None})
    response = client.post("/institutions/join", json={"invite_code": "NOPE1234"}, headers=auth())
    assert response.status_code == 404
    assert "does not match" in response.json()["detail"]


def test_joining_twice_is_refused(client_for) -> None:
    client, _ = client_for(
        {
            "membership": ("Green University", "student"),
            "institution_by_code": (INSTITUTION_ID, "Green University"),
        }
    )
    response = client.post("/institutions/join", json={"invite_code": "PTKQCTGF"}, headers=auth())
    assert response.status_code == 409


# ── /me ─────────────────────────────────────────────────────────────────────


def test_me_reports_the_resolved_identity(client_for) -> None:
    client, _ = client_for({"profile": (USER_ID, INSTITUTION_ID, "student", "s@green.edu.bd")})
    body = client.get("/me", headers=auth()).json()
    assert body == {
        "user_id": USER_ID,
        "institution_id": INSTITUTION_ID,
        "role": "student",
        "email": "s@green.edu.bd",
        "display_name": None,
        "institution_name": None,
        "invite_code": None,
    }


def test_me_carries_the_names_home_greets_with(client_for) -> None:
    client, _ = client_for(
        {
            "profile": (USER_ID, INSTITUTION_ID, "student", "s@green.edu.bd"),
            "me_details": ("Nusrat", "Green University of Bangladesh", "GUB-7Q4K-20"),
        }
    )
    body = client.get("/me", headers=auth()).json()
    assert body["display_name"] == "Nusrat"
    assert body["institution_name"] == "Green University of Bangladesh"
    assert body["invite_code"] == "GUB-7Q4K-20"


def test_a_member_renames_only_themselves(client_for) -> None:
    client, pool = client_for(
        {
            "profile": (USER_ID, INSTITUTION_ID, "student", "s@green.edu.bd"),
            "me_details": ("Nusrat", "Green University of Bangladesh", "GUB-7Q4K-20"),
        }
    )
    response = client.patch("/me", json={"display_name": "  Nusrat J  "}, headers=auth())
    assert response.status_code == 200
    assert pool.state["renamed"] == {"user_id": USER_ID, "display_name": "Nusrat J"}
    assert response.json()["display_name"] == "Nusrat J"


def test_a_blank_display_name_clears_it(client_for) -> None:
    client, pool = client_for(
        {
            "profile": (USER_ID, INSTITUTION_ID, "student", "s@green.edu.bd"),
            "me_details": ("Nusrat", "Green University of Bangladesh", "GUB-7Q4K-20"),
        }
    )
    client.patch("/me", json={"display_name": "   "}, headers=auth())
    assert pool.state["renamed"]["display_name"] is None


def test_renaming_needs_membership(client_for) -> None:
    client, _ = client_for({"profile": None})
    assert client.patch("/me", json={"display_name": "x"}, headers=auth()).status_code == 401


def test_me_requires_membership(client_for) -> None:
    client, _ = client_for({"profile": None})
    assert client.get("/me", headers=auth()).status_code == 401
