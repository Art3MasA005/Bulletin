"""Strategy B — query translation. PRD §7.2, TASKS.md Phase 1.

The tests that matter here are the rejections. A translation that is merely
mediocre still helps: RRF fuses four ranked lists and a weak one contributes
little. A translation that is *wrong* — a different question, an answer, a
course code rewritten in Bangla letters — contributes a confident ranked list
built from something the user never asked, and nothing downstream can tell.

So every rejection path has a test, and each one names the failure it prevents.
"""

from __future__ import annotations

from collections.abc import Iterator, Sequence

from app.providers.base import Message, Provider, ProviderError, ProviderUnsupported, Vector
from app.retrieve.translate_query import (
    MAX_TRANSLATED_CHARS,
    course_codes,
    target_lang_for,
    translate,
)


class _Stub(Provider):
    """A provider that returns a scripted translation and records the prompt."""

    name = "stub"

    def __init__(self, reply: str = "ok", *, fail: bool = False) -> None:
        self.reply = reply
        self.fail = fail
        self.calls: list[list[Message]] = []

    def embed(self, texts: Sequence[str]) -> list[Vector]:  # pragma: no cover
        raise ProviderUnsupported("embed")

    def rerank(self, query: str, docs: Sequence[str]) -> list[float]:  # pragma: no cover
        raise ProviderUnsupported("rerank")

    def generate(self, messages: Sequence[Message], *, stream: bool = False) -> Iterator[str]:
        self.calls.append(list(messages))
        if self.fail:
            raise ProviderError("upstream 502", status=502, retryable=True)
        yield self.reply

    def read_page_image(self, png_bytes: bytes, *, lang_hint: str = "auto") -> str:
        raise ProviderUnsupported("vision")  # pragma: no cover

    def extract_structured(self, png_bytes: bytes, schema, *, prompt: str):
        raise ProviderUnsupported("structured")  # pragma: no cover


# ── which direction to translate ────────────────────────────────────────────


def test_english_translates_to_bangla() -> None:
    assert target_lang_for("en") == "bn"


def test_bangla_translates_to_english() -> None:
    assert target_lang_for("bn") == "en"


def test_mixed_translates_to_english() -> None:
    """A mixed query already reaches Bangla chunks through pg_trgm.

    What it cannot reach is English prose, so English is the variant worth one
    round trip.
    """
    assert target_lang_for("mixed") == "en"


# ── the happy path ──────────────────────────────────────────────────────────


def test_an_english_query_comes_back_in_bangla() -> None:
    stub = _Stub("চূড়ান্ত পরীক্ষা কখন শুরু হবে?")
    result = translate("When do the final examinations start?", provider=stub)

    assert result.ok
    assert result.lang == "bn"
    assert result.source_lang == "en"
    assert result.text == "চূড়ান্ত পরীক্ষা কখন শুরু হবে?"


def test_a_bangla_query_comes_back_in_english() -> None:
    stub = _Stub("When do the final examinations start?")
    result = translate("চূড়ান্ত পরীক্ষা কখন শুরু হবে?", provider=stub)

    assert result.ok
    assert result.lang == "en"
    assert result.source_lang == "bn"


def test_the_prompt_names_the_target_language() -> None:
    stub = _Stub("চূড়ান্ত পরীক্ষা কখন?")
    translate("when is the final exam", provider=stub)

    system = stub.calls[0][0].content
    assert "Bangla" in system
    assert "CSE 3103" in system  # the code-preservation rule is in the prompt


def test_a_translation_carrying_a_latin_course_code_is_accepted() -> None:
    """The correct answer detects as `mixed`, and must not be rejected for it.

    "CSE 3103 এর পরীক্ষা কবে" is exactly what the prompt asks for: Bangla
    prose, Latin code. A target check of `detected == "bn"` would throw away
    every well-formed translation of a course-code question.
    """
    stub = _Stub("CSE 3103 এর পরীক্ষা কবে?")
    result = translate("When is the CSE 3103 exam?", provider=stub)

    assert result.ok
    assert result.lang == "bn"  # tagged by target, not by detection


# ── the rejections ──────────────────────────────────────────────────────────


