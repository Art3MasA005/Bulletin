"""Corpus -> chunks. The `make ingest` entry point.

    python -m tools.ingest_corpus --dry-run          # chunk only, no DB, no cost
    python -m tools.ingest_corpus --vision           # allow vision escalation
    python -m tools.ingest_corpus --institution <uuid> --audience students

Two modes, and the order matters:

  **--dry-run** extracts and chunks, writes every chunk to JSONL, and prints a
  per-document summary. No embedding call, no database, no money. Run it first
  and read the JSONL. CLAUDE.md #7 and #8: a legacy-font or bad-OCR document
  ingested without inspection indexes as garbage with no error anywhere.

  **Full run** additionally embeds each chunk and writes `documents` and
  `chunks` rows. Re-ingesting a file replaces its chunks inside one
  transaction -- a half-replaced document would answer questions from a mix of
  two extractions.

Every document is checkpointed by pipeline.ingest_document, so a run killed
half way resumes without re-spending vision tokens.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path

from app.config import ConfigError, Settings, get_settings
from app.ingest.chunk import Chunk, chunk_pages
from app.ingest.extract import SUPPORTED_SUFFIXES
from app.ingest.pipeline import IngestResult, ingest_document
from app.providers.base import Provider, ProviderError
from app.retrieve.audience import Audience

logger = logging.getLogger(__name__)

# One request per batch of chunks. Large enough to be cheap in round trips,
# small enough that a failure loses little work and a payload stays under any
# provider's request-size limit.
EMBED_BATCH = 32

INSERT_DOCUMENT = """
insert into documents
    (id, institution_id, title, filename, mime_type, storage_path, audience,
     status, page_count, lang_detected, extraction_method, extraction_confidence)
values
    (gen_random_uuid(), %(institution_id)s, %(title)s, %(filename)s, %(mime_type)s,
     %(storage_path)s, %(audience)s, 'ready', %(page_count)s, %(lang)s,
     %(method)s, %(confidence)s)
returning id
"""

DELETE_EXISTING = """
delete from documents
where institution_id = %(institution_id)s and filename = %(filename)s
"""

INSERT_CHUNK = """
insert into chunks
    (doc_id, institution_id, audience, content, page_no, section, lang,
     extraction_method, embedding)
values
    (%(doc_id)s, %(institution_id)s, %(audience)s, %(content)s, %(page_no)s,
     %(section)s, %(lang)s, %(method)s, %(embedding)s)
"""


@dataclass
class DocumentReport:
    """What happened to one file. Printed as a row, written to the JSONL header."""

    filename: str
    pages: int = 0
    chars: int = 0
    chunks: int = 0
    methods: dict[str, int] = field(default_factory=dict)
    escalated: int = 0
    rejected: str | None = None
    doc_id: str | None = None

    @property
    def ok(self) -> bool:
        return self.rejected is None


def corpus_files(root: Path) -> list[Path]:
    """Every supported file under `root`, in a stable order."""
    return sorted(
        p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in SUPPORTED_SUFFIXES
    )


def _document_lang(chunks: list[Chunk]) -> str:
    """The document's dominant chunk language, for the `documents` row."""
    counts: dict[str, int] = {}
    for chunk in chunks:
        counts[chunk.lang] = counts.get(chunk.lang, 0) + 1
    return max(counts, key=counts.get) if counts else "en"  # type: ignore[arg-type]


def _dominant_method(result: IngestResult) -> tuple[str, float]:
    counts = result.method_counts()
    if not counts:
        return "native_text", 0.0
    method = max(counts, key=counts.get)  # type: ignore[arg-type]
    pages = [p for p in result.pages if p.method == method]
    confidence = sum(p.confidence for p in pages) / len(pages) if pages else 0.0
    return method, confidence


