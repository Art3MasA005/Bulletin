"""Strategy B — query translation. PRD §7.2, "The cross-lingual problem".

The lexical arm contributes *nothing* cross-lingually. An English query and a
Bangla chunk share zero tokens, so `to_tsvector('english')` returns empty and
`pg_trgm` returns empty, and the hybrid search silently degrades to dense
retrieval alone — precisely on the corpus where dense is least reliable,
because legacy-font and vision-read Bangla is the noisiest text we hold.

Strategy B buys the arm back: translate the condensed query into the other
language, run both arms again on the translation, and fuse all four ranked
lists. The cost is one round trip.

`eval/reports/crosslingual_check.md` measured Strategy A's premise and it
holds (top-1 100%, margin +0.39 on clean sentence pairs), so this module is
not a rescue — it is the other half of Ablation A. Clean pairs say nothing
about noisy chunks, which is exactly the hypothesis PRD §7.2 asks us to test
rather than assume.

WHAT THIS MODULE REFUSES TO DO

A wrong translation is worse than no translation: it adds a plausible ranked
list built from a question the user never asked, and RRF has no way to know
one arm is lying. So a candidate translation is rejected — falling back to
Strategy A for that query — unless it is short, single-line, actually in the
target language, and still carries every course code the original had.

That last check is the one that matters here. Asked to translate
"CSE 3103 exam date" into Bangla, a model may reasonably return
"সিএসই ৩১০৩ পরীক্ষার তারিখ": correct Bangla, and a destroyed query. Bangla
digits fold back to ASCII in `normalize_for_match`, but `সিএসই` never folds
to `CSE`, so the code no longer matches a routine that prints it in Latin —
and nothing downstream raises. It just retrieves the wrong course.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from app.bangla.normalize import detect_lang
from app.providers.base import Message, Provider, ProviderError

logger = logging.getLogger(__name__)

# A translated query is a query. Anything longer is the model having answered,
# explained, or offered alternatives -- the same failure condense.py guards.
MAX_TRANSLATED_CHARS = 300

# Course codes as they appear inside free text, not anchored like
# `attachments.schemas.COURSE_CODE_RE`, which validates a whole extracted
# field. Here we are scanning a sentence for codes that must survive.
COURSE_CODE_IN_TEXT = re.compile(r"\b([A-Za-z]{2,5})\s*-?\s*(\d{3,5})\b")

# Short words that precede a year and are not department prefixes. Without
# this, "the Fall 2026 routine" scans as the course code FALL 2026, and every
# correct translation of it — which naturally renders "Fall" in Bangla — is
# rejected for dropping a code that was never there. The failure would be
# invisible: Strategy B would simply stop applying to term-scoped questions,
# which are among the most common ones asked.
#
# Only words of five letters or fewer can reach the regex at all, so
# "summer", "spring", "autumn", "winter", "session" and "semester" need no
# entry here — they are already too long to match.
NOT_A_DEPARTMENT = frozenset(
    {"fall", "term", "batch", "year", "sem", "class", "grade", "level", "phase", "part"}
)

TRANSLATE_SYSTEM = (
    "You translate a search query between English and Bangla.\n\n"
    "Rules:\n"
    "- Translate into {target}. Output the translation only, on one line.\n"
    "- Keep every course code, number, date, and proper noun in its original\n"
    "  script. 'CSE 3103' stays 'CSE 3103'; never write it in Bangla letters\n"
    "  or Bangla digits.\n"
    "- Translate the question. Do NOT answer it, explain it, or add context.\n"
    "- If the text is already in {target}, repeat it unchanged."
)

_TARGET_NAME = {"en": "English", "bn": "Bangla"}


@dataclass(frozen=True)
class TranslatedQuery:
    """One translated variant of a query, and whether it may be used.

    `ok` is the only field callers should branch on. When it is false the
    pipeline runs Strategy A for this question — `reason` says why, and it is
    logged, because a strategy that quietly stops applying would make Ablation
    A report a Strategy B that never ran.
    """

    text: str
    lang: str
    source_lang: str
    ok: bool
    reason: str


def target_lang_for(lang: str) -> str:
    """The language a query should be translated *into*.

    `mixed` targets English. A mixed query — "CSE 4101 এর ফাইনাল কবে" — is
    already the best-served case: its Bangla tokens reach Bangla chunks
    through pg_trgm and its ASCII course code reaches English chunks through
    tsvector. What it cannot reach is English *prose*, so English is the
    variant worth paying a round trip for.
    """
    return "en" if lang in ("bn", "mixed") else "bn"


def course_codes(text: str) -> set[str]:
    """Course codes in `text`, normalized to `DEPT NNNN` for comparison.

    Deliberately conservative: a missed code costs one rejected translation,
    a false one costs every translation of a question that mentions a term.
    """
    return {
        f"{match.group(1).upper()} {match.group(2)}"
        for match in COURSE_CODE_IN_TEXT.finditer(text)
        if match.group(1).lower() not in NOT_A_DEPARTMENT
    }


def _looks_like_a_translation(candidate: str, source: str, target: str) -> tuple[bool, str]:
    """Whether the model returned a usable query in the target language."""
    stripped = candidate.strip()
    if not stripped:
        return False, "translator returned empty"
    if len(stripped) > MAX_TRANSLATED_CHARS:
        return False, f"translator returned {len(stripped)} chars; looks like an answer"
    if "\n" in stripped:
        return False, "translator returned multiple lines"

    detected = detect_lang(stripped)
    # `mixed` is accepted on purpose: a correct Bangla translation that keeps
    # "CSE 3103" in Latin *is* mixed, and rejecting it would reject exactly the
    # behaviour the prompt asks for.
    if detected != target and detected != "mixed":
        return False, f"translator returned {detected}, expected {target}"

    lost = course_codes(source) - course_codes(stripped)
    if lost:
        # The silent killer. See the module docstring.
        return False, f"translator dropped course codes: {sorted(lost)}"

    return True, "ok"


def translate(
    query: str,
    *,
    provider: Provider | None,
    source_lang: str | None = None,
    target: str | None = None,
) -> TranslatedQuery:
    """Translate a condensed query into the other language.

    Never raises. A provider failure, a refused translation, or a missing
    provider all return `ok=False`, and the caller falls back to Strategy A.
    Losing the second arm pair is a degraded search; a 500 is no search.
    """
    text = (query or "").strip()
    source = source_lang or detect_lang(text)
    target = target or target_lang_for(source)

    if not text:
        return TranslatedQuery("", target, source, ok=False, reason="empty query")
    if provider is None:
        return TranslatedQuery("", target, source, ok=False, reason="no provider")
    if source == target:
        # Nothing to buy back: both arms already run in this language.
        return TranslatedQuery(text, source, source, ok=False, reason="already in target")

    messages = [
        Message(role="system", content=TRANSLATE_SYSTEM.format(target=_TARGET_NAME[target])),
        Message(role="user", content=text),
    ]

    try:
        candidate = "".join(provider.generate(messages, stream=False)).strip()
    except ProviderError as exc:
        logger.warning("query translation failed, falling back to Strategy A: %s", exc)
        return TranslatedQuery("", target, source, ok=False, reason=f"error: {exc}")

    ok, reason = _looks_like_a_translation(candidate, text, target)
    if not ok:
        logger.warning("query translation rejected (%s), falling back to Strategy A", reason)
        return TranslatedQuery("", target, source, ok=False, reason=reason)

    logger.info("translated query %s -> %s (%d chars)", source, target, len(candidate))
    # The variant is tagged with its TARGET language, not its detected one: a
    # Bangla translation carrying a Latin course code detects as `mixed`, and
    # the lexical arm must still pick the Bangla index for it.
    return TranslatedQuery(candidate, target, source, ok=True, reason="translated")
