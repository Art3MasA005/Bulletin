"""OpenRouter provider.

CLAUDE.md warning #10: `data_collection: "deny"` on EVERY request. This product
handles institutional records and student personal documents (names, student
IDs, schedules). The setting is applied in one place -- `_payload` -- so no
call site can forget it, and a test asserts it.

Model ids come from config and are never defaulted in code. A stale guess fails
as an opaque 400 at request time; an unset id fails immediately with the name
of the env var to set.
"""

from __future__ import annotations

import base64
import json
import logging
import time
from collections.abc import Iterator, Sequence
from typing import Any, TypeVar

import httpx
from pydantic import BaseModel, ValidationError

from app.config import Settings, get_settings
from app.providers.base import (
    Message,
    Provider,
    ProviderError,
    ProviderUnsupported,
    Vector,
)

logger = logging.getLogger(__name__)

T = TypeVar("T", bound=BaseModel)

# Applied to every request body. Do not inline this at a call site.
DATA_COLLECTION_DENY: dict[str, Any] = {"data_collection": "deny"}

DEFAULT_TIMEOUT = httpx.Timeout(connect=10.0, read=180.0, write=30.0, pool=10.0)

# Backoff for retryable failures. The upstream rate limit on a free tier clears
# in seconds, not minutes, so the first wait is short and doubles from there.
RETRY_BASE_SECONDS = 2.0
RETRY_MAX_SECONDS = 30.0

# The table rule is not a formatting preference. Measured on the real corpus
# (2026-08-28): asked only to "preserve table structure", the model transcribed
# an exam routine column by column -- every date, then every slot, then every
# course code -- so the date belonging to a course was no longer recoverable
# from the text. A chunk of that is worse than useless: it retrieves for
# "CSE 101 exam date" and contains no date for CSE 101.
PAGE_READ_PROMPT = (
    "Transcribe all text in this document page exactly as it appears.\n\n"
    "If the page contains a table, output ONE LINE PER ROW, with the cells of "
    "that row separated by ' | ', in the printed left-to-right order. Repeat "
    "the row's date, time, and section values on every line they apply to, so "
    "that each line stands alone and no value depends on a line above it. "
    "Never output a table column by column.\n\n"
    "Preserve the reading order and headings. Bangla text must be transcribed "
    "in Unicode Bangla. Do not translate, summarise, explain, or add "
    "commentary. Output only the transcribed text."
)


