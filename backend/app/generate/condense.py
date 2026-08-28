"""Question + recent history -> one standalone query. PRD 7.2 steps 1-3.

"When is it?" retrieves nothing. "When is the Summer 2026 final exam?"
retrieves the routine. Condensing is what makes a follow-up question work at
all, and it runs before language detection because the pronoun-only question
often carries no language signal of its own.

Two things this module is careful about:

  * **No history, no LLM call.** The first question in a conversation is
    already standalone. Condensing it would spend a round trip to rewrite a
    sentence that needed no rewriting -- and would risk changing it.

  * **The rewrite is never trusted blindly.** A condenser that answers the
    question instead of rewriting it, or returns an empty string, or emits a
    paragraph, falls back to the raw question. A bad rewrite is worse than no
    rewrite: it silently retrieves for a question the user never asked.

Normalization is symmetric with ingestion by construction -- this module
returns text and the retrieval arms call normalize_for_match on it, the same
function chunk.py used (CLAUDE.md #6).
"""

from __future__ import annotations

import logging
from collections.abc import Sequence
from dataclasses import dataclass

from app.bangla.normalize import detect_lang, normalize
from app.providers.base import Message, Provider, ProviderError

logger = logging.getLogger(__name__)

# A standalone query is a question, not an essay. Anything longer than this is
# the model having answered, explained, or hallucinated context.
MAX_CONDENSED_CHARS = 300

CONDENSE_SYSTEM = (
    "You rewrite a follow-up question into a standalone search query.\n\n"
    "Rules:\n"
    "- Resolve pronouns and ellipsis using the conversation history.\n"
    "- Keep the original language. A Bangla question stays Bangla.\n"
    "- Keep every course code, date, and proper noun exactly as written.\n"
    "- Do NOT answer the question. Do not add information. Do not explain.\n"
    "- Output the rewritten question only, on one line."
)


@dataclass(frozen=True)
class CondensedQuery:
    """The query retrieval will actually run, and where it came from."""

    text: str
    lang: str
    rewritten: bool
    reason: str

    @property
    def normalized(self) -> str:
        """Normalized form, for logging and for callers that need it directly."""
        return normalize(self.text)


def _history_block(history: Sequence[Message], turns: int) -> list[Message]:
    """The last `turns` message pairs, oldest first."""
    return list(history)[-(turns * 2) :]


def _looks_like_a_rewrite(candidate: str, question: str) -> tuple[bool, str]:
    """Whether the model returned a query rather than an answer."""
    stripped = candidate.strip()
    if not stripped:
        return False, "condenser returned empty"
    if len(stripped) > MAX_CONDENSED_CHARS:
        return False, f"condenser returned {len(stripped)} chars; looks like an answer"
    if "\n" in stripped.strip():
        return False, "condenser returned multiple lines"
    if detect_lang(stripped) != detect_lang(question) and detect_lang(question) != "mixed":
        return False, "condenser changed the language of the question"
    return True, "ok"


def condense(
    question: str,
    history: Sequence[Message] | None = None,
    *,
    provider: Provider | None = None,
    turns: int = 3,
) -> CondensedQuery:
    """Return the standalone query for this question.

    With no history -- or no provider -- the question is returned unchanged.
    That is the common case and it costs nothing.
    """
    question = (question or "").strip()
    lang = detect_lang(question)

    if not history:
        return CondensedQuery(text=question, lang=lang, rewritten=False, reason="no history")
    if provider is None:
        return CondensedQuery(text=question, lang=lang, rewritten=False, reason="no provider")

    messages = [
        Message(role="system", content=CONDENSE_SYSTEM),
        *_history_block(history, turns),
        Message(role="user", content=question),
    ]

    try:
        candidate = "".join(provider.generate(messages, stream=False)).strip()
    except ProviderError as exc:
        logger.warning("condense failed, using the raw question: %s", exc)
        return CondensedQuery(text=question, lang=lang, rewritten=False, reason=f"error: {exc}")

    ok, reason = _looks_like_a_rewrite(candidate, question)
    if not ok:
        logger.warning("condense rejected (%s), using the raw question", reason)
        return CondensedQuery(text=question, lang=lang, rewritten=False, reason=reason)

    condensed = candidate.strip()
    logger.info(
        "condensed lang=%s turns=%d in=%d chars out=%d chars",
        lang,
        turns,
        len(question),
        len(condensed),
    )
    # Language is re-detected on the rewrite: "CSE 4101 কবে" condensed against
    # English history can come back as English, and the answer must follow the
    # query that actually runs.
    return CondensedQuery(
        text=condensed, lang=detect_lang(condensed), rewritten=True, reason="rewritten"
    )