def embed_chunks(chunks: list[Chunk], provider: Provider, settings: Settings) -> list[list[float]]:
    """Embed every chunk, in batches, asserting the configured dimension.

    A dimension mismatch is caught here rather than by Postgres, because the
    pgvector error names neither the model nor the setting and CLAUDE.md
    requires a migration and a re-index to change it.
    """
    vectors: list[list[float]] = []
    for start in range(0, len(chunks), EMBED_BATCH):
        batch = chunks[start : start + EMBED_BATCH]
        got = provider.embed([c.content for c in batch])
        if len(got) != len(batch):
            raise ProviderError(f"embedded {len(got)} of {len(batch)} chunks")
        for vector in got:
            if len(vector) != settings.embedding_dim:
                raise ProviderError(
                    f"embedding dimension {len(vector)} != BULLETIN_EMBEDDING_DIM "
                    f"{settings.embedding_dim}; the schema and the model disagree"
                )
        vectors.extend(got)
        logger.info("embedded %d/%d chunks", len(vectors), len(chunks))
    return vectors


def write_document(
    conn,
    *,
    path: Path,
    result: IngestResult,
    chunks: list[Chunk],
    vectors: list[list[float]],
    institution_id: str,
    audience: str,
    settings: Settings,
) -> str:
    """Replace this file's document and chunks in one transaction."""
    method, confidence = _dominant_method(result)
    with conn.cursor() as cur:
        # Replace, not append: re-ingesting after a fix must not leave the old
        # extraction's chunks retrievable alongside the new one. The cascade on
        # documents removes the chunks.
        cur.execute(DELETE_EXISTING, {"institution_id": institution_id, "filename": path.name})
        cur.execute(
            INSERT_DOCUMENT,
            {
                "institution_id": institution_id,
                "title": path.stem.replace("-", " ").replace("_", " ").strip(),
                "filename": path.name,
                "mime_type": "application/pdf" if path.suffix.lower() == ".pdf" else "image/png",
                "storage_path": f"local://{path.name}",
                "audience": audience,
                "page_count": len(result.pages),
                "lang": _document_lang(chunks),
                "method": method,
                "confidence": confidence,
            },
        )
        doc_id = cur.fetchone()[0]

        for chunk, vector in zip(chunks, vectors, strict=True):
            cur.execute(
                INSERT_CHUNK,
                {
                    "doc_id": doc_id,
                    "institution_id": institution_id,
                    "audience": audience,
                    "content": chunk.content,
                    "page_no": chunk.page_no,
                    "section": chunk.section,
                    "lang": chunk.lang,
                    "method": chunk.extraction_method,
                    "embedding": str(vector),
                },
            )
    conn.commit()
    logger.info("wrote doc=%s doc_id=%s chunks=%d", path.name, doc_id, len(chunks))
    return str(doc_id)


def process_file(
    path: Path,
    *,
    audience: str,
    provider: Provider | None,
    settings: Settings,
    resume: bool = True,
) -> tuple[DocumentReport, list[Chunk], IngestResult]:
    """Extract and chunk one file. No database, no embedding."""
    result = ingest_document(path, provider, settings=settings, resume=resume)
    report = DocumentReport(filename=path.name)

    if result.rejected:
        report.rejected = result.rejected
        logger.warning("skipped doc=%s reason=%s", path.name, result.reject_code)
        return report, [], result

    chunks = chunk_pages(
        [(p.page_no, p.text, p.method) for p in result.pages],
        audience=audience,
        settings=settings,
    )
    report.pages = len(result.pages)
    report.chars = result.total_chars
    report.chunks = len(chunks)
    report.methods = result.method_counts()
    report.escalated = len(result.escalated_pages)
    return report, chunks, result


