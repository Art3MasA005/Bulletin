"""Gold-set evaluation: Recall@k, MRR, and the refusal rate. PRD 12.

    python eval/run_eval.py --institution <uuid>
    python eval/run_eval.py --institution <uuid> --ablation
    python eval/run_eval.py --institution <uuid> --slice course_code --k 5

Reads `eval/gold_set.jsonl`, runs each question through the real retrieval
pipeline against the real index, and scores against the gold PAGES rather than
chunk ids -- chunk ids change on every re-ingest, pages do not.

`--ablation` runs the same questions under each retrieval configuration
(dense only / lexical only / hybrid RRF) and prints the comparison table
Ablation C needs. That is the only honest way to claim the hybrid arm earns its
complexity: the numbers, per slice, from one run.

Costs one embedding call per question per config. No generation calls unless
`--answers` is passed, which additionally checks that the expected strings
appear in the generated answer.
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend"))

from app.config import ConfigError, Settings, get_settings
from app.db.connection import connect
from app.generate.answer import plan_answer, stream_answer
from app.providers.base import Provider, ProviderError
from app.providers.openrouter import OpenRouterProvider
from app.retrieve import dense as dense_arm
from app.retrieve import lexical as lexical_arm
from app.retrieve.audience import Role
from app.retrieve.dense import Candidate
from app.retrieve.fuse import reciprocal_rank_fusion

logger = logging.getLogger(__name__)

GOLD_SET = REPO_ROOT / "eval" / "gold_set.jsonl"

# The configurations Ablation C compares. "hybrid" is the shipping default.
CONFIGS = ("dense", "lexical", "hybrid")

# How a grounded answer says it cannot answer. The prompt tells the model to
# say the context does not contain the answer; models phrase that several ways,
# and scoring refusal needs to recognise all of them.
REFUSAL_MARKERS = (
    "does not contain",
    "do not contain",
    "not contain the answer",
    "no information",
    "not mentioned",
    "not covered",
    "nothing in the published documents",
    "cannot answer",
    "not available in the",
)


def contains_fact(text: str, needle: str) -> bool:
    """Whether a generated answer states this fact.

    Normalizes the two ways a correct answer still fails a naive substring
    check: digit grouping ("Tk. 1,500" for 1500) and whitespace/case. Measured
    on the first gold run, where 2 of 4 "wrong" answers were in fact correct
    and only written differently.
    """
    flat = re.sub(r"(?<=\d),(?=\d)", "", " ".join(text.split())).lower()
    target = re.sub(r"(?<=\d),(?=\d)", "", " ".join(needle.split())).lower()
    return target in flat


@dataclass
class GoldItem:
    id: str
    slice: str
    question: str
    gold_pages: list[tuple[str, int]]
    expect: str
    role: str = "student"
    lang: str = "en"
    answer_contains: list[str] = field(default_factory=list)

    @property
    def answerable(self) -> bool:
        return self.expect == "answer"


@dataclass
class ItemScore:
    item: GoldItem
    rank: int | None  # 1-based rank of the first gold page, None if absent
    refused: bool
    top_score: float
    answer_ok: bool | None = None
    # For an unanswerable question that cleared the floor: did the generated
    # answer refuse anyway? None when it never reached generation.
    answer_refused: bool | None = None
    # True when the provider gave up (rate limit) and this item went unscored.
    generation_failed: bool = False

    def hit_at(self, k: int) -> bool:
        return self.rank is not None and self.rank <= k

    @property
    def reciprocal_rank(self) -> float:
        return 1.0 / self.rank if self.rank else 0.0


def load_gold(path: Path = GOLD_SET) -> list[GoldItem]:
    items: list[GoldItem] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        raw = json.loads(line)
        items.append(
            GoldItem(
                id=raw["id"],
                slice=raw["slice"],
                question=raw["question"],
                gold_pages=[(f, int(p)) for f, p in raw.get("gold_pages", [])],
                expect=raw.get("expect", "answer"),
                role=raw.get("role", "student"),
                lang=raw.get("lang", "en"),
                answer_contains=raw.get("answer_contains", []),
            )
        )
    return items


def load_page_index(conn, institution_id: str) -> dict[int, tuple[str, int]]:
    """chunk_id -> (filename, page_no). Gold pages are matched through this."""
    with conn.cursor() as cur:
        cur.execute(
            "select c.id, d.filename, c.page_no from chunks c "
            "join documents d on d.id = c.doc_id where c.institution_id = %s",
            (institution_id,),
        )
        return {row[0]: (row[1], int(row[2])) for row in cur.fetchall()}


def _search(
    conn,
    *,
    config: str,
    item: GoldItem,
    vector: list[float] | None,
    institution_id: str,
    settings: Settings,
) -> list[Candidate]:
    """Run one retrieval configuration. Returns candidates, best first."""
    dense_hits: list[Candidate] = []
    lexical_hits: list[Candidate] = []

    if config in ("dense", "hybrid") and vector is not None:
        dense_hits = dense_arm.search(
            conn,
            institution_id=institution_id,
            role=Role(item.role),
            query_vector=vector,
            limit=settings.retrieve_top_k,
        )
    if config in ("lexical", "hybrid"):
        lexical_hits = lexical_arm.search(
            conn,
            institution_id=institution_id,
            role=Role(item.role),
            query=item.question,
            limit=settings.retrieve_top_k,
            query_lang=item.lang,
        )

    if config == "dense":
        return dense_hits
    if config == "lexical":
        return lexical_hits
    fused = reciprocal_rank_fusion({"dense": dense_hits, "lexical": lexical_hits})
    return [f.candidate for f in fused]


def score_item(
    item: GoldItem,
    candidates: Sequence[Candidate],
    pages: dict[int, tuple[str, int]],
    *,
    settings: Settings,
    provider: Provider | None = None,
) -> ItemScore:
    """Rank of the first gold page, and whether the floor gate refused."""
    gold = {(f.lower(), p) for f, p in item.gold_pages}
    rank: int | None = None
    for position, candidate in enumerate(candidates, start=1):
        page = pages.get(candidate.chunk_id)
        if page and (page[0].lower(), page[1]) in gold:
            rank = position
            break

    dense_scores = {c.chunk_id: c.score for c in candidates if c.arm == "dense"}
    plan = plan_answer(
        item.question,
        list(candidates[: settings.rerank_top_k]),
        query_lang=item.lang,
        dense_scores=dense_scores,
        settings=settings,
    )

    answer_ok: bool | None = None
    answer_refused: bool | None = None
    generation_failed = False
    if provider is not None and plan.grounded:
        # A rate limit on question 31 must not discard the 30 answers already
        # scored. The provider already retries with backoff; if it still gives
        # up, this item is reported as unscored rather than crashing the run.
        try:
            if item.answerable and item.answer_contains:
                text = "".join(stream_answer(plan, provider=provider, stream=False))
                answer_ok = all(
                    contains_fact(text, needle) for needle in item.answer_contains
                )
            elif not item.answerable:
                # The question cleared the floor but the corpus cannot answer
                # it. PRD 13 makes refusal pass/fail, so the second line of
                # defence -- the answer prompt -- is measured, not assumed.
                text = "".join(stream_answer(plan, provider=provider, stream=False))
                answer_refused = any(
                    marker in text.lower() for marker in REFUSAL_MARKERS
                )
        except ProviderError as exc:
            logger.warning("generation failed for %s: %s", item.id, exc)
            generation_failed = True

    return ItemScore(
        item=item,
        rank=rank,
        refused=not plan.grounded,
        top_score=max((c.score for c in candidates if c.arm == "dense"), default=0.0),
        answer_ok=answer_ok,
        answer_refused=answer_refused,
        generation_failed=generation_failed,
    )


def evaluate(
    conn,
    items: Sequence[GoldItem],
    *,
    config: str,
    institution_id: str,
    provider: Provider,
    pages: dict[int, tuple[str, int]],
    settings: Settings,
    check_answers: bool = False,
) -> list[ItemScore]:
    scores: list[ItemScore] = []
    for item in items:
        vector = None
        if config in ("dense", "hybrid"):
            vector = provider.embed([item.question])[0]
        candidates = _search(
            conn,
            config=config,
            item=item,
            vector=vector,
            institution_id=institution_id,
            settings=settings,
        )
        scores.append(
            score_item(
                item,
                candidates,
                pages,
                settings=settings,
                provider=provider if check_answers else None,
            )
        )
        logger.info("scored %s config=%s rank=%s", item.id, config, scores[-1].rank)
    return scores


# ── reporting ───────────────────────────────────────────────────────────────


def _slice_rows(
    scores: Sequence[ItemScore], k: int
) -> list[tuple[str, int, float, float]]:
    """(slice, n, recall@k, MRR) for answerable items, one row per slice."""
    rows = []
    by_slice: dict[str, list[ItemScore]] = {}
    for score in scores:
        if score.item.answerable:
            by_slice.setdefault(score.item.slice, []).append(score)
    for name, group in sorted(by_slice.items()):
        recall = sum(s.hit_at(k) for s in group) / len(group)
        mrr = sum(s.reciprocal_rank for s in group) / len(group)
        rows.append((name, len(group), recall, mrr))
    if by_slice:
        every = [s for g in by_slice.values() for s in g]
        rows.append(
            (
                "ALL",
                len(every),
                sum(s.hit_at(k) for s in every) / len(every),
                sum(s.reciprocal_rank for s in every) / len(every),
            )
        )
    return rows


def print_report(scores: Sequence[ItemScore], k: int) -> None:
    print(f"\nRetrieval (k={k})")
    print(f"{'slice':<28}{'n':>4}{'Recall@k':>11}{'MRR':>8}")
    for name, n, recall, mrr in _slice_rows(scores, k):
        print(f"{name:<28}{n:>4}{recall:>11.2f}{mrr:>8.2f}")

    refusals = [s for s in scores if not s.item.answerable]
    if refusals:
        gated = sum(s.refused for s in refusals)
        measured = [s for s in refusals if s.answer_refused is not None]
        by_answer = sum(1 for s in measured if s.answer_refused)
        print(f"\nRefusal ({len(refusals)} unanswerable questions)")
        print(f"  refused by the score floor, no LLM call : {gated}")
        if measured:
            print(
                f"  refused by the answer prompt instead    : {by_answer}/{len(measured)}"
            )
            print(
                f"  ANSWERED ANYWAY                         : {len(measured) - by_answer}"
            )
        for score in refusals:
            if score.answer_refused is False:
                print(
                    f"  LEAKED  {score.item.id}  top={score.top_score:.3f}  {score.item.question}"
                )
            elif score.answer_refused is None and not score.refused:
                print(
                    f"  ungated {score.item.id}  top={score.top_score:.3f} (use --answers)"
                )

    missed = [s for s in scores if s.item.answerable and not s.hit_at(k)]
    if missed:
        print(f"\nMissed at k={k} ({len(missed)})")
        for score in missed:
            found = f"rank {score.rank}" if score.rank else "not retrieved"
            print(f"  {score.item.id:<12} {found:<15} {score.item.question}")

    failed = [s for s in scores if s.generation_failed]
    if failed:
        names = ", ".join(s.item.id for s in failed)
        print(
            f"\nGeneration unavailable for {len(failed)} item(s) (rate limit): {names}"
        )

    answered = [s for s in scores if s.answer_ok is not None]
    if answered:
        correct = sum(bool(s.answer_ok) for s in answered)
        print(
            f"\nAnswer content: {correct}/{len(answered)} contained the expected facts"
        )
        for score in answered:
            if not score.answer_ok:
                print(
                    f"  WRONG   {score.item.id}  expected {score.item.answer_contains}"
                )


def print_ablation(table: dict[str, list[ItemScore]], k: int) -> None:
    """Ablation C: dense vs lexical vs hybrid, per slice."""
    slices = [row[0] for row in _slice_rows(next(iter(table.values())), k)]
    print(f"\nAblation C -- retrieval configuration (Recall@{k})")
    header = f"{'slice':<28}" + "".join(f"{c:>12}" for c in table)
    print(header)
    for name in slices:
        cells = []
        for scores in table.values():
            row = next((r for r in _slice_rows(scores, k) if r[0] == name), None)
            cells.append(f"{row[2]:>12.2f}" if row else f"{'-':>12}")
        print(f"{name:<28}" + "".join(cells))

    print("\nAblation C -- retrieval configuration (MRR)")
    print(header)
    for name in slices:
        cells = []
        for scores in table.values():
            row = next((r for r in _slice_rows(scores, k) if r[0] == name), None)
            cells.append(f"{row[3]:>12.2f}" if row else f"{'-':>12}")
        print(f"{name:<28}" + "".join(cells))


def _markdown_table(
    table: dict[str, list[ItemScore]], k: int, column: int
) -> list[str]:
    """One metric as a markdown table. `column` is 2 for Recall@k, 3 for MRR."""
    lines = [
        "| slice | n | " + " | ".join(table) + " |",
        "|---|---|" + "---|" * len(table),
    ]
    for name in [row[0] for row in _slice_rows(next(iter(table.values())), k)]:
        cells, n = [], 0
        for scores in table.values():
            row = next((r for r in _slice_rows(scores, k) if r[0] == name), None)
            n = row[1] if row else 0
            cells.append(f"{row[column]:.2f}" if row else "-")
        lines.append(f"| {name} | {n} | " + " | ".join(cells) + " |")
    return lines


def write_report(path: Path, table: dict[str, list[ItemScore]], k: int) -> None:
    lines = [
        "# Gold-set evaluation",
        "",
        f"Gold set: `eval/gold_set.jsonl` · k={k} · generated by `eval/run_eval.py`",
        "",
        f"## Recall@{k}",
        "",
        *_markdown_table(table, k, 2),
        "",
        "## MRR",
        "",
        *_markdown_table(table, k, 3),
    ]

    hybrid = table.get("hybrid")
    if hybrid:
        refusals = [s for s in hybrid if not s.item.answerable]
        if refusals:
            gated = sum(s.refused for s in refusals)
            measured = [s for s in refusals if s.answer_refused is not None]
            by_answer = sum(1 for s in measured if s.answer_refused)
            lines += [
                "",
                "## Refusal",
                "",
                f"- refused by the score floor, no LLM call: **{gated}/{len(refusals)}**",
            ]
            if measured:
                lines += [
                    f"- refused by the answer prompt instead: **{by_answer}/{len(measured)}**",
                    f"- answered anyway: **{len(measured) - by_answer}**",
                ]
            else:
                lines.append(
                    "- the rest were not scored at the answer level "
                    "(re-run with `--answers`)"
                )

        answered = [s for s in hybrid if s.answer_ok is not None]
        if answered:
            correct = sum(bool(s.answer_ok) for s in answered)
            lines += [
                "",
                "## Answer content",
                "",
                f"{correct}/{len(answered)} answers contained the expected facts.",
            ]

        missed = [s for s in hybrid if s.item.answerable and not s.hit_at(k)]
        if missed:
            lines += ["", f"## Missed at k={k}", ""]
            lines += [
                f"- `{s.item.id}` ({'rank ' + str(s.rank) if s.rank else 'not retrieved'}) "
                f"— {s.item.question}"
                for s in missed
            ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\nwrote {path}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the gold set.")
    parser.add_argument("--institution", required=True, help="institution uuid")
    parser.add_argument("--k", type=int, default=5, help="k for Recall@k (default 5)")
    parser.add_argument("--slice", help="run only one slice")
    parser.add_argument(
        "--ablation", action="store_true", help="dense vs lexical vs hybrid"
    )
    parser.add_argument(
        "--answers", action="store_true", help="also generate and check answers"
    )
    parser.add_argument("--out", default="eval/reports/gold_set_eval.md")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s %(message)s",
    )

    settings = get_settings()
    items = load_gold()
    if args.slice:
        items = [i for i in items if i.slice == args.slice]
    if not items:
        print("no gold items selected", file=sys.stderr)
        return 1

    try:
        conn = connect(settings)
    except ConfigError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    provider = OpenRouterProvider(settings)
    configs = CONFIGS if args.ablation else ("hybrid",)

    try:
        with conn:
            pages = load_page_index(conn, args.institution)
            print(f"gold items : {len(items)}   indexed chunks: {len(pages)}")

            table: dict[str, list[ItemScore]] = {}
            for config in configs:
                table[config] = evaluate(
                    conn,
                    items,
                    config=config,
                    institution_id=args.institution,
                    provider=provider,
                    pages=pages,
                    settings=settings,
                    check_answers=args.answers and config == "hybrid",
                )

            print_report(table["hybrid" if "hybrid" in table else configs[0]], args.k)
            if args.ablation:
                print_ablation(table, args.k)
            write_report(settings.resolved(Path(args.out)), table, args.k)
    finally:
        provider.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
