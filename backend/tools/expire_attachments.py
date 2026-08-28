"""Delete attachment images past their TTL. PRD 8.4.

    python -m tools.expire_attachments --dry-run
    python -m tools.expire_attachments

A student's routine carries their name, student ID, and schedule. PRD 8.4 keeps
the image for seven days so chat history can show what was attached, and keeps
the extracted JSON with the message forever. This job is what makes the first
half of that sentence true.

**The row is kept, the file is deleted.** `extracted_json` is what the join
answer was built from and what the conversation shows; the image is only the
thumbnail. Deleting the row would erase the message's own history.

Run it on a schedule (a cron on the host, or a Supabase scheduled function).
It is idempotent: a file already gone is a no-op, and a row already cleared is
skipped by the `storage_path is not null` predicate.
"""

from __future__ import annotations

import argparse
import logging
import sys
from collections import defaultdict

from app.config import ConfigError, Settings, get_settings
from app.db import storage
from app.db.connection import connect, describe

logger = logging.getLogger(__name__)

EXPIRED_SQL = """
select id::text, storage_path, image_expires_at
from attachments
where image_expires_at < now() and storage_path is not null
order by image_expires_at
limit %(limit)s
"""

CLEAR_PATH_SQL = """
update attachments set storage_path = null where id = any(%(ids)s::uuid[])
"""


def expire(settings: Settings, *, limit: int = 500, dry_run: bool = False) -> int:
    """Delete expired images. Returns how many rows were cleared."""
    with connect(settings) as conn:
        with conn.cursor() as cur:
            cur.execute(EXPIRED_SQL, {"limit": limit})
            rows = cur.fetchall()

        if not rows:
            print("nothing expired")
            return 0

        by_bucket: dict[str, list[str]] = defaultdict(list)
        ids: list[str] = []
        for attachment_id, path, expires_at in rows:
            bucket, _, object_path = str(path).partition("/")
            if object_path:
                by_bucket[bucket].append(object_path)
            ids.append(attachment_id)
            print(f"  {attachment_id}  expired {expires_at:%Y-%m-%d}  {path}")

        if dry_run:
            print(f"\ndry run: {len(ids)} image(s) would be deleted, rows kept")
            return 0

        for bucket, paths in by_bucket.items():
            try:
                storage.remove(bucket=bucket, paths=paths, settings=settings)
            except storage.StorageError as exc:
                # A missing object is the desired end state anyway; a real
                # outage is worth reporting but must not stop the run.
                logger.warning("could not delete from %s: %s", bucket, exc)

        with conn.cursor() as cur:
            cur.execute(CLEAR_PATH_SQL, {"ids": ids})
        conn.commit()

    print(f"\ndeleted {len(ids)} image(s); the extracted data and messages are untouched")
    return len(ids)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Delete attachment images past their TTL.")
    parser.add_argument("--dry-run", action="store_true", help="list what would go, delete nothing")
    parser.add_argument("--limit", type=int, default=500)
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s %(message)s",
    )
    settings = get_settings()

    try:
        print(f"database   : {describe(settings)}")
        print(f"ttl        : {settings.attachment_image_ttl_days} days")
        expire(settings, limit=args.limit, dry_run=args.dry_run)
    except ConfigError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
