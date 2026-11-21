"""Shared fixtures for tests that need a disposable local PostgreSQL.

Set ``PITCHY_TEST_DATABASE_URL`` to a local database (CI starts one). Database tests are skipped
otherwise. The reset DROPS the public schema, so it refuses any host other than localhost.
"""

import os
from urllib.parse import urlsplit, urlunsplit

import psycopg
import pytest

from scripts.migrate import apply_pending, apply_seed, discover

TEST_URL = os.environ.get("PITCHY_TEST_DATABASE_URL")
APP_TEST_LOGIN = "pitchy_backend_test"
APP_TEST_PASSWORD = "local-test-only"  # noqa: S105 - throwaway local test login

requires_db = pytest.mark.skipif(not TEST_URL, reason="PITCHY_TEST_DATABASE_URL not set")


def _with_user(url: str, user: str, password: str) -> str:
    parts = urlsplit(url)
    netloc = f"{user}:{password}@{parts.hostname}" + (f":{parts.port}" if parts.port else "")
    return urlunsplit((parts.scheme, netloc, parts.path, parts.query, parts.fragment))


@pytest.fixture(scope="session")
def db_url() -> str:
    host = urlsplit(TEST_URL).hostname
    if host not in {"localhost", "127.0.0.1", "::1"}:
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
    return TEST_URL


@pytest.fixture(scope="session")
def app_db_url(db_url: str) -> str:
    """Connection string for a login that has only the pitchy_app role."""
    return _with_user(db_url, APP_TEST_LOGIN, APP_TEST_PASSWORD)


@pytest.fixture
def conn(db_url: str):
    with psycopg.connect(db_url, autocommit=True) as c:
        c.execute(
            "truncate public.ingestion_jobs, public.locations, public.anonymous_sessions cascade"
        )
        yield c


@pytest.fixture
def connect(app_db_url: str, conn):
    """Connection factory for repositories, using the least-privilege login."""
    return lambda: psycopg.connect(app_db_url)