class OpenRouterProvider(Provider):
    name = "openrouter"

    def __init__(self, settings: Settings | None = None, client: httpx.Client | None = None):
        self.settings = settings or get_settings()
        self._client = client
        self._owns_client = client is None

    # ── transport ───────────────────────────────────────────────────────────

    @property
    def client(self) -> httpx.Client:
        if self._client is None:
            self._client = httpx.Client(
                base_url=self.settings.openrouter_base_url,
                timeout=DEFAULT_TIMEOUT,
                headers=self._headers(),
            )
        return self._client

    def close(self) -> None:
        if self._client is not None and self._owns_client:
            self._client.close()
            self._client = None

    def __enter__(self) -> OpenRouterProvider:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def _headers(self) -> dict[str, str]:
        key = self.settings.require("openrouter_api_key")
        return {
            "Authorization": f"Bearer {key}",
            "HTTP-Referer": self.settings.app_url,
            "X-Title": self.settings.app_name,
            "Content-Type": "application/json",
        }

    @staticmethod
    def _payload(**fields: Any) -> dict[str, Any]:
        """Build a request body with the privacy setting always attached.

        Single choke point for CLAUDE.md #10. Every request body in this module
        goes through here.
        """
        body = dict(fields)
        provider = dict(body.get("provider") or {})
        provider.update(DATA_COLLECTION_DENY)
        body["provider"] = provider
        return body

    def _post_once(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        try:
            response = self.client.post(path, json=body)
        except httpx.RequestError as exc:
            raise ProviderError(f"OpenRouter request failed: {exc}", retryable=True) from exc

        if response.status_code == 404:
            raise ProviderUnsupported(f"OpenRouter has no endpoint at {path}", status=404)
        if response.status_code >= 400:
            detail = response.text[:400]
            raise ProviderError(
                f"OpenRouter {response.status_code} on {path}: {detail}",
                status=response.status_code,
                retryable=response.status_code in (408, 429, 500, 502, 503, 504),
                retry_after=_retry_after(response),
            )
        return response.json()

    def _post(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        """POST with backoff on retryable failures.

        A free-tier vision run hits "temporarily rate-limited upstream" (429)
        regularly. Without a retry, a whole page of the corpus falls back to
        its broken text layer because of a transient limit -- the page is then
        checkpointed and silently never read again. Backoff is what makes an
        unattended ingest of a 34-page corpus finish.
        """
        attempts = max(1, self.settings.provider_max_retries)
        delay = RETRY_BASE_SECONDS
        for attempt in range(1, attempts + 1):
            try:
                return self._post_once(path, body)
            except ProviderError as exc:
                if not exc.retryable or attempt == attempts:
                    raise
                wait = min(exc.retry_after or delay, RETRY_MAX_SECONDS)
                logger.warning(
                    "retrying %s after %.1fs (attempt %d/%d): %s",
                    path,
                    wait,
                    attempt,
                    attempts,
                    exc,
                )
                time.sleep(wait)
                delay *= 2
        raise ProviderError(f"OpenRouter {path} exhausted {attempts} attempts")

    # ── embeddings ──────────────────────────────────────────────────────────

    def embed(self, texts: Sequence[str]) -> list[Vector]:
        """Embed via OpenRouter's /embeddings.

        PHASE 1 RISK, flagged deliberately: OpenRouter's coverage of an
        embeddings endpoint has historically been thin compared to chat. If
        this raises ProviderUnsupported, switch to the local bge-m3 fallback in
        providers/local.py -- PRD 6 lists it as the designated fallback. Verify
        before building the index, not after.
        """
        if not texts:
            return []
        model = self.settings.require("embedding_model")
        data = self._post("/embeddings", self._payload(model=model, input=list(texts)))
        try:
            rows = sorted(data["data"], key=lambda r: r.get("index", 0))
            vectors = [list(map(float, row["embedding"])) for row in rows]
        except (KeyError, TypeError, ValueError) as exc:
            raise ProviderError(f"unexpected embeddings response shape: {exc}") from exc

        expected = self.settings.embedding_dim
        if vectors and len(vectors[0]) != expected:
            raise ProviderError(
                f"embedding dim {len(vectors[0])} != configured {expected}. "
                "Changing dimensions requires a migration and a full re-index "
                "(CLAUDE.md). Update BULLETIN_EMBEDDING_DIM deliberately."
            )
        return vectors

    # ── reranking ───────────────────────────────────────────────────────────

    def rerank(self, query: str, docs: Sequence[str]) -> list[float]:
        """Not offered by OpenRouter. PRD 6 puts reranking on a local model."""
        raise ProviderUnsupported(
            "OpenRouter does not expose a reranking endpoint. Use "
            "providers/local.py (bge-reranker-v2-m3), or skip reranking and "
            "measure the cost per PRD 6."
        )

    # ── generation ──────────────────────────────────────────────────────────

    def generate(self, messages: Sequence[Message], *, stream: bool = False) -> Iterator[str]:
        model = self.settings.require("generation_model")
        body = self._payload(
            model=model,
            messages=[m.model_dump() for m in messages],
            stream=stream,
        )
        if not stream:
            data = self._post("/chat/completions", body)
            yield _first_choice_text(data)
            return
        yield from self._stream_completion(body)

    def _stream_completion(self, body: dict[str, Any]) -> Iterator[str]:
        """Yield token deltas from an SSE stream."""
        try:
            with self.client.stream("POST", "/chat/completions", json=body) as response:
                if response.status_code >= 400:
                    response.read()
                    raise ProviderError(
                        f"OpenRouter {response.status_code}: {response.text[:400]}",
                        status=response.status_code,
                        retryable=response.status_code in (429, 500, 502, 503, 504),
                    )
                for line in response.iter_lines():
                    if not line or not line.startswith("data:"):
                        continue
                    payload = line[len("data:") :].strip()
                    if payload == "[DONE]":
                        return
                    try:
                        chunk = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                    delta = chunk.get("choices", [{}])[0].get("delta", {}).get("content")
                    if delta:
                        yield delta
        except httpx.RequestError as exc:
            raise ProviderError(f"stream failed: {exc}", retryable=True) from exc

    # ── vision ──────────────────────────────────────────────────────────────

    def read_page_image(self, png_bytes: bytes, *, lang_hint: str = "auto") -> str:
        model = self.settings.require("vision_model")
        prompt = PAGE_READ_PROMPT
        if lang_hint == "bn":
            prompt += " This page is primarily in Bangla."
        elif lang_hint == "en":
            prompt += " This page is primarily in English."

        body = self._payload(
            model=model,
            messages=[_image_message(prompt, png_bytes)],
            temperature=0,
        )
        data = self._post("/chat/completions", body)
        return _first_choice_text(data).strip()

    def extract_structured(self, png_bytes: bytes, schema: type[T], *, prompt: str) -> T:
        """Vision read constrained to a JSON schema.

        Returns a validated model. A response that does not fit the schema is a
        ProviderError, never a silently half-filled object -- the confirmation
        UI depends on per-field confidence being real.
        """
        model = self.settings.require("extraction_model")
        json_schema = schema.model_json_schema()
        body = self._payload(
            model=model,
            messages=[_image_message(prompt, png_bytes)],
            temperature=0,
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": schema.__name__,
                    "strict": True,
                    "schema": json_schema,
                },
            },
        )
        data = self._post("/chat/completions", body)
        raw = _first_choice_text(data).strip()
        raw = _strip_code_fence(raw)
        try:
            return schema.model_validate_json(raw)
        except ValidationError as exc:
            logger.warning("structured extraction did not match schema: %s", exc)
            raise ProviderError(
                f"{schema.__name__} extraction did not match the schema: {exc}"
            ) from exc


# ── helpers ─────────────────────────────────────────────────────────────────


def _retry_after(response: httpx.Response) -> float | None:
    """Seconds from a Retry-After header, when the provider sent one."""
    raw = response.headers.get("retry-after")
    if not raw:
        return None
    try:
        return max(0.0, float(raw))
    except ValueError:
        # The HTTP-date form. Not worth parsing: fall back to our own backoff.
        return None


def _image_message(prompt: str, png_bytes: bytes) -> dict[str, Any]:
    encoded = base64.b64encode(png_bytes).decode("ascii")
    return {
        "role": "user",
        "content": [
            {"type": "text", "text": prompt},
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{encoded}"},
            },
        ],
    }


def _first_choice_text(data: dict[str, Any]) -> str:
    try:
        content = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise ProviderError(f"unexpected completion response shape: {exc}") from exc
    if isinstance(content, list):  # some models return content parts
        return "".join(part.get("text", "") for part in content if isinstance(part, dict))
    return content or ""


def _strip_code_fence(text: str) -> str:
    """Models wrap JSON in ``` fences often enough to handle it here."""
    stripped = text.strip()
    if not stripped.startswith("```"):
        return stripped
    lines = stripped.splitlines()
    if lines and lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    return "\n".join(lines).strip()
