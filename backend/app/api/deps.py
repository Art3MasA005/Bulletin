"""Request-scoped dependencies: settings, database connection, caller.

FastAPI dependencies only. No business logic here and none in the routes --
CLAUDE.md: "No business logic in route handlers -- parse, delegate, serialize."
"""

from __future__ import annotations

import logging
from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request, status

from app.api.auth import AuthError, Caller, bearer_token, caller_from_token
from app.config import Settings, get_settings
from app.providers.base import Provider

logger = logging.getLogger(__name__)


def settings_dep() -> Settings:
    return get_settings()


SettingsDep = Annotated[Settings, Depends(settings_dep)]


def db_connection(request: Request) -> Iterator:
    """A pooled connection for the life of one request."""
    pool = getattr(request.app.state, "pool", None)
    if pool is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database is not configured",
        )
    with pool.connection() as conn:
        yield conn


ConnDep = Annotated[object, Depends(db_connection)]


def provider_dep(request: Request) -> Provider:
    provider = getattr(request.app.state, "provider", None)
    if provider is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="model provider is not configured",
        )
    return provider


ProviderDep = Annotated[Provider, Depends(provider_dep)]


def current_caller(
    conn: ConnDep,
    settings: SettingsDep,
    authorization: Annotated[str | None, Header()] = None,
) -> Caller:
    """Authenticate the request. 401 on every failure, with a usable reason.

    Note what this returns: an identity resolved against `profiles`, not the
    token's claims. Role and institution are never taken from the token
    (app/api/auth.py explains why).
    """
    try:
        token = bearer_token(authorization)
        return caller_from_token(conn, token, settings)
    except AuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


CallerDep = Annotated[Caller, Depends(current_caller)]
