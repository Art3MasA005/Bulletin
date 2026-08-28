"""FastAPI application. PRD 6, TASKS Phase 2.

    make dev   ->   uvicorn app.main:app --reload --port 8000

Two things are set up once, at startup, and shared by every request: the
database connection pool and the model provider. Both are expensive to create
(a TLS handshake to another region; an HTTP client with keep-alive) and neither
holds request state.

Startup does not fail when the database is unreachable. A free-tier Supabase
project pauses after inactivity and a free host cold-starts (PRD §6), so a
process that refuses to boot without a database is a process that stays down
after a nap. `/health` reports the truth instead, and requests that need the
database return 503 with a reason.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.attachments import router as attachments_router
from app.api.chat import router as chat_router
from app.api.documents import router as documents_router
from app.api.history import router as history_router
from app.api.institutions import router as institutions_router
from app.config import ConfigError, get_settings
from app.db.connection import describe, make_pool

logger = logging.getLogger(__name__)

API_TITLE = "Bulletin"
API_DESCRIPTION = "Cross-lingual RAG over an institution's published documents."


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()

    app.state.pool = None
    app.state.pool_error = None
    try:
        pool = make_pool(settings)
        pool.open(wait=True, timeout=15)
        app.state.pool = pool
        logger.info("database pool open: %s", describe(settings))
    except (ConfigError, OSError, RuntimeError) as exc:
        # Not fatal: /health says so, and the routes that need it return 503.
        app.state.pool_error = str(exc)
        logger.error("database pool unavailable: %s", exc)

    from app.providers.openrouter import OpenRouterProvider

    app.state.provider = OpenRouterProvider(settings)

    try:
        yield
    finally:
        if app.state.pool is not None:
            app.state.pool.close()
        app.state.provider.close()
        logger.info("shutdown complete")


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title=API_TITLE, description=API_DESCRIPTION, lifespan=lifespan)

    # The Flutter client is not a browser, so CORS matters only for a web
    # build and for local tooling. Credentials are never cookie-based here --
    # the client sends a bearer token -- so no wildcard-with-credentials trap.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )

    @app.get("/health", tags=["ops"])
    def health() -> dict[str, object]:
        """Liveness plus the two dependencies that actually matter.

        Reports rather than raises: a demo needs to know WHICH part is asleep.
        """
        pool = getattr(app.state, "pool", None)
        database: dict[str, object] = {"configured": bool(settings.database_url)}
        if pool is None:
            database["status"] = "unavailable"
            database["detail"] = getattr(app.state, "pool_error", None)
        else:
            database["status"] = "ok"
            database["target"] = describe(settings)

        return {
            "status": "ok",
            "database": database,
            "models": {
                "generation": settings.generation_model or None,
                "embedding": settings.embedding_model or None,
                "vision": settings.vision_model or None,
            },
            "auth": {
                "supabase_url": bool(settings.supabase_url),
                "mode": "hs256" if settings.supabase_jwt_secret.get_secret_value() else "jwks",
            },
        }

    app.include_router(chat_router)
    app.include_router(attachments_router)
    app.include_router(institutions_router)
    app.include_router(documents_router)
    app.include_router(history_router)
    return app


app = create_app()
