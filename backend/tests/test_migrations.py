"""Migration, RLS, privilege and ingestion-lock tests (local PostgreSQL; see conftest.py)."""

import threading
import time
from datetime import UTC, datetime, timedelta

import psycopg
import pytest
from psycopg import errors

from scripts.migrate import apply_pending, discover
from tests.conftest import requires_db

TABLES = {
    "weather_sources", "locations", "match_contexts", "ingestion_jobs", "source_fetches",
    "forecast_values", "safety_assessments", "assessment_inputs", "protocol_documents",
    "protocol_chunks", "anonymous_sessions", "alert_checks", "official_alerts",
    "lightning_checks",
}  # fmt: skip

pytestmark = requires_db


def _location(conn: psycopg.Connection, scope_key: str = "test-scope") -> str:
    return conn.execute(
        "insert into public.locations (name, latitude, longitude, scope_key)"
        " values ('Test venue', 14.6, 121.0, %s) returning id",
        (scope_key,),
    ).fetchone()[0]


def _new_job(conn: psycopg.Connection, location_id, scope_key: str = "pagasa:test-scope"):
    lease = datetime.now(UTC) + timedelta(minutes=5)
    return conn.execute(
        "insert into public.ingestion_jobs (scope_key, source_id, location_id, state,"
        " started_at, lease_expires_at) values (%s, 'pagasa', %s, 'running', now(), %s)"
        " returning id",
        (scope_key, location_id, lease),
    ).fetchone()[0]


def test_migrations_are_recorded_and_idempotent(db_url: str) -> None:
    with psycopg.connect(db_url, autocommit=True) as conn:
        assert apply_pending(conn, discover()) == []
        versions = conn.execute("select version from supabase_migrations.schema_migrations")
        assert {row[0] for row in versions} == {m.version for m in discover()}


def test_all_tables_exist_with_rls_and_no_client_access(conn: psycopg.Connection) -> None:
    rows = conn.execute(
        "select c.relname, c.relrowsecurity from pg_class c"
        " join pg_namespace n on n.oid = c.relnamespace"
        " where n.nspname = 'public' and c.relkind = 'r'"
    ).fetchall()
    assert {name for name, _ in rows} == TABLES
    assert all(rls for _, rls in rows)
    for table in TABLES:
        for role in ("anon", "authenticated"):
            for privilege in ("select", "insert", "update", "delete"):
                allowed = conn.execute(
                    "select has_table_privilege(%s, %s, %s)", (role, f"public.{table}", privilege)
                ).fetchone()[0]
                assert not allowed, f"{role} has {privilege} on {table}"


def test_only_the_backend_role_has_policies(conn: psycopg.Connection) -> None:
    rows = conn.execute(
        "select tablename, roles from pg_policies where schemaname = 'public'"
    ).fetchall()
    assert {table for table, _ in rows} == TABLES
    assert all(roles == ["pitchy_app"] for _, roles in rows)


def test_backend_role_can_read_and_write_but_not_delete_or_alter(app_db_url: str, conn) -> None:
    location = _location(conn)
    with psycopg.connect(app_db_url, autocommit=True) as app:
        assert app.execute("select count(*) from public.weather_sources").fetchone()[0] == 6
        app.execute("update public.locations set name = 'renamed' where id = %s", (location,))
        with pytest.raises(errors.InsufficientPrivilege):
            app.execute("delete from public.locations where id = %s", (location,))
        with pytest.raises(errors.InsufficientPrivilege):
            app.execute("truncate public.weather_sources")
        with pytest.raises(errors.InsufficientPrivilege):
            app.execute("drop table public.weather_sources")
        with pytest.raises(errors.InsufficientPrivilege):
            app.execute("select * from supabase_migrations.schema_migrations")


def test_sources_enabled_only_with_a_tested_adapter(conn: psycopg.Connection) -> None:
    rows = conn.execute("select id, enabled from public.weather_sources order by id").fetchall()
    assert rows == [
        ("dost_asti", False), ("open_meteo", True), ("pagasa", False),
        ("pagasa_atmo", True), ("pagasa_ecmwf", True), ("xweather_lightning", True),
    ]  # fmt: skip


def test_second_active_job_for_same_scope_is_rejected(conn: psycopg.Connection) -> None:
    location = _location(conn)
    _new_job(conn, location)
    with pytest.raises(errors.UniqueViolation):
        _new_job(conn, location)


def test_unrelated_scopes_do_not_block_each_other(conn: psycopg.Connection) -> None:
    location = _location(conn)
    _new_job(conn, location, "pagasa:test-scope")
    _new_job(conn, location, "pagasa:other-scope")


