"""Discover new notices on the institution's website and fetch them.

    python -m tools.watch_notices                      # what is new? (no downloads)
    python -m tools.watch_notices --fetch              # download new ones to the corpus
    python -m tools.watch_notices --fetch --only <slug> --only <slug>
    python -m tools.watch_notices --fetch --skip disciplinary

Then ingest with the tool that already exists:

    python -m tools.ingest_corpus --dry-run
    python -m tools.ingest_corpus --institution <uuid> --audience all

THIS TOOL DOES NOT INGEST, AND THAT IS THE DESIGN

`ingest_corpus.py` already handles chunking, checkpointing, re-ingest inside a
transaction, and the dry-run that CLAUDE.md #7 requires on any new corpus.
Duplicating that here would create a second path through the pipeline, and the
second path is the one that quietly stops matching the first.

So this tool has one job: turn a website into files in the corpus. What is
"new" is answered by the corpus itself, so there is no state file to drift.

That answer is by **content**, not by filename, and the difference is not
academic. The registrar's own downloads are named by upload timestamp
(`notice-holiday-...-1787478763.pdf`) while this tool names by slug, and two
different notices sometimes link to the same file. Deduplicating on names put
seven copies of six documents into the corpus on the first run. A hash of the
bytes, checked against every file already in the tree, does not care what
anything is called.

WHY IT DOES NOT PUBLISH BY ITSELF

Two of the notices on this feed today are disciplinary actions that name
students and print their student IDs. Ingesting the feed unattended would put
one student's punishment into a vector index every other student can query —
the harm CLAUDE.md #2 forbids for attachments, arriving through a different
door. PRD §5 also requires an audience with no default, and no scraper can
choose one.

So a human runs this, reads the list, and decides. Titles that look like they
concern individuals are marked in the listing; the mark is a prompt to think,
not a filter to trust.

POLITENESS

`green.edu.bd/robots.txt` allows `/notice` explicitly. The PDFs live on
`admin.green.edu.bd`, which sends `Disallow: /` — a blanket rule that reads
like a CMS default rather than a policy about files it embeds in a public
allowed page, but it is a rule. Fetching here is user-initiated, one request a
second, with a User-Agent that says who is calling and why. If this project
ever runs unattended, ask the registrar for permission first.
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from app.config import Settings, get_settings

logger = logging.getLogger(__name__)

LISTING_URL = "https://green.edu.bd/notice"
DETAIL_RE = re.compile(r'href="(https://green\.edu\.bd/notice-details/[^"]+)"')
# Notices attach whatever the registrar uploaded. Most are PDFs; the exam
# routines — the highest-value documents on the feed — are .xlsx, which is
# better news than it sounds: a spreadsheet has no OCR layer to be wrong.
ATTACHMENT_RE = re.compile(
    r'"(https://admin\.green\.edu\.bd/storage/files/[^"?]+\.[A-Za-z0-9]{2,5})'
)

# What ingest_corpus can actually read today (app/ingest/extract.py).
INGESTIBLE = {".pdf", ".png", ".jpg", ".jpeg", ".webp"}
TITLE_RE = re.compile(r"<h1[^>]*>(.*?)</h1>", re.S | re.I)
TAG_RE = re.compile(r"<[^>]+>")

# Identifies the caller. A scraper that hides what it is gives an administrator
# no way to contact anyone or to allow it deliberately.
USER_AGENT = (
    "BulletinResearchBot/0.1 (university notice indexing; "
    "https://github.com/Art3MasA005/bulletin)"
)

# One request a second. This is somebody's server and nothing here is urgent.
DELAY_SECONDS = 1.0

# Titles that suggest the notice is about named individuals rather than about
# the institution. Flagged in the listing, never filtered automatically: a
# keyword list is not a privacy control, and treating it as one would be worse
# than having none, because it would invite trusting it.
PERSONAL_HINTS = ("disciplinary", "expel", "suspend", "punish", "show cause", "termination")


@dataclass(frozen=True)
class Notice:
    slug: str
    url: str
    title: str

    def existing(self, corpus: Path) -> Path | None:
        """Any already-downloaded file for this notice, whatever its format."""
        for path in corpus.glob(f"{self.slug}.*"):
            return path
        return None

    @property
    def looks_personal(self) -> bool:
        haystack = f"{self.slug} {self.title}".lower()
        return any(hint in haystack for hint in PERSONAL_HINTS)


def _get(url: str, timeout: int = 45) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def list_notices() -> list[Notice]:
    """Every notice currently on the listing page, newest first."""
    html = _get(LISTING_URL).decode("utf-8", "ignore")
    seen: dict[str, Notice] = {}
    for match in DETAIL_RE.finditer(html):
        url = match.group(1)
        slug = url.rstrip("/").rsplit("/", 1)[-1]
        if slug not in seen:
            seen[slug] = Notice(slug=slug, url=url, title=slug.replace("-", " "))
    return list(seen.values())


def resolve_attachment(notice: Notice) -> tuple[str | None, str]:
    """The attachment url on a notice's detail page, and its real title."""
    html = _get(notice.url).decode("utf-8", "ignore")
    title_match = TITLE_RE.search(html)
    title = notice.title
    if title_match:
        cleaned = TAG_RE.sub("", title_match.group(1))
        if cleaned.strip():
            title = " ".join(cleaned.split())
    match = ATTACHMENT_RE.search(html)
    return (match.group(1).split("#")[0] if match else None), title


