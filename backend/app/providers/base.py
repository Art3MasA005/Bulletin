"""The provider interface. PRD 6.

CLAUDE.md: "Model access only through providers/base.py. Never call OpenRouter
directly from a pipeline module." Pipeline code depends on this protocol, never
on a vendor SDK, which is what makes the local-model fallback in providers/
local.py a config change rather than a rewrite.

    embed(texts)                     -> list[Vector]
    rerank(query, docs)              -> list[float]
    generate(messages, stream)       -> Iterator[str]
    read_page_image(png_bytes)       -> str
    extract_structured(png, schema)  -> BaseModel
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Iterator, Sequence
from typing import TypeVar

from pydantic import BaseModel

Vector = list[float]
T = TypeVar("T", bound=BaseModel)


class ProviderError(RuntimeError):
    """A provider call failed. Carries enough context to log and to escalate."""

    def __init__(
        self,
        message: str,
        *,
        status: int | None = None,
        retryable: bool = False,
        retry_after: float | None = None,
    ):
        super().__init__(message)
        self.status = status
        self.retryable = retryable
        # Seconds the provider asked us to wait, when it said so (Retry-After).
        self.retry_after = retry_after


class ProviderUnsupported(ProviderError):
    """This provider does not offer the capability.

    Not a bug and not a crash: the caller falls back. PRD 6 pairs every
    capability with a fallback, and reranking is allowed to be skipped
    entirely provided the cost is measured.
    """


class Message(BaseModel):
    role: str  # "system" | "user" | "assistant"
    content: str


class Provider(ABC):
    """Every model capability the product needs, and nothing else."""

    name: str = "provider"

    @abstractmethod
    def embed(self, texts: Sequence[str]) -> list[Vector]:
        """Embed texts for the dense arm. Order of results matches input."""

    @abstractmethod
    def rerank(self, query: str, docs: Sequence[str]) -> list[float]:
        """Cross-encoder relevance scores, one per doc, same order."""

    @abstractmethod
    def generate(self, messages: Sequence[Message], *, stream: bool = False) -> Iterator[str]:
        """Yield answer text. With stream=False, yields exactly one chunk."""

    @abstractmethod
    def read_page_image(self, png_bytes: bytes, *, lang_hint: str = "auto") -> str:
        """Read a rendered page image and return its text.

        The escape hatch for legacy fonts (PRD 7.1): the encoding problem lives
        only in the text layer, so a model reading the rendered page gets
        correct Unicode.
        """

    @abstractmethod
    def extract_structured(self, png_bytes: bytes, schema: type[T], *, prompt: str) -> T:
        """Read an image into a typed schema.

        Used for chat attachments (PRD 8.2). Structured per-field extraction,
        not table-as-text, because grid misalignment is the characteristic
        vision failure on a routine.
        """
