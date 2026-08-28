"""Create the institution row an ingest run needs.

    python -m tools.db_seed --name "Green University of Bangladesh"
    python -m tools.db_seed --list

`tools.ingest_corpus --institution <uuid>` needs an institution to attach
documents to, and the invite-code join flow (PRD 4) needs one to join. This
creates exactly that row and prints the uuid. It does NOT create profiles:
those reference `auth.users`, so a person has to sign up first.

Idempotent by name -- running it twice returns the existing row rather than
creating a second institution with the same name and a different id, which
would silently split the corpus in two.
"""

from __future__ import annotations

import argparse
import logging
import secrets
import sys

from app.config import ConfigError, Settings, get_settings
from app.db.connection import connect, describe

logger = logging.getLogger(__name__)

# Unambiguous alphabet: no O/0, I/1, so a code read off a screen and typed on a
# phone lands on the right institution.
_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
INVITE_CODE_LENGTH = 8


def invite_code() -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(INVITE_CODE_LENGTH))


def seed(settings: Settings, *, name: str) -> tuple[str, str, bool]:
    """Return (id, invite_code, created)."""
    with connect(settings) as conn, conn.cursor() as cur:
        cur.execute("select id::text, invite_code from institutions where name = %s", (name,))
        row = cur.fetchone()
        if row:
            return row[0], row[1], False

        code = invite_code()
        cur.execute(
            "insert into institutions (name, invite_code) values (%s, %s) returning id::text",
            (name, code),
        )
        new_id = cur.fetchone()[0]
        conn.commit()
        return new_id, code, True


def listing(settings: Settings) -> int:
    with connect(settings) as conn, conn.cursor() as cur:
        cur.execute(
            "select id::text, name, invite_code,"
            " (select count(*) from documents d where d.institution_id = i.id),"
            " (select count(*) from chunks c where c.institution_id = i.id)"
            " from institutions i order by created_at"
        )
        rows = cur.fetchall()

    if not rows:
        print("no institutions yet -- run without --list to create one")
        return 0
    for institution_id, name, code, docs, chunks in rows:
        print(f"{institution_id}  {name}  invite={code}  documents={docs} chunks={chunks}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Create or list institutions.")
    parser.add_argument("--name", default="Green University of Bangladesh")
    parser.add_argument("--list", action="store_true", help="list institutions and exit")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s %(message)s",
    )
    settings = get_settings()

    try:
        if args.list:
            return listing(settings)
        institution_id, code, created = seed(settings, name=args.name)
    except ConfigError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    print(f"database   : {describe(settings)}")
    print(f"institution: {institution_id}  ({'created' if created else 'already existed'})")
    print(f"name       : {args.name}")
    print(f"invite code: {code}")
    print(f"\nNext:\n  python -m tools.ingest_corpus --institution {institution_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