def known_hashes(root: Path) -> set[str]:
    """A digest of every file already in the corpus tree, at any depth."""
    return {
        hashlib.sha256(f.read_bytes()).hexdigest()
        for f in root.rglob("*")
        if f.is_file() and f.stat().st_size > 0
    }


def fetch(notice: Notice, target: Path, known: set[str] | None = None) -> str | None:
    """Download one notice's attachment. Returns the suffix written, or None.

    The suffix is returned rather than a bool because the caller has to report
    which formats arrived: a notice whose routine is an .xlsx is not a failure,
    it is a document this pipeline cannot read *yet*, and silently dropping it
    would hide the most valuable page on the feed.
    """
    url, _title = resolve_attachment(notice)
    if url is None:
        logger.warning("no attachment slug=%s", notice.slug)
        return None

    suffix = Path(url).suffix.lower()
    try:
        body = _get(url, timeout=90)
    except urllib.error.HTTPError as exc:
        logger.warning("fetch failed slug=%s status=%s", notice.slug, exc.code)
        return None

    # An error page served with a 200 would otherwise land in the corpus as a
    # "document" and fail much later, inside extraction.
    if suffix == ".pdf" and not body.startswith(b"%PDF"):
        logger.warning("not a pdf slug=%s bytes=%d", notice.slug, len(body))
        return None
    if len(body) < 512:
        logger.warning("suspiciously small slug=%s bytes=%d", notice.slug, len(body))
        return None

    digest = hashlib.sha256(body).hexdigest()
    if known is not None and digest in known:
        # Same bytes, different name: the registrar's own upload, or a second
        # notice linking the same file.
        logger.info("already in the corpus under another name slug=%s", notice.slug)
        return None
    if known is not None:
        known.add(digest)

    (target / f"{notice.slug}{suffix}").write_bytes(body)
    logger.info("fetched slug=%s%s bytes=%d", notice.slug, suffix, len(body))
    return suffix


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="download; default is to list only")
    parser.add_argument("--only", action="append", default=[], help="slug substring; repeatable")
    parser.add_argument("--skip", action="append", default=[], help="slug substring; repeatable")
    parser.add_argument(
        "--dir",
        help="where to write (default: BULLETIN_CORPUS_DIR/inbox, alongside manual downloads)",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(message)s",
        stream=sys.stderr,
    )
    settings: Settings = get_settings()
    root = settings.corpus_path
    # New arrivals land in `inbox/`, which is where manual downloads already
    # go. Writing to the corpus root instead scattered them across two
    # conventions and made the duplicates below harder to see.
    target = Path(args.dir) if args.dir else root / "inbox"
    target.mkdir(parents=True, exist_ok=True)
    known = known_hashes(root)

    try:
        notices = list_notices()
    except Exception as exc:  # noqa: BLE001 -- a site change should read as one line, not a stack
        print(f"could not read {LISTING_URL}: {exc}", file=sys.stderr)
        return 1

    def selected(notice: Notice) -> bool:
        if args.only and not any(s.lower() in notice.slug.lower() for s in args.only):
            return False
        return not any(s.lower() in notice.slug.lower() for s in args.skip)

    new = [n for n in notices if selected(n) and n.existing(target) is None]
    have = len(notices) - len(new)

    # "unseen" rather than "new": this listing can only compare names. Whether
    # a notice is genuinely new is settled by its bytes at fetch time, and a
    # file the registrar uploaded under a different name is skipped there.
    print(f"{len(notices)} listed · {have} already in {target} by name · {len(new)} unseen")
    if not new:
        return 0

    print()
    for notice in new:
        mark = "  ⚠ names individuals?" if notice.looks_personal else ""
        print(f"  {notice.slug[:66]}{mark}")

    if not args.fetch:
        print("\nNothing downloaded. Re-run with --fetch, or --only/--skip to choose.")
        print("Anything already held under another name is skipped at fetch time.")
        return 0

    print()
    written: dict[str, int] = {}
    skipped = 0
    for index, notice in enumerate(new):
        if index:
            time.sleep(DELAY_SECONDS)
        try:
            suffix = fetch(notice, target, known)
        except Exception as exc:  # noqa: BLE001 -- one bad notice must not end the run
            # The type is printed, not swallowed: an AttributeError here is a
            # bug in this file, and a run that only said "failed" would read
            # like the site was down.
            print(f"  failed   {notice.slug[:56]}  ({type(exc).__name__}: {exc})")
            continue
        if suffix is None:
            print(f"  skipped  {notice.slug[:62]}")
            skipped += 1
            continue
        written[suffix] = written.get(suffix, 0) + 1
        note = "" if suffix in INGESTIBLE else "   <-- ingest cannot read this yet"
        print(f"  fetched  {notice.slug[:52]}{suffix}{note}")

    total = sum(written.values())
    print(f"\n{total} file(s) written to {target}, {skipped} already held under another name")
    for suffix, count in sorted(written.items()):
        mark = "" if suffix in INGESTIBLE else "   NOT ingestible yet"
        print(f"    {count:>3} x {suffix}{mark}")
    print("\nNext, and read the dry run before the real one (CLAUDE.md #7):")
    print("    python -m tools.ingest_corpus --dry-run")
    print("    python -m tools.ingest_corpus --institution <uuid> --audience <audience>")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
