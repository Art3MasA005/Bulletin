"""Ask the indexed corpus a question from the terminal.

    python -m tools.ask "when do the final examinations start"
    python -m tools.ask "CSE 211 exam date" --role student --answer

Retrieval only by default: it prints both arms, the fused order, and the score
floor decision, without spending a generation call. `--answer` runs the rest of
PRD 7.2 (steps 7-9) as well.

This is the harness the gold set will be measured with, and it is also the
fastest way to see whether a chunk that should have matched actually did.
"""

from __future__ import annotations

import argparse
import logging
import sys
import textwrap

from app.config import ConfigError, get_settings
from app.db.connection import connect, describe
from app.generate.answer import plan_answer, stream_answer
from app.providers.openrouter import OpenRouterProvider
from app.retrieve.audience import Role
from app.retrieve.pipeline import retrieve

logger = logging.getLogger(__name__)

SNIPPET_WIDTH = 100


def _print_arm(name: str, candidates, limit: int) -> None:
    print(f"\n{name} ({len(candidates)})")
    if not candidates:
        print("   (nothing)")
        return
    for rank, candidate in enumerate(candidates[:limit], start=1):
        head = textwrap.shorten(" ".join(candidate.content.split()), SNIPPET_WIDTH)
        print(f"  {rank:2d}. {candidate.score:.4f}  p{candidate.page_no:<3} {head}")


def run(args: argparse.Namespace) -> int:
    settings = get_settings()

    try:
        conn = connect(settings)
    except ConfigError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    provider = OpenRouterProvider(settings)
    print(f"database   : {describe(settings)}")
    print(f"question   : {args.question}")
    print(f"role       : {args.role}")

    try:
        with conn:
            result = retrieve(
                conn,
                question=args.question,
                institution_id=args.institution,
                role=Role(args.role),
                provider=provider,
                settings=settings,
            )

            if result.query.rewritten:
                print(f"condensed  : {result.query.text}")
            for error in result.errors:
                print(f"warning    : {error}")

            _print_arm("dense", result.dense, args.show)
            _print_arm("lexical", result.lexical, args.show)

            print(f"\nfused (RRF, top {args.show})")
            for rank, item in enumerate(result.fused[: args.show], start=1):
                arms = ",".join(f"{a}#{r}" for a, r in sorted(item.ranks.items()))
                head = textwrap.shorten(" ".join(item.content.split()), SNIPPET_WIDTH)
                print(f"  {rank:2d}. {item.rrf_score:.4f} [{arms}] {head}")

            outcome = result.rerank_outcome
            print(f"\nrerank     : {outcome.path} -- {outcome.reason}" if outcome else "")

            plan = plan_answer(
                result.query.text,
                result.finalists,
                query_lang=result.query.lang,
                dense_scores=result.dense_scores,
                settings=settings,
            )
            print(f"floor gate : {'PASS' if plan.grounded else 'REFUSE'} -- {plan.reason}")

            if not args.answer:
                return 0

            print("\nanswer")
            for piece in stream_answer(plan, provider=provider, stream=False):
                print(piece, end="", flush=True)
            print()

            if plan.citations:
                print("\ncitations")
                for citation in plan.citations:
                    snippet = textwrap.shorten(citation.snippet, SNIPPET_WIDTH)
                    print(f"  [{citation.n}] page {citation.page_no} ({citation.lang}) {snippet}")
        return 0
    finally:
        provider.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Query the indexed corpus.")
    parser.add_argument("question")
    parser.add_argument("--institution", required=True, help="institution uuid")
    parser.add_argument(
        "--role",
        default=Role.STUDENT.value,
        choices=[r.value for r in Role],
        help="caller role; decides which audiences are searchable (default: student)",
    )
    parser.add_argument("--answer", action="store_true", help="also generate the answer")
    parser.add_argument("--show", type=int, default=5, help="rows to print per arm")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s %(message)s",
    )
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
