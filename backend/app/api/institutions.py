"""Institutions: create one, or join one by invite code. PRD 4.

    POST /institutions        create an institution and become its admin
    POST /institutions/join   join an existing one by invite code
    GET  /me                  who the caller is, as the app sees them

These are the only endpoints a signed-in user can reach without a profile row,
because they are what creates one. Everything else requires membership
(app/api/deps.current_caller), which is why they take the token directly rather
than a resolved Caller.

One institution per account in v1 (PRD 4). Joining twice is refused rather than
silently moving the account, because moving it would move every conversation
with it and quietly change what the user can see.
"""

from __future__ import annotations

import logging
import secrets

from fastapi import APIRouter, Header, HTTPException, status
from pydantic import BaseModel, Field

from app.api.auth import AuthError, bearer_token, decode_token
from app.api.deps import CallerDep, ConnDep, SettingsDep
from app.retrieve.audience import Role

logger = logging.getLogger(__name__)

router = APIRouter(tags=["institutions"])

# Unambiguous alphabet: no O/0 or I/1, because this code is read off a screen
# and typed on a phone.
_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
INVITE_CODE_LENGTH = 8

FIND_BY_CODE_SQL = "select id::text, name from institutions where invite_code = %(code)s"
EXISTING_PROFILE_SQL = """
select i.name, p.role::text
from profiles p join institutions i on i.id = p.institution_id
where p.id = %(user_id)s
"""
# What Home and Settings need beyond the caller: the name to greet, the
# institution the answers come from, and the code the member joined with
# (Settings shows it; every member already had it to get in).
ME_DETAILS_SQL = """
select p.display_name, i.name, i.invite_code
from profiles p join institutions i on i.id = p.institution_id
where p.id = %(user_id)s
"""
# Scoped by the caller's own id in the query: a member can only ever rename
# themselves.
UPDATE_DISPLAY_NAME_SQL = """
update profiles set display_name = %(display_name)s
where id = %(user_id)s
"""
CREATE_INSTITUTION_SQL = """
insert into institutions (name, invite_code) values (%(name)s, %(code)s)
returning id::text
"""
CREATE_PROFILE_SQL = """
insert into profiles (id, institution_id, email, display_name, role)
values (%(user_id)s, %(institution_id)s, %(email)s, %(display_name)s, %(role)s)
returning id::text
"""


class CreateInstitution(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    display_name: str | None = Field(default=None, max_length=80)


class JoinInstitution(BaseModel):
    invite_code: str = Field(min_length=4, max_length=32)
    display_name: str | None = Field(default=None, max_length=80)


class Membership(BaseModel):
    user_id: str
    institution_id: str
    institution_name: str
    role: str
    # Only ever populated for the admin who created the institution: it is the
    # code they hand out, and nobody else needs to see it.
    invite_code: str | None = None


class Me(BaseModel):
    user_id: str
    institution_id: str
    role: str
    email: str | None = None
    display_name: str | None = None
    institution_name: str | None = None
    invite_code: str | None = None


class UpdateMe(BaseModel):
    # Blank clears it, and the app falls back to the sign-up name.
    display_name: str | None = Field(default=None, max_length=60)


def invite_code() -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(INVITE_CODE_LENGTH))


def _identity(authorization: str | None, settings) -> tuple[str, str | None]:
    """(user_id, email) from the token alone -- there is no profile row yet."""
    try:
        claims = decode_token(bearer_token(authorization), settings)
    except AuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    user_id = str(claims.get("sub") or "")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="token has no subject")
    email = claims.get("email")
    return user_id, str(email) if email else None


def _refuse_if_already_a_member(conn, user_id: str) -> None:
    with conn.cursor() as cur:
        cur.execute(EXISTING_PROFILE_SQL, {"user_id": user_id})
        row = cur.fetchone()
    if row is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"This account already belongs to {row[0]} as {row[1]}.",
        )