def run(args: argparse.Namespace, settings: Settings) -> int:
    root = settings.resolved(Path(args.dir)) if args.dir else settings.corpus_path
    files = corpus_files(root)
    if not files:
        print(f"No supported files under {root}", file=sys.stderr)
        return 1

    if args.limit:
        files = files[: args.limit]

    provider: Provider | None = None
    if args.vision or not args.dry_run:
        from app.providers.openrouter import OpenRouterProvider

        provider = OpenRouterProvider(settings)

    out_path = settings.resolved(Path(args.out))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    conn = None
    if not args.dry_run:
        if not args.institution:
            print("--institution <uuid> is required for a real run", file=sys.stderr)
            return 2
        from app.db.connection import connect

        try:
            conn = connect(settings)
        except ConfigError as exc:
            print(str(exc), file=sys.stderr)
            return 2

    reports: list[DocumentReport] = []
    try:
        with out_path.open("w", encoding="utf-8") as sink:
            for path in files:
                report, chunks, result = process_file(
                    path,
                    audience=args.audience,
                    provider=provider,
                    settings=settings,
                    resume=not args.no_resume,
                )

                if chunks and conn is not None:
                    assert provider is not None
                    vectors = embed_chunks(chunks, provider, settings)
                    report.doc_id = write_document(
                        conn,
                        path=path,
                        result=result,
                        chunks=chunks,
                        vectors=vectors,
                        institution_id=args.institution,
                        audience=args.audience,
                        settings=settings,
                    )

                for chunk in chunks:
                    sink.write(
                        json.dumps(
                            {
                                "filename": path.name,
                                "doc_id": report.doc_id,
                                "index": chunk.index,
                                "page_no": chunk.page_no,
                                "section": chunk.section,
                                "lang": chunk.lang,
                                "extraction_method": chunk.extraction_method,
                                "audience": chunk.audience,
                                "chars": chunk.char_count,
                                "content": chunk.content,
                            },
                            ensure_ascii=False,
                        )
                        + "\n"
                    )
                reports.append(report)
    finally:
        if conn is not None:
            conn.close()
        if provider is not None:
            provider.close()

    _print_summary(reports, out_path, dry_run=args.dry_run)
    return 0 if all(r.ok for r in reports) else 1


def _print_summary(reports: list[DocumentReport], out_path: Path, *, dry_run: bool) -> None:
    width = max((len(r.filename) for r in reports), default=8)
    print(f"\n{'document'.ljust(width)}  pages  chunks   chars  methods")
    for report in reports:
        if not report.ok:
            print(f"{report.filename.ljust(width)}  REJECTED  {report.rejected}")
            continue
        methods = ",".join(f"{k}:{v}" for k, v in sorted(report.methods.items()))
        print(
            f"{report.filename.ljust(width)}  {report.pages:5d}  {report.chunks:6d}  "
            f"{report.chars:6d}  {methods}"
        )

    ok = [r for r in reports if r.ok]
    print(
        f"\n{len(ok)}/{len(reports)} documents, "
        f"{sum(r.chunks for r in ok)} chunks, "
        f"{sum(r.escalated for r in ok)} pages escalated to vision"
    )
    print(f"chunks written to {out_path}")
    if dry_run:
        print("dry run: nothing was embedded and nothing was written to the database.")
        print("READ THE CHUNKS before a real run (CLAUDE.md #7, #8).")


def main(argv: list[str] | None = None) -> int:
    settings = get_settings()
    parser = argparse.ArgumentParser(description="Ingest a corpus into chunks.")
    parser.add_argument("--dir", help="corpus directory (default: BULLETIN_CORPUS_DIR)")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="chunk only: no embedding call, no database write",
    )
    parser.add_argument(
        "--vision",
        action="store_true",
        help="allow vision escalation during a dry run (costs tokens)",
    )
    parser.add_argument("--institution", help="institution uuid (required for a real run)")
    parser.add_argument(
        "--audience",
        default=Audience.ALL.value,
        choices=[a.value for a in Audience],
        help="audience for every document in this run (default: all)",
    )
    parser.add_argument("--limit", type=int, help="process only the first N files")
    parser.add_argument(
        "--no-resume",
        action="store_true",
        help="ignore page checkpoints and reprocess every page (re-spends vision tokens)",
    )
    parser.add_argument(
        "--out",
        default="eval/reports/chunks.jsonl",
        help="where to write the chunk JSONL",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s %(message)s",
    )
    return run(args, settings)


if __name__ == "__main__":
    raise SystemExit(main())
