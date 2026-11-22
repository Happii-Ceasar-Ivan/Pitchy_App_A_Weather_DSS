"""DEC-11 retention: purge_old_weather_data, run as the backend role (local PostgreSQL)."""

from datetime import UTC, datetime, timedelta

import psycopg
import pytest
from psycopg import errors, sql

from shared.db.records import NewForecastValue
from shared.db.repositories import (
    PgAlertRepository,
    PgForecastRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
    PgRetentionRepository,
)
from tests.conftest import requires_db

pytestmark = requires_db
DAY = timedelta(days=1)
T = datetime(2026, 12, 1, tzinfo=UTC)


def _values(n=3):
    return [NewForecastValue("temperature_2m", 30.0, "°C", "ok", T + i * timedelta(hours=1),
                             T + (i + 1) * timedelta(hours=1), None) for i in range(n)]  # fmt: skip


def _fetch(connect, conn, source, scope, age: timedelta, status="succeeded", job=None):
    loc = PgLocationRepository(connect).get_by_scope_key(scope)
    repo = PgForecastRepository(connect)
    if status == "succeeded":
        fid = repo.record_fetch(source, loc.id, job, _values())
    else:
        fid = repo.record_failed_fetch(source, loc.id, job, "HTTP_503", "down")
    conn.execute(
        "update public.source_fetches set requested_at = requested_at - %s,"
        " completed_at = completed_at - %s where id = %s",
        (age, age, fid),
    )
    return fid


def _exists(conn, table, row_id) -> bool:
    query = sql.SQL("select 1 from public.{} where id = %s").format(sql.Identifier(table))
    return conn.execute(query, (row_id,)).fetchone() is not None


def _purge(connect):
    return PgRetentionRepository(connect).purge(14 * DAY, 30 * DAY)


def test_old_forecasts_rotate_but_the_newest_per_source_and_venue_stays(connect, conn) -> None:
    oldest = _fetch(connect, conn, "open_meteo", "rizal_memorial", 20 * DAY)
    old = _fetch(connect, conn, "open_meteo", "rizal_memorial", 15 * DAY)
    recent = _fetch(connect, conn, "open_meteo", "rizal_memorial", 2 * DAY)
    only_clark = _fetch(connect, conn, "open_meteo", "new_clark_city", 40 * DAY)  # newest there

    deleted = _purge(connect)
    assert deleted["source_fetches_deleted"] == 2
    assert deleted["forecast_values_deleted"] == 6
    assert not _exists(conn, "source_fetches", oldest) and not _exists(conn, "source_fetches", old)
    assert _exists(conn, "source_fetches", recent) and _exists(conn, "source_fetches", only_clark)
    assert _purge(connect)["source_fetches_deleted"] == 0  # idempotent


def test_newest_attempt_is_kept_even_when_it_failed(connect, conn) -> None:
    success = _fetch(connect, conn, "pagasa_atmo", "rizal_memorial", 30 * DAY)
    failure = _fetch(connect, conn, "pagasa_atmo", "rizal_memorial", 20 * DAY, status="failed")
    _purge(connect)
    assert _exists(conn, "source_fetches", success)  # newest successful
    assert _exists(conn, "source_fetches", failure)  # newest attempt (4-hour rule, cooldown)


def test_values_used_by_an_assessment_are_never_deleted(connect, conn) -> None:
    used = _fetch(connect, conn, "open_meteo", "rizal_memorial", 20 * DAY)
    _fetch(connect, conn, "open_meteo", "rizal_memorial", 1 * DAY)
    value_id, location_id = conn.execute(
        "select id, location_id from public.forecast_values where fetch_id = %s limit 1", (used,)
    ).fetchone()
    match = conn.execute(
        "insert into public.match_contexts (kickoff_at, location_id) values (now(), %s)"
        " returning id", (location_id,),
    ).fetchone()[0]  # fmt: skip
    assessment = conn.execute(
        "insert into public.safety_assessments (match_context_id, rule_version, result)"
        " values (%s, 'test', '{}') returning id", (match,),
    ).fetchone()[0]  # fmt: skip
    conn.execute("insert into public.assessment_inputs values (%s, %s, 'heat')",
                 (assessment, value_id))  # fmt: skip

    _purge(connect)
    assert _exists(conn, "source_fetches", used)
    assert _exists(conn, "forecast_values", value_id)


def test_old_finished_jobs_rotate_active_and_referenced_ones_stay(connect, conn) -> None:
    jobs = PgIngestionJobRepository(connect)
    loc = PgLocationRepository(connect).get_by_scope_key("rizal_memorial")

    def job(scope, finish=True):
        j = jobs.acquire(scope, "open_meteo", loc.id, timedelta(days=60)).job
        if finish:
            jobs.finish(j.id, succeeded=True)
        conn.execute("update public.ingestion_jobs set requested_at = requested_at - %s"
                     " where id = %s", (40 * DAY, j.id))  # fmt: skip
        return j.id

    old_done = job("open_meteo:a")
    active = job("open_meteo:b", finish=False)
    referenced = job("open_meteo:c")
    _fetch(connect, conn, "open_meteo", "rizal_memorial", 1 * DAY, job=referenced)

    assert _purge(connect)["ingestion_jobs_deleted"] == 1
    assert not _exists(conn, "ingestion_jobs", old_done)
    assert _exists(conn, "ingestion_jobs", active) and _exists(conn, "ingestion_jobs", referenced)


def test_old_alert_checks_rotate_but_the_newest_ones_stay(connect, conn) -> None:
    repo = PgAlertRepository(connect)
    alert = {"identifier": "x", "issuer": "PRSD", "event": "THUNDERSTORM", "subtype": "s",
             "headline": "h", "message": "m", "issued_at": None, "valid_until": None,
             "areas": [], "matched_venues": []}  # fmt: skip
    old_success = repo.record_check(None, [alert], 0)
    newer_success = repo.record_check(None, [alert], 0)
    newest_failed = repo.record_failed_check(None, "HTTP_503", "down")
    for check, age in ((old_success, 50), (newer_success, 40), (newest_failed, 35)):
        conn.execute("update public.alert_checks set checked_at = now() - %s where id = %s",
                     (age * DAY, check))  # fmt: skip

    deleted = _purge(connect)
    assert (deleted["alert_checks_deleted"], deleted["official_alerts_deleted"]) == (1, 1)
    assert not _exists(conn, "alert_checks", old_success)
    assert _exists(conn, "alert_checks", newer_success)  # newest successful
    assert _exists(conn, "alert_checks", newest_failed)  # newest overall


def test_periods_shorter_than_a_day_are_refused(connect) -> None:
    with pytest.raises(errors.RaiseException):
        PgRetentionRepository(connect).purge(timedelta(hours=1), 30 * DAY)


def test_only_the_backend_role_may_run_the_purge(conn, app_db_url) -> None:
    for role in ("anon", "authenticated"):
        allowed = conn.execute(
            "select has_function_privilege(%s,"
            " 'public.purge_old_weather_data(interval, interval)', 'execute')",
            (role,),
        ).fetchone()[0]
        assert not allowed
    with psycopg.connect(app_db_url, autocommit=True) as app:
        with pytest.raises(errors.InsufficientPrivilege):
            app.execute("delete from public.forecast_values")