@router.post("/institutions", response_model=Membership, status_code=status.HTTP_201_CREATED)
def create_institution(
    body: CreateInstitution,
    conn: ConnDep,
    settings: SettingsDep,
    authorization: str | None = Header(default=None),
) -> Membership:
    """Create an institution. The caller becomes its admin.

    Whoever sets up the institution is the person who publishes its documents,
    so they are the admin by construction rather than by a later grant.
    """
    user_id, email = _identity(authorization, settings)
    _refuse_if_already_a_member(conn, user_id)

    code = invite_code()
    with conn.cursor() as cur:
        cur.execute(CREATE_INSTITUTION_SQL, {"name": body.name, "code": code})
        institution_id = cur.fetchone()[0]
        cur.execute(
            CREATE_PROFILE_SQL,
            {
                "user_id": user_id,
                "institution_id": institution_id,
                "email": email or "",
                "display_name": body.display_name,
                "role": Role.ADMIN.value,
            },
        )
    conn.commit()

    logger.info("institution created id=%s admin=%s", institution_id, user_id)
    return Membership(
        user_id=user_id,
        institution_id=institution_id,
        institution_name=body.name,
        role=Role.ADMIN.value,
        invite_code=code,
    )


@router.post("/institutions/join", response_model=Membership)
def join_institution(
    body: JoinInstitution,
    conn: ConnDep,
    settings: SettingsDep,
    authorization: str | None = Header(default=None),
) -> Membership:
    """Join by invite code, as a student.

    Everyone joins as a student. Teacher and admin are granted by an admin
    afterwards -- an invite code travels by screenshot and group chat, and a
    code that granted a role would hand out that role to whoever forwarded it.
    """
    user_id, email = _identity(authorization, settings)
    _refuse_if_already_a_member(conn, user_id)

    code = body.invite_code.strip().upper()
    with conn.cursor() as cur:
        cur.execute(FIND_BY_CODE_SQL, {"code": code})
        row = cur.fetchone()
    if row is None:
        # Deliberately identical wording for "no such code" and a typo: an
        # invite code is a secret, and a distinguishing error would let it be
        # brute-forced by observing which guesses answer differently.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="That invite code does not match any institution.",
        )
    institution_id, name = row

    with conn.cursor() as cur:
        cur.execute(
            CREATE_PROFILE_SQL,
            {
                "user_id": user_id,
                "institution_id": institution_id,
                "email": email or "",
                "display_name": body.display_name,
                "role": Role.STUDENT.value,
            },
        )
    conn.commit()

    logger.info("user %s joined institution %s", user_id, institution_id)
    return Membership(
        user_id=user_id,
        institution_id=institution_id,
        institution_name=name,
        role=Role.STUDENT.value,
    )


@router.get("/me", response_model=Me, tags=["auth"])
def me(caller: CallerDep, conn: ConnDep) -> Me:
    """The caller as the backend resolved them, plus the names Home greets
    with. Useful to the client on launch."""
    with conn.cursor() as cur:
        cur.execute(ME_DETAILS_SQL, {"user_id": caller.user_id})
        row = cur.fetchone()
    display_name, institution_name, code = row if row is not None else (None, None, None)
    return Me(
        user_id=caller.user_id,
        institution_id=caller.institution_id,
        role=caller.role.value,
        email=caller.email,
        display_name=display_name,
        institution_name=institution_name,
        invite_code=code,
    )


@router.patch("/me", response_model=Me)
def update_me(body: UpdateMe, caller: CallerDep, conn: ConnDep) -> Me:
    """Change the caller's display name (Settings). Blank clears it."""
    name = (body.display_name or "").strip() or None
    with conn.cursor() as cur:
        cur.execute(UPDATE_DISPLAY_NAME_SQL, {"user_id": caller.user_id, "display_name": name})
    conn.commit()
    logger.info("profile renamed user=%s cleared=%s", caller.user_id, name is None)
    return me(caller, conn)
