"""Shared fixtures for tests that need a disposable local PostgreSQL.

Set ``PITCHY_TEST_DATABASE_URL`` to a local database (CI starts one). Database tests are skipped
otherwise. The reset DROPS the public schema, so it refuses any host other than localhost.
"""

import os
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import psycopg
import pytest
from psycopg.conninfo import conninfo_to_dict
from psycopg.rows import dict_row

from scripts.migrate import apply_pending, apply_seed, discover

TEST_URL = os.environ.get("PITCHY_TEST_DATABASE_URL")
APP_TEST_LOGIN = "pitchy_backend_test"
APP_TEST_PASSWORD = "local-test-only"  # noqa: S105 - throwaway local test login

LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}


def pytest_configure(config) -> None:
    """--basetemp (pyproject: .tmp/pytest, on D:) needs its parent folder; CI starts without it."""
    basetemp = config.option.basetemp
    if basetemp:
        Path(basetemp).resolve().parent.mkdir(parents=True, exist_ok=True)


@pytest.fixture(autouse=True)
def _no_remote_pools(monkeypatch):
    """Tests must never open a pool to a real database (e.g. Supabase from the root .env)."""
    import psycopg_pool

    original = psycopg_pool.ConnectionPool.__init__

    def guarded(self, conninfo="", *args, **kwargs):
        host = conninfo_to_dict(conninfo).get("host")
        if host not in LOCAL_HOSTS:
            raise RuntimeError(f"Test tried to open a pool to a non-local host ({host}).")
        original(self, conninfo, *args, **kwargs)

    monkeypatch.setattr(psycopg_pool.ConnectionPool, "__init__", guarded)


requires_db = pytest.mark.skipif(not TEST_URL, reason="PITCHY_TEST_DATABASE_URL not set")


def _with_user(url: str, user: str, password: str) -> str:
    parts = urlsplit(url)
    netloc = f"{user}:{password}@{parts.hostname}" + (f":{parts.port}" if parts.port else "")
    return urlunsplit((parts.scheme, netloc, parts.path, parts.query, parts.fragment))


@pytest.fixture(scope="session")
def db_url() -> str:
    host = urlsplit(TEST_URL).hostname
    if host not in LOCAL_HOSTS:
        pytest.fail(f"Refusing to reset a non-local database ({host}).")
    with psycopg.connect(TEST_URL, autocommit=True) as conn:
        conn.execute("drop schema if exists supabase_migrations cascade")
        conn.execute("drop schema public cascade")
        conn.execute("create schema public")
        for role in ("anon", "authenticated"):  # mimic Supabase's client roles
            if not conn.execute("select 1 from pg_roles where rolname = %s", (role,)).fetchone():
                conn.execute(f'create role "{role}" nologin')
            conn.execute(f'grant usage on schema public to "{role}"')
        conn.execute(
            "alter default privileges in schema public grant all on tables to anon, authenticated"
        )
        apply_pending(conn, discover())
        apply_seed(conn)
        exists = conn.execute(
            "select 1 from pg_roles where rolname = %s", (APP_TEST_LOGIN,)
        ).fetchone()
        verb = "alter" if exists else "create"
        conn.execute(
            psycopg.sql.SQL("{} role {} login password {}").format(
                psycopg.sql.SQL(verb),
                psycopg.sql.Identifier(APP_TEST_LOGIN),
                psycopg.sql.Literal(APP_TEST_PASSWORD),
            )
        )
        conn.execute(f'grant pitchy_app to "{APP_TEST_LOGIN}"')
        _SEEDED_LOCATIONS[:] = (
            conn.cursor(row_factory=dict_row)
            .execute("select * from public.locations order by scope_key")
            .fetchall()
        )
    return TEST_URL


# Venues come from migrations (P-07). Tests truncate locations, so they are put back each time.
_SEEDED_LOCATIONS: list[dict] = []


def _restore_seeded_locations(conn: psycopg.Connection) -> None:
    for row in _SEEDED_LOCATIONS:
        columns = list(row)
        conn.execute(
            psycopg.sql.SQL("insert into public.locations ({}) values ({})").format(
                psycopg.sql.SQL(", ").join(map(psycopg.sql.Identifier, columns)),
                psycopg.sql.SQL(", ").join(psycopg.sql.Placeholder() * len(columns)),
            ),
            [row[c] for c in columns],
        )


@pytest.fixture(scope="session")
def app_db_url(db_url: str) -> str:
    """Connection string for a login that has only the pitchy_app role."""
    return _with_user(db_url, APP_TEST_LOGIN, APP_TEST_PASSWORD)


@pytest.fixture
def conn(db_url: str):
    with psycopg.connect(db_url, autocommit=True) as c:
        c.execute(
            "truncate public.ingestion_jobs, public.locations, public.anonymous_sessions,"
            " public.alert_checks, public.protocol_documents cascade"
        )
        _restore_seeded_locations(c)
        yield c


@pytest.fixture
def connect(app_db_url: str, conn):
    """Connection factory for repositories, using the least-privilege login."""
    return lambda: psycopg.connect(app_db_url)