def test_a_course_code_written_in_bangla_letters_is_rejected() -> None:
    """The silent killer this module exists to stop.

    `সিএসই ৩১০৩` is a correct Bangla rendering and a destroyed query: Bangla
    digits fold back to ASCII in normalize_for_match, but `সিএসই` never folds
    to `CSE`, so the code stops matching a routine printed in Latin. Nothing
    downstream raises — it just retrieves the wrong course.
    """
    stub = _Stub("সিএসই ৩১০৩ এর পরীক্ষা কবে?")
    result = translate("When is the CSE 3103 exam?", provider=stub)

    assert not result.ok
    assert "dropped course codes" in result.reason
    assert "CSE 3103" in result.reason


def test_a_translation_that_answers_instead_of_translating_is_rejected() -> None:
    stub = _Stub("ক" * (MAX_TRANSLATED_CHARS + 1))
    result = translate("when is the final exam", provider=stub)

    assert not result.ok
    assert "looks like an answer" in result.reason


def test_a_multi_line_translation_is_rejected() -> None:
    """Two lines means the model offered alternatives, and RRF cannot choose."""
    stub = _Stub("চূড়ান্ত পরীক্ষা কখন?\nফাইনাল পরীক্ষা কবে?")
    result = translate("when is the final exam", provider=stub)

    assert not result.ok
    assert "multiple lines" in result.reason


def test_a_translation_that_stayed_in_the_source_language_is_rejected() -> None:
    """An untranslated echo buys back no lexical arm; it duplicates the one we
    already ran, and RRF would double-count it."""
    stub = _Stub("When do the final examinations start?")
    result = translate("When do the final examinations start?", provider=stub)

    assert not result.ok
    assert "expected bn" in result.reason


def test_an_empty_translation_is_rejected() -> None:
    stub = _Stub("   ")
    result = translate("when is the final exam", provider=stub)

    assert not result.ok
    assert "empty" in result.reason


# ── failure is never fatal ──────────────────────────────────────────────────


def test_a_provider_failure_falls_back_to_strategy_a() -> None:
    """Losing the second arm pair is a degraded search; a 500 is no search."""
    stub = _Stub(fail=True)
    result = translate("when is the final exam", provider=stub)

    assert not result.ok
    assert result.reason.startswith("error:")


def test_no_provider_means_no_translation_and_no_crash() -> None:
    result = translate("when is the final exam", provider=None)

    assert not result.ok
    assert result.reason == "no provider"


def test_an_empty_query_never_reaches_the_provider() -> None:
    stub = _Stub("anything")
    result = translate("   ", provider=stub)

    assert not result.ok
    assert stub.calls == []


def test_a_query_already_in_the_target_language_is_not_translated() -> None:
    """Both arms already run in this language; a round trip buys nothing."""
    stub = _Stub("anything")
    result = translate("when is the exam", provider=stub, target="en")

    assert not result.ok
    assert result.reason == "already in target"
    assert stub.calls == []


# ── the code scanner itself ─────────────────────────────────────────────────


def test_course_codes_are_found_inside_a_sentence() -> None:
    assert course_codes("When is the CSE 3103 exam?") == {"CSE 3103"}


def test_course_codes_are_compared_case_and_space_insensitively() -> None:
    """`cse-3103` and `CSE 3103` are the same code; a translation that only
    changed the punctuation must not be rejected as having dropped it."""
    assert course_codes("cse-3103") == course_codes("CSE 3103")


def test_several_codes_in_one_query_are_all_found() -> None:
    assert course_codes("CSE 3103 and EEE 2101 exams") == {"CSE 3103", "EEE 2101"}


def test_a_plain_year_is_not_mistaken_for_a_course_code() -> None:
    """ "Summer 2026" would otherwise become a code the translation must
    preserve, and every correct translation of it would be rejected."""
    assert course_codes("the Summer 2026 routine") == set()


def test_a_term_and_year_is_not_mistaken_for_a_course_code() -> None:
    """ "Fall 2026" matches the code shape exactly, and a Bangla translation
    naturally renders "Fall" as a word. Treating it as a code would reject
    every correct translation of a term-scoped question."""
    assert course_codes("the Fall 2026 routine") == set()
    assert course_codes("Batch 2020 students") == set()


def test_a_term_word_does_not_hide_a_real_code_beside_it() -> None:
    assert course_codes("Fall 2026 CSE 3103 exam") == {"CSE 3103"}