def test_finished_job_releases_the_lock(conn: psycopg.Connection) -> None:
    location = _location(conn)
    for final_state in ("succeeded", "failed", "expired"):
        job = _new_job(conn, location)
        conn.execute(
            "update public.ingestion_jobs set state = %s, finished_at = now() where id = %s",
            (final_state, job),
        )
    _new_job(conn, location)


def test_finished_state_requires_finished_at(conn: psycopg.Connection) -> None:
    job = _new_job(conn, _location(conn))
    with pytest.raises(errors.CheckViolation):
        conn.execute("update public.ingestion_jobs set state = 'succeeded' where id = %s", (job,))


def test_concurrent_acquisition_only_one_wins(db_url: str, conn: psycopg.Connection) -> None:
    location = _location(conn)
    results: dict[str, str] = {}

    with psycopg.connect(db_url) as first:  # transaction stays open until commit
        _new_job(first, location)

        def second_attempt() -> None:
            with psycopg.connect(db_url, autocommit=True) as second:
                try:
                    _new_job(second, location)
                    results["second"] = "acquired"
                except errors.UniqueViolation:
                    results["second"] = "rejected"

        worker = threading.Thread(target=second_attempt)
        worker.start()
        time.sleep(0.5)
        assert worker.is_alive(), "second insert should wait for the first transaction"
        first.commit()
        worker.join(timeout=10)

    assert results == {"second": "rejected"}


def test_ok_value_requires_a_number(conn: psycopg.Connection) -> None:
    location = _location(conn)
    fetch = conn.execute(
        "insert into public.source_fetches (source_id, location_id, status)"
        " values ('pagasa', %s, 'succeeded') returning id",
        (location,),
    ).fetchone()[0]
    insert = (
        "insert into public.forecast_values (fetch_id, source_id, location_id, parameter, value,"
        " value_state, retrieved_at) values (%s, 'pagasa', %s, 'p', %s, %s, now())"
    )
    conn.execute(insert, (fetch, location, None, "missing"))
    with pytest.raises(errors.CheckViolation):
        conn.execute(insert, (fetch, location, None, "ok"))


def test_assessment_inputs_cannot_be_deleted(conn: psycopg.Connection) -> None:
    location = _location(conn)
    fetch = conn.execute(
        "insert into public.source_fetches (source_id, location_id, status)"
        " values ('pagasa', %s, 'succeeded') returning id",
        (location,),
    ).fetchone()[0]
    value = conn.execute(
        "insert into public.forecast_values (fetch_id, source_id, location_id, parameter, value,"
        " retrieved_at) values (%s, 'pagasa', %s, 'p', 1.0, now()) returning id",
        (fetch, location),
    ).fetchone()[0]
    match = conn.execute(
        "insert into public.match_contexts (kickoff_at, location_id) values (now(), %s)"
        " returning id",
        (location,),
    ).fetchone()[0]
    assessment = conn.execute(
        "insert into public.safety_assessments (match_context_id, rule_version, result)"
        " values (%s, 'test', '{}') returning id",
        (match,),
    ).fetchone()[0]
    conn.execute(
        "insert into public.assessment_inputs values (%s, %s, 'heat')", (assessment, value)
    )
    with pytest.raises(errors.ForeignKeyViolation):
        conn.execute("delete from public.forecast_values where id = %s", (value,))


def test_venues_have_their_alert_codes(connect) -> None:
    from shared.db.repositories import PgLocationRepository

    venues = {v.scope_key: v for v in PgLocationRepository(connect).list_all()}
    assert venues["rizal_memorial"].alert_codes == {"133910000", "133900000", "130000000"}
    assert venues["new_clark_city"].alert_codes == {"036904000", "036900000"}


def test_submunicipality_code_must_be_nine_digits(conn: psycopg.Connection) -> None:
    with pytest.raises(errors.CheckViolation):
        conn.execute(
            "update public.locations set submunicipality_psgc_code = '1380610000'"
            " where scope_key = 'rizal_memorial'"
        )


def test_only_the_alerts_job_may_have_no_venue(conn: psycopg.Connection) -> None:
    insert = (
        "insert into public.ingestion_jobs (scope_key, source_id, location_id, state,"
        " started_at, lease_expires_at) values (%s, 'pagasa', null, 'running', now(),"
        " now() + interval '5 minutes')"
    )
    conn.execute(insert, ("pagasa_alerts",))
    with pytest.raises(errors.CheckViolation):
        conn.execute(insert, ("pagasa:somewhere",))
