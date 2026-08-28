"""Apply SQL migrations to Supabase Postgres.

    python -m tools.db_migrate --check    # connection + extensions only, no writes
    python -m tools.db_migrate            # apply pending migrations
    python -m tools.db_migrate --verify   # assert RLS is actually on afterwards

Migrations are applied in filename order and recorded in `schema_migrations`, so
re-running is safe. Each file runs inside one transaction: a migration either
lands whole or not at all, because a half-applied schema with RLS partially
enabled is worse than no schema (CLAUDE.md #5).
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import sys
from pathlib import Path

from app.config import ConfigError, Settings, get_settings
from app.db.connection import connect

logger = logging.getLogger(__name__)

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "app" / "db" / "migrations"

# Every table in PRD 9. RLS must be on for all of them -- verified, not assumed.
EXPECTED_RLS_TABLES = (
    "institutions",
    "profiles",
    "documents",
    "chunks",
    "conversations",
    "messages",
    "attachments",
)

BOOTSTRAP = """
create table if not exists schema_migrations (
  filename    text primary key,
  checksum    text not null,
  applied_at  timestamptz not null default now()
);
"""


def _connect(settings: Settings):
    try:
        return connect(settings, autocommit=False)
    except ConfigError as exc:
        raise SystemExit(str(exc)) from exc


def migration_files() -> list[Path]:
    return sorted(MIGRATIONS_DIR.glob("*.sql"))


def _checksum(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def check(settings: Settings) -> int:
    """Connection and prerequisites only. Writes nothing."""
    with _connect(settings) as conn, conn.cursor() as cur:
        cur.execute("select current_database(), current_user, version()")
        db, user, version = cur.fetchone()
        print(f"connected  : {db} as {user}")
        print(f"postgres   : {version.split(',')[0]}")

        cur.execute("select extname from pg_extension order by extname")
        installed = {r[0] for r in cur.fetchall()}
        for ext in ("vector", "pg_trgm"):
            mark = "ok" if ext in installed else "MISSING (the migration creates it)"
            print(f"extension  : {ext} -- {mark}")

        cur.execute(
            "select table_name from information_schema.tables "
            "where table_schema = 'public' order by table_name"
        )
        tables = [r[0] for r in cur.fetchall()]
        print(f"tables     : {', '.join(tables) if tables else '(none yet)'}")
        conn.rollback()
    return 0


def applied(conn) -> dict[str, str]:
    with conn.cursor() as cur:
        cur.execute(BOOTSTRAP)
        cur.execute("select filename, checksum from schema_migrations")
        return dict(cur.fetchall())


def migrate(settings: Settings, *, dry_run: bool = False) -> int:
    files = migration_files()
    if not files:
        print(f"No migrations found in {MIGRATIONS_DIR}", file=sys.stderr)
        return 2

    with _connect(settings) as conn:
        done = applied(conn)
        conn.commit()

        pending = []
        for path in files:
            checksum = _checksum(path)
            if path.name not in done:
                pending.append((path, checksum))
            elif done[path.name] != checksum:
                # An applied migration was edited. Silently re-running it would
                # produce a schema nobody can reason about.
                print(
                    f"REFUSING: {path.name} was modified after it was applied "
                    f"(recorded {done[path.name]}, now {checksum}).\n"
                    "Write a new migration instead of editing an applied one.",
                    file=sys.stderr,
                )
                return 1

        if not pending:
            print("Nothing to apply; schema is up to date.")
            return 0

        for path, checksum in pending:
            print(f"applying   : {path.name}", file=sys.stderr)
            if dry_run:
                continue
            try:
                with conn.cursor() as cur:
                    cur.execute(path.read_text(encoding="utf-8"))
                    cur.execute(
                        "insert into schema_migrations (filename, checksum) values (%s, %s)",
                        (path.name, checksum),
                    )
                conn.commit()
                print(f"applied    : {path.name}")
            except Exception as exc:
                conn.rollback()
                print(f"\nFAILED on {path.name}, rolled back:\n{exc}", file=sys.stderr)
                return 1
    return 0


def verify(settings: Settings) -> int:
    """Assert RLS is enabled and the audience policy exists.

    CLAUDE.md #5: "Do not filter in Python and call it done." This checks the
    database itself rather than trusting that the migration did what it said.
    """
    failures: list[str] = []
    with _connect(settings) as conn, conn.cursor() as cur:
        cur.execute(
            "select relname, relrowsecurity from pg_class "
            "where relname = any(%s) and relkind = 'r'",
            (list(EXPECTED_RLS_TABLES),),
        )
        found = dict(cur.fetchall())
        for table in EXPECTED_RLS_TABLES:
            if table not in found:
                failures.append(f"table {table} does not exist")
            elif not found[table]:
                failures.append(f"RLS is DISABLED on {table}")
            else:
                print(f"rls on     : {table}")

        cur.execute("select tablename, policyname from pg_policies where schemaname = 'public'")
        policies = cur.fetchall()
        by_table: dict[str, list[str]] = {}
        for tablename, policyname in policies:
            by_table.setdefault(tablename, []).append(policyname)

        for table in EXPECTED_RLS_TABLES:
            names = by_table.get(table, [])
            if not names:
                # RLS on with no policy denies everything -- safe, but broken.
                failures.append(f"{table} has RLS on but NO policy (denies all reads)")
            else:
                print(f"policies   : {table} -- {', '.join(sorted(names))}")

        cur.execute(
            "select count(*) from information_schema.columns "
            "where table_name = 'attachments' and column_name = 'embedding'"
        )
        if cur.fetchone()[0]:
            failures.append("attachments has an `embedding` column -- CLAUDE.md #2 forbids it")
        conn.rollback()

    if failures:
        print("\nVERIFY FAILED:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print("\nVERIFY OK: RLS enabled with policies on every table.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="connection only, no writes")
    parser.add_argument("--verify", action="store_true", help="assert RLS is on")
    parser.add_argument("--dry-run", action="store_true", help="list pending migrations")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s", stream=sys.stderr)
    settings = get_settings()

    if args.check:
        return check(settings)
    if args.verify:
        return verify(settings)
    return migrate(settings, dry_run=args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
