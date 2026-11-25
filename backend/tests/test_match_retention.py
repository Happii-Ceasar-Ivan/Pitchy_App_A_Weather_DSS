"""B6 item 8: matches are deleted 135 days after kickoff, with their assessments and chat events
(public.purge_old_match_contexts, run as the backend role; local PostgreSQL)."""

from datetime import UTC, datetime, timedelta

import pytest
from psycopg import errors

from shared.db.records import NewForecastValue
from shared.db.repositories import (
    PgForecastRepository,
    PgLocationRepository,
    PgRetentionRepository,
)
from shared.settings import Settings
from tests.conftest import requires_db

pytestmark = requires_db
DAY = timedelta(days=1)
KEEP = timedelta(days=Settings(env="test").retention_match_days)


def _match(conn, kickoff_ago: timedelta) -> str:
    loc = conn.execute(
        "select id from public.locations where scope_key = 'rizal_memorial'"
    ).fetchone()[0]
    return conn.execute(
        "insert into public.match_contexts (kickoff_at, location_id) values (now() - %s, %s)"
        " returning id",
        (kickoff_ago, loc),
    ).fetchone()[0]


def _assessment(conn, match, value_id=None) -> str:
    assessment = conn.execute(
        "insert into public.safety_assessments (match_context_id, rule_version, result)"
        " values (%s, 'test', '{}') returning id",
        (match,),
    ).fetchone()[0]
    if value_id is not None:
        conn.execute(
            "insert into public.assessment_inputs values (%s, %s, 'heat')", (assessment, value_id)
        )
    return assessment


def _event(conn, match, assessment) -> None:
    conn.execute(
        "insert into public.conversation_events (match_context_id, assessment_id, role,"
        " generation, outcome_code, provider_called) values (%s, %s, 'coach', 'unavailable',"
        " 'OFF_TOPIC', false)",
        (match, assessment),
    )


def _count(conn, table: str, match) -> int:
    column = "id" if table == "match_contexts" else "match_context_id"
    return conn.execute(
        f"select count(*) from public.{table} where {column} = %s",  # noqa: S608 - fixed names
        (match,),
    ).fetchone()[0]


def test_default_is_four_and_a_half_months() -> None:
    assert KEEP == timedelta(days=135)


def test_old_match_goes_with_its_assessments_and_chat_events(connect, conn) -> None:
    old = _match(conn, KEEP + DAY)
    _event(conn, old, _assessment(conn, old))
    _assessment(conn, old)
    kept = _match(conn, KEEP - DAY)
    _event(conn, kept, _assessment(conn, kept))
    future = _match(conn, -30 * DAY)

    deleted = PgRetentionRepository(connect).purge_matches(KEEP)

    assert deleted == {
        "conversation_events_deleted": 1,
        "safety_assessments_deleted": 2,
        "match_contexts_deleted": 1,
    }
    for table in ("match_contexts", "safety_assessments", "conversation_events"):
        assert _count(conn, table, old) == 0
        assert _count(conn, table, kept) == 1
    assert _count(conn, "match_contexts", future) == 1


def test_weather_pinned_by_a_deleted_assessment_can_then_rotate(connect, conn) -> None:
    """DEC-11 keeps values an assessment used; once the assessment is gone they can rotate."""
    loc = PgLocationRepository(connect).get_by_scope_key("rizal_memorial")
    forecasts = PgForecastRepository(connect)
    start = datetime(2026, 12, 1, tzinfo=UTC)
    value = NewForecastValue(
        "temperature_2m", 30.0, "°C", "ok", start, start + timedelta(hours=1), None
    )
    pinned = forecasts.record_fetch("open_meteo", loc.id, None, [value])
    conn.execute(
        "update public.source_fetches set requested_at = requested_at - interval '20 days',"
        " completed_at = completed_at - interval '20 days' where id = %s",
        (pinned,),
    )
    forecasts.record_fetch("open_meteo", loc.id, None, [value])  # the newest one stays anyway
    value_id = conn.execute(
        "select id from public.forecast_values where fetch_id = %s", (pinned,)
    ).fetchone()[0]
    _assessment(conn, _match(conn, KEEP + DAY), value_id)

    retention = PgRetentionRepository(connect)
    assert retention.purge(14 * DAY, 30 * DAY)["source_fetches_deleted"] == 0  # still pinned
    assert retention.purge_matches(KEEP)["match_contexts_deleted"] == 1
    assert retention.purge(14 * DAY, 30 * DAY)["source_fetches_deleted"] == 1


@pytest.mark.parametrize("keep", [timedelta(days=29), timedelta(hours=1), None])
def test_periods_under_30_days_are_refused(connect, conn, keep) -> None:
    recent = _match(conn, 10 * DAY)
    with pytest.raises(errors.RaiseException):
        PgRetentionRepository(connect).purge_matches(keep)
    assert _count(conn, "match_contexts", recent) == 1


def test_only_the_backend_role_may_run_it(conn) -> None:
    for role, expected in (("anon", False), ("authenticated", False), ("pitchy_app", True)):
        if not conn.execute("select 1 from pg_roles where rolname = %s", (role,)).fetchone():
            continue
        allowed = conn.execute(
            "select has_function_privilege(%s,"
            " 'public.purge_old_match_contexts(interval)', 'execute')",
            (role,),
        ).fetchone()[0]
        assert allowed is expected


def test_the_setting_refuses_under_30_days() -> None:
    with pytest.raises(ValueError):
        Settings(env="test", retention_match_days=10)
