"""Ingestion runner against a local PostgreSQL with fake adapters (no network)."""

from datetime import UTC, datetime, timedelta

import pytest

from services.weather_ingestion.jobs.runner import AdapterGroup, run_ingestion
from services.weather_ingestion.registry import venue_from_location
from services.weather_ingestion.sources.base import (
    FetchFailure,
    SourceFetch,
    SourceUnavailableError,
)
from shared.db.records import NewForecastValue
from shared.db.repositories import (
    PgForecastRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
)
from tests.conftest import requires_db

pytestmark = requires_db
T0 = datetime(2026, 12, 1, tzinfo=UTC)


def value(name="temperature_2m"):
    return NewForecastValue(name, 30.0, "°C", "ok", T0, T0 + timedelta(hours=1), None)


class FakeAdapter:
    def __init__(self, source_ids, behaviour="ok"):
        self.source_ids, self.behaviour, self.calls, self.closed = source_ids, behaviour, 0, False

    def fetch(self, venue):
        self.calls += 1
        if self.behaviour == "down":
            raise SourceUnavailableError("Site down.", "HTTP_503")
        if self.behaviour == "crash":
            raise ZeroDivisionError("bug")
        outcomes = []
        for i, sid in enumerate(self.source_ids):
            if self.behaviour == "half" and i == 1:
                outcomes.append(FetchFailure(sid, venue, SourceUnavailableError("x", "HTTP_500")))
            else:
                outcomes.append(SourceFetch(sid, venue, [value(), value("cape")], '{"raw": 1}'))
        return outcomes

    def close(self):
        self.closed = True


@pytest.fixture
def env(connect):
    venues = [
        venue_from_location(PgLocationRepository(connect).get_or_create(k, 14.5, 121.0, k))
        for k in ("venue_a", "venue_b")
    ]
    return venues, PgIngestionJobRepository(connect), PgForecastRepository(connect)


def run(env, groups, enabled, **kw):
    venues, jobs, forecasts = env
    return run_ingestion(groups, venues, enabled, jobs, forecasts, **kw)


def test_stores_values_and_provenance_for_every_venue(env, conn) -> None:
    adapter = FakeAdapter(("open_meteo",))
    report = run(
        env, [AdapterGroup("open_meteo", ("open_meteo",), lambda: adapter)], {"open_meteo"}
    )
    assert [(r.venue, r.status, r.values_stored) for r in report.results] == [
        ("venue_a", "stored", 2), ("venue_b", "stored", 2)
    ]  # fmt: skip
    assert adapter.calls == 2 and adapter.closed
    row = conn.execute(
        "select status, raw_payload_sha256 is not null, ingestion_job_id is not null"
        " from public.source_fetches limit 1"
    ).fetchone()
    assert row == ("succeeded", True, True)
    jobs = conn.execute("select state from public.ingestion_jobs").fetchall()
    assert jobs == [("succeeded",), ("succeeded",)]


def test_pagasa_four_hour_rule(env) -> None:
    ids = ("pagasa_atmo", "pagasa_ecmwf")
    adapter = FakeAdapter(ids)
    group = AdapterGroup("pagasa", ids, lambda: adapter, min_interval=timedelta(hours=4))
    run(env, [group], set(ids))
    assert adapter.calls == 2
    second = run(env, [group], set(ids))
    assert adapter.calls == 2  # nothing sent to the source again
    assert {r.status for r in second.results} == {"skipped_recent"}
    later = run(
        env, [group], set(ids), now=lambda: datetime.now(UTC) + timedelta(hours=4, minutes=1)
    )
    assert adapter.calls == 4 and {r.status for r in later.results} == {"stored"}


def test_failed_requests_also_count_for_the_four_hour_rule(env) -> None:
    down = FakeAdapter(("pagasa_atmo",), "down")
    group = AdapterGroup("pagasa", ("pagasa_atmo",), lambda: down, min_interval=timedelta(hours=4))
    first = run(env, [group], {"pagasa_atmo"})
    assert {(r.status, r.error_code) for r in first.results} == {("failed", "HTTP_503")}
    run(env, [group], {"pagasa_atmo"})
    assert down.calls == 2  # one per venue, no retry storm


def test_one_model_failing_keeps_the_other(env, conn) -> None:
    ids = ("pagasa_atmo", "pagasa_ecmwf")
    report = run(env, [AdapterGroup("pagasa", ids, lambda: FakeAdapter(ids, "half"))], set(ids))
    statuses = {(r.source_id, r.status) for r in report.results}
    assert statuses == {("pagasa_atmo", "stored"), ("pagasa_ecmwf", "failed")}
    states = {s for (s,) in conn.execute("select state from public.ingestion_jobs")}
    assert states == {"succeeded"}


def test_adapter_bug_is_recorded_safely(env, conn) -> None:
    group = AdapterGroup(
        "open_meteo", ("open_meteo",), lambda: FakeAdapter(("open_meteo",), "crash")
    )
    report = run(env, [group], {"open_meteo"})
    assert {r.error_code for r in report.results} == {"INTERNAL_ERROR"}
    failure = conn.execute("select failure_code from public.ingestion_jobs limit 1").fetchone()
    assert failure == ("INTERNAL_ERROR",)


def test_running_job_means_in_progress_not_a_second_fetch(env) -> None:
    venues, jobs, _ = env
    jobs.acquire(f"open_meteo:{venues[0].scope_key}", "open_meteo", venues[0].location_id,
                 timedelta(minutes=5))  # fmt: skip
    adapter = FakeAdapter(("open_meteo",))
    report = run(
        env, [AdapterGroup("open_meteo", ("open_meteo",), lambda: adapter)], {"open_meteo"}
    )
    assert [r.status for r in report.results] == ["in_progress", "stored"]
    assert adapter.calls == 1


def test_disabled_sources_are_not_called(env) -> None:
    adapter = FakeAdapter(("dost_asti",))
    report = run(env, [AdapterGroup("dost_asti", ("dost_asti",), lambda: adapter)], set())
    assert {r.status for r in report.results} == {"disabled"} and adapter.calls == 0
