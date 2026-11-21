"""Apply SQL migrations in ``supabase/migrations/`` to the database (decision M1).

Run from ``backend/``::

    uv run python scripts/migrate.py            # apply pending migrations
    uv run python scripts/migrate.py --status   # list applied / pending, change nothing
    uv run python scripts/migrate.py --seed     # also load supabase/seed/*.sql (not in production)

Uses ``SUPABASE_DB_URL`` from the root ``.env`` unless ``--database-url-env`` names another
variable. Applied versions are recorded in ``supabase_migrations.schema_migrations``, the same
table the Supabase CLI uses, so the CLI can take over later. Each file runs in one transaction.
The connection string is never printed.
"""

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path

import psycopg

BACKEND_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = BACKEND_DIR.parent
MIGRATIONS_DIR = REPO_DIR / "supabase" / "migrations"
SEED_DIR = REPO_DIR / "supabase" / "seed"

_TRACKING_DDL = """
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (
  version text primary key,
  statements text[],
  name text
);
"""


@dataclass(frozen=True)
class Migration:
    version: str
    name: str
    path: Path


def discover(directory: Path = MIGRATIONS_DIR) -> list[Migration]:
    migrations = []
    for path in sorted(directory.glob("*.sql")):
        version, _, name = path.stem.partition("_")
        if not version.isdigit():
            raise ValueError(f"Migration file must start with a numeric version: {path.name}")
        migrations.append(Migration(version, name, path))
    return migrations


def applied_versions(conn: psycopg.Connection) -> set[str]:
    conn.execute(_TRACKING_DDL)
    rows = conn.execute("select version from supabase_migrations.schema_migrations").fetchall()
    return {row[0] for row in rows}


def apply_pending(conn: psycopg.Connection, migrations: list[Migration]) -> list[Migration]:
    """Apply migrations not yet recorded. Returns the ones applied, in order."""
    with conn.transaction():
        done = applied_versions(conn)
    applied = []
    for migration in migrations:
        if migration.version in done:
            continue
        sql = migration.path.read_text(encoding="utf-8")
        with conn.transaction():
            conn.execute(sql)
            conn.execute(
                "insert into supabase_migrations.schema_migrations (version, statements, name)"
                " values (%s, %s, %s)",
                (migration.version, [sql], migration.name),
            )
        applied.append(migration)
    return applied


def apply_seed(conn: psycopg.Connection, directory: Path = SEED_DIR) -> list[Path]:
    files = sorted(directory.glob("*.sql"))
    for path in files:
        with conn.transaction():
            conn.execute(path.read_text(encoding="utf-8"))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--status", action="store_true", help="show status only")
    parser.add_argument("--seed", action="store_true", help="also load development seed files")
    parser.add_argument("--database-url-env", default="SUPABASE_DB_URL")
    args = parser.parse_args()

    sys.path.insert(0, str(BACKEND_DIR))
    from shared.settings import Settings

    settings = Settings()
    if args.database_url_env == "SUPABASE_DB_URL":
        url = settings.supabase_db_url.get_secret_value() if settings.supabase_db_url else None
    else:
        url = os.environ.get(args.database_url_env)
    if not url:
        print(f"{args.database_url_env} is not set (see the root .env).", file=sys.stderr)
        return 2
    if args.seed and settings.env == "production":
        print("Refusing to load development seed data with PITCHY_ENV=production.", file=sys.stderr)
        return 2

    migrations = discover()
    try:
        with psycopg.connect(url, autocommit=True, connect_timeout=15) as conn:
            if args.status:
                done = applied_versions(conn)
                for m in migrations:
                    print(f"{'applied' if m.version in done else 'PENDING'}  {m.path.name}")
                return 0
            applied = apply_pending(conn, migrations)
            print(f"Applied {len(applied)} migration(s).")
            for m in applied:
                print(f"  {m.path.name}")
            if args.seed:
                for path in apply_seed(conn):
                    print(f"Seeded {path.name}")
    except psycopg.OperationalError as exc:
        reason = str(exc).splitlines()[0].replace(url, "<database url>")
        print(f"Could not connect: {reason}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
