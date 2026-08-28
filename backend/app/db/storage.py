"""Supabase Storage, over its REST API. PRD 6, 8.4.

Two buckets, deliberately separate:

  documents    institutional publications, permanent, admin-uploaded
  attachments  student uploads, PRIVATE, deleted after
               BULLETIN_ATTACHMENT_IMAGE_TTL_DAYS (PRD 8.4)

Both are created private. A public attachments bucket would put a student's
routine -- name, student ID, schedule -- behind a guessable URL with no
authentication at all, which no amount of RLS elsewhere would undo.

The service key is used here and only here on the storage path. It bypasses
RLS by design, so every call in this module takes an explicit path built from
the caller's own user id; there is no "list everything" helper.
"""

from __future__ import annotations

import logging
import uuid
from pathlib import PurePosixPath

import httpx

from app.config import ConfigError, Settings, get_settings

logger = logging.getLogger(__name__)

DOCUMENTS_BUCKET = "documents"
ATTACHMENTS_BUCKET = "attachments"

_TIMEOUT = httpx.Timeout(connect=10.0, read=60.0, write=120.0, pool=10.0)


class StorageError(RuntimeError):
    """A storage call failed. Carries the status for the caller to map."""

    def __init__(self, message: str, *, status: int | None = None):
        super().__init__(message)
        self.status = status


def _base(settings: Settings) -> str:
    base = settings.supabase_base_url
    if not base:
        raise ConfigError("BULLETIN_SUPABASE_URL is not set; storage is unavailable")
    return f"{base}/storage/v1"


def _headers(settings: Settings) -> dict[str, str]:
    key = settings.require("supabase_service_key")
    return {"apikey": key, "Authorization": f"Bearer {key}"}


def object_path(*, user_id: str, filename: str, prefix: str = "") -> str:
    """A storage path that cannot collide and cannot be guessed.

    Scoped by user id so a stray policy mistake still cannot serve one
    student's routine from another student's prefix, and suffixed with a uuid
    so two photos named IMG_0001.jpg do not overwrite each other.
    """
    suffix = PurePosixPath(filename).suffix.lower() or ".bin"
    name = f"{uuid.uuid4().hex}{suffix}"
    parts = [p for p in (prefix, user_id, name) if p]
    return "/".join(parts)


def ensure_buckets(settings: Settings | None = None) -> dict[str, str]:
    """Create both buckets if they are missing. Idempotent; safe to re-run."""
    settings = settings or get_settings()
    results: dict[str, str] = {}
    with httpx.Client(timeout=_TIMEOUT, headers=_headers(settings)) as client:
        for bucket in (DOCUMENTS_BUCKET, ATTACHMENTS_BUCKET):
            response = client.post(
                f"{_base(settings)}/bucket",
                json={"id": bucket, "name": bucket, "public": False},
            )
            if response.status_code in (200, 201):
                results[bucket] = "created"
            elif response.status_code == 409:
                results[bucket] = "already exists"
            else:
                raise StorageError(
                    f"could not create bucket {bucket}: "
                    f"{response.status_code} {response.text[:200]}",
                    status=response.status_code,
                )
    logger.info("buckets: %s", results)
    return results


def upload(
    *,
    bucket: str,
    path: str,
    content: bytes,
    content_type: str,
    settings: Settings | None = None,
) -> str:
    """Store bytes and return the object path. Never overwrites."""
    settings = settings or get_settings()
    headers = _headers(settings) | {"Content-Type": content_type, "x-upsert": "false"}
    with httpx.Client(timeout=_TIMEOUT) as client:
        response = client.post(
            f"{_base(settings)}/object/{bucket}/{path}", content=content, headers=headers
        )
    if response.status_code not in (200, 201):
        raise StorageError(
            f"upload to {bucket}/{path} failed: {response.status_code} {response.text[:200]}",
            status=response.status_code,
        )
    logger.info("stored %s/%s bytes=%d", bucket, path, len(content))
    return path


def signed_url(
    *, bucket: str, path: str, expires_in: int = 3600, settings: Settings | None = None
) -> str:
    """A time-limited URL for one object.

    How a private bucket is read by a client: the backend authorises the
    request, then hands back a URL that expires. No object is ever public.
    """
    settings = settings or get_settings()
    with httpx.Client(timeout=_TIMEOUT, headers=_headers(settings)) as client:
        response = client.post(
            f"{_base(settings)}/object/sign/{bucket}/{path}", json={"expiresIn": expires_in}
        )
    if response.status_code != 200:
        raise StorageError(
            f"could not sign {bucket}/{path}: {response.status_code}",
            status=response.status_code,
        )
    return f"{settings.supabase_base_url}/storage/v1{response.json()['signedURL']}"


def remove(*, bucket: str, paths: list[str], settings: Settings | None = None) -> int:
    """Delete objects. Returns how many the server reported removing."""
    if not paths:
        return 0
    settings = settings or get_settings()
    with httpx.Client(timeout=_TIMEOUT, headers=_headers(settings)) as client:
        response = client.request(
            "DELETE", f"{_base(settings)}/object/{bucket}", json={"prefixes": paths}
        )
    if response.status_code != 200:
        raise StorageError(
            f"delete from {bucket} failed: {response.status_code} {response.text[:200]}",
            status=response.status_code,
        )
    removed = len(response.json() or [])
    logger.info("deleted %d object(s) from %s", removed, bucket)
    return removed
