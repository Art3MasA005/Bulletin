"""Supabase JWT -> caller identity. PRD 4, TASKS Phase 2.

Every request that touches institutional content resolves to three facts:
`user_id`, `institution_id`, and `role`. Two of them come from the database,
never from the token:

    the token proves WHO you are
    the profiles table decides WHAT you may see

A token carries whatever claims the issuer put there, and Supabase lets a
client write to `user_metadata`. If `role` were read from the token, a student
could set their own metadata role to `admin` and the audience filter would
happily widen (CLAUDE.md #4). So the token is used only for `sub`, and the
role and institution are read from `profiles` on every request.

Verification uses the project JWKS (ES256/RS256). The legacy HS256 path is
supported when `BULLETIN_SUPABASE_JWT_SECRET` is set, because projects created
before the asymmetric keys rollout still sign that way.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import timedelta

import httpx
import jwt
from jwt import PyJWKClient

from app.config import Settings, get_settings
from app.retrieve.audience import Role, UnknownRole

logger = logging.getLogger(__name__)

# Supabase issues access tokens with this audience by default.
DEFAULT_AUDIENCE = "authenticated"

# JWKS is fetched once and cached; a rotated key is picked up on cache expiry.
_JWKS_TTL_SECONDS = 600

# Tolerance for clock skew between Supabase (which stamps `iat`/`nbf`) and this
# server. Measured, not guessed: with zero leeway, a freshly minted token was
# rejected on an Android emulator with "The token is not yet valid (iat)" --
# the issuer's clock was a few seconds ahead of the host's. Sixty seconds is
# the usual allowance; it widens the window a stolen-and-replayed token is
# valid in by a minute, against an `exp` measured in hours.
CLOCK_SKEW_LEEWAY = timedelta(seconds=60)


class AuthError(Exception):
    """The caller could not be authenticated. Always a 401, never a 500.

    The message is safe to return: it says what was wrong with the request,
    never whether a given user or institution exists.
    """


@dataclass(frozen=True)
class Caller:
    """The authenticated caller, as every downstream module needs them."""

    user_id: str
    institution_id: str
    role: Role
    email: str | None = None

    @property
    def is_admin(self) -> bool:
        return self.role is Role.ADMIN


class _JWKSCache:
    """One PyJWKClient per issuer, refreshed on a TTL."""

    def __init__(self) -> None:
        self._clients: dict[str, tuple[float, PyJWKClient]] = {}

    def client(self, jwks_url: str) -> PyJWKClient:
        now = time.monotonic()
        cached = self._clients.get(jwks_url)
        if cached and now - cached[0] < _JWKS_TTL_SECONDS:
            return cached[1]
        client = PyJWKClient(jwks_url, cache_keys=True)
        self._clients[jwks_url] = (now, client)
        return client

    def clear(self) -> None:
        self._clients.clear()


_jwks = _JWKSCache()


def jwks_url(settings: Settings) -> str:
    base = settings.supabase_base_url
    if not base:
        raise AuthError("BULLETIN_SUPABASE_URL is not configured")
    return f"{base}/auth/v1/.well-known/jwks.json"


def decode_token(token: str, settings: Settings | None = None) -> dict[str, object]:
    """Verify a Supabase access token and return its claims.

    Signature, expiry, and audience are all checked. An unverified decode is
    never performed -- `verify_signature=False` anywhere in this file would
    make every other control in the system decorative.
    """
    settings = settings or get_settings()
    secret = settings.supabase_jwt_secret.get_secret_value()

    try:
        if secret:
            # Legacy symmetric project keys.
            return jwt.decode(
                token,
                secret,
                algorithms=["HS256"],
                audience=DEFAULT_AUDIENCE,
                leeway=CLOCK_SKEW_LEEWAY,
                options={"require": ["exp", "sub"]},
            )
        signing_key = _jwks.client(jwks_url(settings)).get_signing_key_from_jwt(token)
        return jwt.decode(
            token,
            signing_key.key,
            algorithms=["ES256", "RS256"],
            audience=DEFAULT_AUDIENCE,
            leeway=CLOCK_SKEW_LEEWAY,
            options={"require": ["exp", "sub"]},
        )
    except jwt.ImmatureSignatureError as exc:
        # More skew than the leeway allows. Naming the clock is the difference
        # between a five-minute fix and an afternoon of debugging auth.
        logger.warning("token not yet valid; check the server clock: %s", exc)
        raise AuthError(
            "this device's clock is out of step with the server; check the time settings"
        ) from exc
    except jwt.ExpiredSignatureError as exc:
        raise AuthError("session expired; sign in again") from exc
    except jwt.InvalidAudienceError as exc:
        raise AuthError("token audience is not 'authenticated'") from exc
    except jwt.PyJWTError as exc:
        logger.warning("token rejected: %s", exc)
        raise AuthError("invalid access token") from exc
    except (httpx.HTTPError, OSError) as exc:
        # A JWKS fetch failure is an outage, not a bad token. Say so plainly
        # rather than telling a legitimate user their session is invalid.
        logger.error("JWKS unavailable: %s", exc)
        raise AuthError("cannot verify the session right now; try again") from exc


PROFILE_SQL = """
select p.id::text, p.institution_id::text, p.role::text, p.email
from profiles p
where p.id = %(user_id)s
"""


def load_profile(conn, user_id: str) -> Caller:
    """Read role and institution from the database. Fails closed.

    A signed-in user with no profile row has not joined an institution yet
    (PRD 4: members join by invite code). That is a 401 with a clear reason,
    not a default institution and not a default role.
    """
    with conn.cursor() as cur:
        cur.execute(PROFILE_SQL, {"user_id": user_id})
        row = cur.fetchone()

    if row is None:
        raise AuthError("this account has not joined an institution yet")

    try:
        role = Role(row[2])
    except (ValueError, UnknownRole) as exc:
        # An unrecognised role must never widen access by defaulting.
        logger.error("profile %s has unknown role %r", user_id, row[2])
        raise AuthError("account role is not recognised; contact the office") from exc

    return Caller(user_id=row[0], institution_id=row[1], role=role, email=row[3])


def caller_from_token(conn, token: str, settings: Settings | None = None) -> Caller:
    """The full path: verify the token, then read the profile it points at."""
    claims = decode_token(token, settings)
    user_id = str(claims.get("sub") or "")
    if not user_id:
        raise AuthError("token has no subject")
    caller = load_profile(conn, user_id)
    logger.info(
        "authenticated user=%s institution=%s role=%s",
        caller.user_id,
        caller.institution_id,
        caller.role,
    )
    return caller


def bearer_token(header: str | None) -> str:
    """Extract the token from an Authorization header, or raise AuthError."""
    if not header:
        raise AuthError("missing Authorization header")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise AuthError("Authorization header must be 'Bearer <token>'")
    return token.strip()
