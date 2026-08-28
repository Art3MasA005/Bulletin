"""Phase 1 gate: does the embedding model actually place Bangla and English
equivalents near each other?

TASKS.md: "Verify cross-lingual embedding behaviour FIRST. Embed 20
English/Bangla sentence pairs meaning the same thing; check cosine similarity
is high. If the model doesn't cluster them, switch now -- everything downstream
depends on it."

PRD 7.2 Strategy A rests entirely on this property, and PRD 14 lists "chosen
embedding model isn't truly cross-lingual" as a named risk. This script is the
cheapest possible way to retire that risk: 40 embedding calls, before a single
chunk is written.

WHAT IS ACTUALLY MEASURED

Raw cosine similarity is a poor test on its own -- some models put every pair
at 0.9 and every unrelated pair at 0.85, which looks excellent and retrieves
nothing. So the headline metric is RANK based:

    For each English sentence, is its true Bangla translation the nearest of
    all 20 Bangla candidates?

That is precisely the question retrieval asks. The margin between matched and
mismatched pairs is reported alongside it, because a model that ranks
correctly with no margin will collapse on a real corpus.

    python eval/verify_crosslingual.py
"""

from __future__ import annotations

import argparse
import logging
import math
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend"))

from app.bangla.normalize import normalize  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.providers.base import Provider, ProviderError  # noqa: E402

logger = logging.getLogger(__name__)

# 20 pairs drawn from the actual domain -- exam dates, hostel rules, fees,
# scholarships, registration. Generic sentence pairs would overstate
# performance; these use the vocabulary the real corpus uses.
PAIRS: list[tuple[str, str]] = [
    ("When do the final examinations start?", "চূড়ান্ত পরীক্ষা কখন শুরু হবে?"),
    ("The exam routine is published on the notice board.", "পরীক্ষার সময়সূচি নোটিশ বোর্ডে প্রকাশ করা হয়েছে।"),
    ("Students must carry their admit card.", "শিক্ষার্থীদের অবশ্যই প্রবেশপত্র সঙ্গে আনতে হবে।"),
    ("How do I apply for a scholarship?", "বৃত্তির জন্য কীভাবে আবেদন করতে হয়?"),
    ("The tuition fee must be paid before registration.", "রেজিস্ট্রেশনের আগে টিউশন ফি পরিশোধ করতে হবে।"),
    ("What are the hostel rules?", "ছাত্রাবাসের নিয়মকানুন কী কী?"),
    ("Hostel residents must return before ten at night.", "ছাত্রাবাসের আবাসিকদের রাত দশটার আগে ফিরতে হবে।"),
    ("The library remains closed on public holidays.", "সরকারি ছুটির দিনে গ্রন্থাগার বন্ধ থাকে।"),
    ("Application for leave must be submitted in writing.", "ছুটির আবেদন লিখিতভাবে জমা দিতে হবে।"),
    ("The semester begins in the first week of January.", "সেমিস্টার শুরু হবে জানুয়ারির প্রথম সপ্তাহে।"),
    ("Late registration carries an additional fee.", "বিলম্বে নিবন্ধনের জন্য অতিরিক্ত ফি দিতে হবে।"),
    ("Results will be published in February.", "ফলাফল ফেব্রুয়ারি মাসে প্রকাশিত হবে।"),
    ("A minimum attendance of seventy percent is required.", "ন্যূনতম সত্তর শতাংশ উপস্থিতি আবশ্যক।"),
    ("The department office opens at nine in the morning.", "বিভাগীয় কার্যালয় সকাল নয়টায় খোলে।"),
    ("Students may appeal against a published result.", "শিক্ষার্থীরা প্রকাশিত ফলাফলের বিরুদ্ধে আপিল করতে পারবে।"),
    ("Identity cards must be renewed every academic year.", "প্রতি শিক্ষাবর্ষে পরিচয়পত্র নবায়ন করতে হবে।"),
    ("The university will remain closed during Eid.", "ঈদের সময় বিশ্ববিদ্যালয় বন্ধ থাকবে।"),
    ("Course registration closes on the thirtieth of December.", "কোর্স রেজিস্ট্রেশন ৩০ ডিসেম্বর শেষ হবে।"),
    ("Medical certificates must be submitted within seven days.", "চিকিৎসা সনদ সাত দিনের মধ্যে জমা দিতে হবে।"),
    ("Financial aid is available for eligible students.", "যোগ্য শিক্ষার্থীদের জন্য আর্থিক সহায়তা রয়েছে।"),
]

# A model that ranks the true pair first for fewer than this fraction of
# sentences cannot support Strategy A. PRD 13 targets Recall@5 >= 0.65 on the
# cross-lingual slices; a model failing here will not reach that.
TOP1_FLOOR = 0.70
MARGIN_FLOOR = 0.05


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b, strict=True))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


