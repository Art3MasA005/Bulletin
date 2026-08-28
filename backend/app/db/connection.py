"""One place that opens a Postgres connection.

`psycopg` is imported inside the function, not at module import: most of the
backend (extraction, chunking, the Bangla pipeline, every unit test) runs with
no database at all, and a top-level import would make a driver a hard
dependency of code that never touches one.

The DSN carries a password. It is read through `settings.require`, which
unwraps the SecretStr, and is never logged -- `describe()` exists so a CLI can
print where it is connecting without printing the credentials.
"""

from __future__ import annotations

import logging
from urllib.parse import urlsplit

from app.config import ConfigError, Settings, get_settings

logger = logging.getLogger(__name__)

MISSING_DSN_HELP = (
    "Supabase dashboard -> Settings -> Database -> Connection string -> URI.\n"
    "Use the pooled connection string if your host blocks direct 5432."
)


def dsn(settings: Settings | None = None) -> str:
    """The database URL, or a ConfigError naming the env var and where to find it.

    Also rejects a DSN that cannot be parsed. The usual cause is a password
    pasted straight out of the Supabase dashboard containing one of
    `@ : / ? # %`, which makes the rest of the string mean something else --
    and the failure surfaces as an unrelated-looking parse error somewhere far
    away unless it is caught here.
    """
    settings = settings or get_settings()
    try:
        value = settings.require("database_url")
    except ConfigError as exc:
        raise ConfigError(f"{exc}\n\n{MISSING_DSN_HELP}") from exc

    try:
        _ = urlsplit(value).port  # raises on a password that broke the URL shape
    except ValueError as exc:
        raise ConfigError(
            "BULLETIN_DATABASE_URL cannot be parsed as a URL. If the database "
            "password contains any of  @ : / ? # %  it must be percent-encoded "
            "(@ becomes %40, # becomes %23, / becomes %2F, % becomes %25), or "
            "reset the password to letters and digits only.\n\n"
            f"{MISSING_DSN_HELP}"
        ) from exc
    return value


def describe(settings: Settings | None = None) -> str:
    """host:port/database, with the credentials removed. Safe to log and print."""
    try:
        parts = urlsplit(dsn(settings))
        host = parts.hostname or "?"
        port = f":{parts.port}" if parts.port else ""
    except (ConfigError, ValueError):
        # Never raise from a describe() used inside a log line -- the caller is
        # already reporting a problem and this must not become the exception.
        return "<unparseable>"
    return f"{host}{port}{parts.path}"


def connect(settings: Settings | None = None, *, autocommit: bool = False):
    """Open a psycopg connection. The caller owns it -- use it as a context manager."""
    import psycopg

    settings = settings or get_settings()
    logger.info("connecting to %s autocommit=%s", describe(settings), autocommit)
    return psycopg.connect(dsn(settings), autocommit=autocommit)


def make_pool(settings: Settings | None = None, *, min_size: int = 1, max_size: int = 4):
    """A connection pool for the API process.

    The database is a pooler in another region, so a fresh TLS handshake costs
    more than most queries do. `open=False` because the pool is opened inside
    the app lifespan: a pool that dials the database at import time turns a
    misconfigured `.env` into an import error rather than a startup error with
    a readable message.
    """
    from psycopg_pool import ConnectionPool

    settings = settings or get_settings()
    return ConnectionPool(
        conninfo=dsn(settings),
        min_size=min_size,
        max_size=max_size,
        open=False,
        name="bulletin",
    )
