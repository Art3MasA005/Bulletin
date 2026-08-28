"""Which generation model should Bulletin use? Measured, not guessed.

The question that started this: `qwen/qwen3.8-flash` is served by exactly one
provider, so an upstream 429 has nowhere to route and the answer dies as "could
not be completed". The fallback chain fixed the symptom, but it raised a real
question — is the primary model even the right choice, given that a
single-provider model is a single point of failure and the current fallback
costs three times as much?

Price and provider count come from the OpenRouter API and are facts. What no
API can tell us is the thing this product actually depends on:

  * Does the model answer a Bangla question **in Bangla**? The app is
    bilingual (PRD §2) and an English answer to a Bangla question is a wrong
    answer, however accurate its content.
  * Does it cite? Every answer must carry [n] markers or the Source Cards
    have nothing to point at (PRD §7.2 step 8).
  * Does it **refuse** when the context does not contain the answer? A model
    that invents a plausible exam date is worse than no model. This is the
    single most important column in the table.

So each candidate is run through the real retrieval pipeline and the real
answer prompt, on real corpus questions, and graded on those three.

    python eval/compare_generation_models.py
    python eval/compare_generation_models.py --models a/b,c/d
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend"))

import psycopg  # noqa: E402

from app.bangla.normalize import detect_lang  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.generate.answer import plan_answer, stream_answer  # noqa: E402
from app.providers.base import ProviderError  # noqa: E402
from app.providers.openrouter import OpenRouterProvider  # noqa: E402
from app.retrieve.pipeline import retrieve  # noqa: E402

logger = logging.getLogger(__name__)

# Multi-provider candidates, plus the two currently configured. Single-provider
# models are included only as the baseline they already are: adopting another
# one would rebuild the exact failure this investigation started from.
DEFAULT_MODELS = [
    "qwen/qwen3.8-flash",  # current primary — 1 provider
    "qwen/qwen3.8-27b",  # current fallback — 9 providers
    "google/gemma-4-26b-a4b-it",  # 8 providers
    "google/gemma-4-31b-it",  # 13 providers
    "deepseek/deepseek-v4-flash",  # 16 providers
    "openai/gpt-oss-20b",  # 12 providers
    "mistralai/mistral-nemo",  # 4 providers
]


@dataclass(frozen=True)
class Case:
    question: str
    lang: str
    #: True when the corpus can answer it. The refusal cases are the ones that
    #: separate a usable model from a dangerous one.
    answerable: bool


CASES = [
    Case("When do the final examinations start?", "en", True),
    Case("What is the exam time for CSE 211?", "en", True),
    Case("চূড়ান্ত পরীক্ষা কখন শুরু হবে?", "bn", True),
    Case("সিএসই বিভাগের পরীক্ষার সময়সূচি কী?", "bn", True),
    # Nothing in the corpus covers hostels. A model that answers this one is
    # inventing, and no retrieval improvement can save a product that does.
    Case("What are the hostel rules and curfew timings?", "en", False),
]


@dataclass
class Result:
    model: str
    case: Case
    text: str
    seconds: float
    error: str = ""

    @property
    def cited(self) -> bool:
        return "[1]" in self.text or "[2]" in self.text

    @property
    def answered_in_query_language(self) -> bool:
        """A Bangla question must come back in Bangla.

        `mixed` counts: a Bangla answer quoting "CSE 211" is mixed by
        detection and correct by every standard that matters.
        """
        if self.error or not self.text.strip():
            return False
        got = detect_lang(self.text)
        return got == self.case.lang or got == "mixed"

    @property
    def refused(self) -> bool:
        """Whether the model declined rather than inventing.

        Matched on meaning rather than an exact string, because the not-found
        wording is the model's own once it is inside the answer prompt.
        """
        low = self.text.lower()
        markers = (
            "not covered",
            "nothing in the",
            "does not contain",
            "doesn't contain",
            "no information",
            "not mentioned",
            "not specify",
            "not stated",
            "could not find",
            "নেই",
            "উল্লেখ নেই",
            "পাওয়া যায়নি",
        )
        return any(m in low for m in markers)

    @property
    def ok(self) -> bool:
        if self.error:
            return False
        if not self.case.answerable:
            return self.refused
        return self.answered_in_query_language and self.cited and not self.refused


def catalogue(api_key: str) -> dict[str, dict]:
    """Provider count and best price per model, straight from OpenRouter."""
    out: dict[str, dict] = {}
    for slug in DEFAULT_MODELS:
        url = f"https://openrouter.ai/api/v1/models/{slug}/endpoints"
        request = urllib.request.Request(url, headers={"Authorization": f"Bearer {api_key}"})
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                data = json.load(response)["data"]
        except Exception as exc:  # noqa: BLE001 -- a missing model is reportable, not fatal
            logger.warning("no endpoint data for %s: %s", slug, exc)
            continue
        endpoints = [e for e in data.get("endpoints", []) if (e.get("status") or 0) >= 0]
        if not endpoints:
            continue
        out[slug] = {
            "providers": len(endpoints),
            "prompt": min(float(e["pricing"]["prompt"]) for e in endpoints),
            "completion": min(float(e["pricing"]["completion"]) for e in endpoints),
        }
    return out


def estimate_tokens(text: str) -> int:
    """Rough token count. Bangla tokenizes far worse than English.

    Latin text runs about 4 characters per token; Bangla conjuncts and matras
    land closer to 1.5. Using one ratio for both would understate the cost of
    every Bangla question by roughly half, which is the wrong way round for a
    product whose whole point is Bangla.
    """
    bangla = sum(1 for ch in text if "ঀ" <= ch <= "৿")
    latin = len(text) - bangla
    return int(latin / 4 + bangla / 1.5)


def run(models: list[str]) -> tuple[list[Result], dict[str, int]]:
    settings = get_settings()
    results: list[Result] = []
    prompt_tokens: dict[str, int] = {}

    with psycopg.connect(settings.database_url.get_secret_value()) as conn, conn.cursor() as cur:
        cur.execute("select institution_id from profiles where institution_id is not null limit 1")
        row = cur.fetchone()
        if row is None:
            raise SystemExit("no institution in the database; seed one before comparing models")
        institution_id = str(row[0])

        # Retrieval runs ONCE per question with the configured provider. Every
        # candidate then answers from an identical context, so the table
        # measures generation and nothing else.
        base = OpenRouterProvider(settings)
        plans = {}
        for case in CASES:
            result = retrieve(
                conn,
                question=case.question,
                institution_id=institution_id,
                role="student",
                provider=base,
            )
            plan = plan_answer(
                case.question,
                result.finalists,
                query_lang=result.query.lang,
                dense_scores=result.dense_scores,
            )
            plans[case.question] = plan
            prompt_tokens[case.question] = sum(
                estimate_tokens(m.content) for m in (plan.messages or [])
            )
            print(
                f"  context ready: {case.question[:44]:<44} "
                f"grounded={plan.grounded} blocks={len(plan.citations)}",
                file=sys.stderr,
            )
        base.close()

    for model in models:
        # One model per provider instance, fallbacks off: a chain would hide
        # which model actually answered, which is the whole measurement.
        pinned = settings.model_copy(
            update={"generation_model": model, "generation_model_fallbacks": ""}
        )
        provider = OpenRouterProvider(pinned)
        for case in CASES:
            plan = plans[case.question]
            started = time.time()
            try:
                text = "".join(stream_answer(plan, provider=provider))
                error = ""
            except ProviderError as exc:
                text, error = "", str(exc)[:120]
            elapsed = time.time() - started
            results.append(Result(model, case, text, elapsed, error))
            print(
                f"  {model:<30} {case.lang} {'ok ' if results[-1].ok else 'BAD'} "
                f"{elapsed:5.1f}s  {(error or text)[:60]!r}",
                file=sys.stderr,
            )
        provider.close()

    return results, prompt_tokens


def render(results: list[Result], prices: dict[str, dict], prompt_tokens: dict[str, int]) -> str:
    models = list(dict.fromkeys(r.model for r in results))
    mean_prompt = sum(prompt_tokens.values()) / max(1, len(prompt_tokens))

    lines = [
        "# Generation model comparison",
        "",
        "Every candidate answered the **same retrieved context** through the",
        "**real answer prompt**. Retrieval ran once per question, so the only",
        "variable is the model.",
        "",
        f"Measured prompt size: **{mean_prompt:.0f} tokens** average across "
        f"{len(prompt_tokens)} questions (estimated; Bangla counted at a worse",
        "ratio than Latin, which is honest for this corpus). Cost below assumes",
        "that prompt plus a 300-token answer.",
        "",
        "| model | providers | $/M in | $/M out | $/1k questions | passed | bn ok | cites | refuses |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]

    for model in models:
        rows = [r for r in results if r.model == model]
        answerable = [r for r in rows if r.case.answerable]
        refusals = [r for r in rows if not r.case.answerable]
        bangla = [r for r in answerable if r.case.lang == "bn"]

        price = prices.get(model, {})
        cost = ""
        if price:
            per_q = price["prompt"] * mean_prompt + price["completion"] * 300
            cost = f"${per_q * 1000:.2f}"

        lines.append(
            f"| `{model}` "
            f"| {price.get('providers', '?')} "
            f"| {price.get('prompt', 0) * 1e6:.3f} "
            f"| {price.get('completion', 0) * 1e6:.3f} "
            f"| {cost} "
            f"| {sum(1 for r in rows if r.ok)}/{len(rows)} "
            f"| {sum(1 for r in bangla if r.answered_in_query_language)}/{len(bangla)} "
            f"| {sum(1 for r in answerable if r.cited)}/{len(answerable)} "
            f"| {sum(1 for r in refusals if r.refused)}/{len(refusals)} |"
        )

    lines += [
        "",
        "**passed** — every check for that case. **bn ok** — a Bangla question",
        "answered in Bangla. **cites** — carries [n] markers. **refuses** — declined",
        "the question the corpus cannot answer, instead of inventing one.",
        "",
        "`refuses` is the column to read first. A model that scores 4/4 on the",
        "answerable questions and 0/1 here is not a cheaper option, it is a",
        "product that lies about exam dates.",
        "",
        "## Answers",
        "",
    ]
    for model in models:
        lines.append(f"### `{model}`")
        lines.append("")
        for r in [x for x in results if x.model == model]:
            verdict = "PASS" if r.ok else "FAIL"
            body = r.error or " ".join(r.text.split())[:300]
            lines.append(f"- **{verdict}** ({r.seconds:.1f}s) _{r.case.question}_")
            lines.append(f"  > {body}")
        lines.append("")

    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", default=",".join(DEFAULT_MODELS))
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.ERROR, format="%(levelname)s %(message)s", stream=sys.stderr)
    settings = get_settings()
    models = [m.strip() for m in args.models.split(",") if m.strip()]

    print(f"Comparing {len(models)} models on {len(CASES)} questions...", file=sys.stderr)
    prices = catalogue(settings.require("openrouter_api_key"))
    results, prompt_tokens = run(models)

    out = args.out or (settings.reports_path / "model_comparison.md")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(results, prices, prompt_tokens), encoding="utf-8")
    print(f"\nWrote {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