@dataclass
class Report:
    top1_accuracy: float
    mean_matched: float
    mean_mismatched: float
    per_pair: list[tuple[str, float, int, bool]]

    @property
    def margin(self) -> float:
        return self.mean_matched - self.mean_mismatched

    @property
    def passed(self) -> bool:
        return self.top1_accuracy >= TOP1_FLOOR and self.margin >= MARGIN_FLOOR


def evaluate(provider: Provider, pairs: list[tuple[str, str]]) -> Report:
    """Embed both sides and measure rank-1 cross-lingual retrieval."""
    # Normalization is applied exactly as ingestion and query apply it
    # (CLAUDE.md #6) -- testing unnormalized text would measure a pipeline the
    # product never runs.
    english = [normalize(en) for en, _ in pairs]
    bangla = [normalize(bn) for _, bn in pairs]

    en_vectors = provider.embed(english)
    bn_vectors = provider.embed(bangla)

    matched: list[float] = []
    mismatched: list[float] = []
    per_pair: list[tuple[str, float, int, bool]] = []

    for i, en_vec in enumerate(en_vectors):
        sims = [cosine(en_vec, bn_vec) for bn_vec in bn_vectors]
        true_sim = sims[i]
        ranked = sorted(range(len(sims)), key=lambda j: sims[j], reverse=True)
        rank = ranked.index(i) + 1

        matched.append(true_sim)
        mismatched.extend(sims[j] for j in range(len(sims)) if j != i)
        per_pair.append((pairs[i][0], true_sim, rank, rank == 1))

    return Report(
        top1_accuracy=sum(1 for _, _, _, hit in per_pair if hit) / len(per_pair),
        mean_matched=sum(matched) / len(matched),
        mean_mismatched=sum(mismatched) / len(mismatched),
        per_pair=per_pair,
    )


def render(report: Report, model: str) -> str:
    lines = [
        "# Cross-lingual embedding check",
        "",
        f"Model: `{model}`  ·  pairs: {len(report.per_pair)}",
        "",
        f"- **Top-1 accuracy: {report.top1_accuracy:.0%}** (floor {TOP1_FLOOR:.0%})",
        f"- Mean matched cosine: {report.mean_matched:.4f}",
        f"- Mean mismatched cosine: {report.mean_mismatched:.4f}",
        f"- **Margin: {report.margin:+.4f}** (floor {MARGIN_FLOOR:+.4f})",
        "",
        f"## Verdict: {'PASS' if report.passed else 'FAIL'}",
        "",
    ]
    if report.passed:
        lines += [
            "Strategy A (shared embedding space) is viable with this model.",
            "Strategy B (query translation) remains worth measuring in Ablation A --",
            "PRD 7.2 predicts B wins on noisy legacy-font and vision-read chunks.",
        ]
    else:
        lines += [
            "**Do not build on this model.** Cross-lingual retrieval would fail",
            "silently: no exception, no warning, just a confident 'not found'",
            "(PRD 2). Try another multilingual embedding model, or the local",
            "`bge-m3` fallback named in PRD 6, and re-run this before continuing.",
        ]
    lines += ["", "## Per pair", "", "| English | cosine | rank | top-1 |", "|---|---|---|---|"]
    for text, sim, rank, hit in report.per_pair:
        short = text if len(text) <= 52 else text[:49] + "..."
        lines.append(f"| {short} | {sim:.4f} | {rank} | {'yes' if hit else 'NO'} |")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s", stream=sys.stderr)
    settings = get_settings()

    from app.providers.openrouter import OpenRouterProvider

    provider = OpenRouterProvider(settings)
    try:
        model = settings.require("embedding_model")
    except Exception as exc:  # ConfigError
        print(f"{exc}", file=sys.stderr)
        return 2

    print(f"Embedding {len(PAIRS)} pairs with {model}...", file=sys.stderr)
    try:
        report = evaluate(provider, PAIRS)
    except ProviderError as exc:
        print(f"\nProvider call failed: {exc}", file=sys.stderr)
        print(
            "\nIf this is a 404, OpenRouter has no embeddings endpoint for this\n"
            "model. PRD 6 names local bge-m3 as the designated fallback --\n"
            "implement providers/local.py and re-run.",
            file=sys.stderr,
        )
        return 1
    finally:
        provider.close()

    out = args.out or (settings.reports_path / "crosslingual_check.md")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(report, model), encoding="utf-8")

    print(f"\nTop-1 accuracy : {report.top1_accuracy:.0%}  (floor {TOP1_FLOOR:.0%})")
    print(f"Matched cosine : {report.mean_matched:.4f}")
    print(f"Mismatched     : {report.mean_mismatched:.4f}")
    print(f"Margin         : {report.margin:+.4f}  (floor {MARGIN_FLOOR:+.4f})")
    print(f"\nVERDICT: {'PASS' if report.passed else 'FAIL'}")
    print(f"Wrote {out}", file=sys.stderr)
    return 0 if report.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
