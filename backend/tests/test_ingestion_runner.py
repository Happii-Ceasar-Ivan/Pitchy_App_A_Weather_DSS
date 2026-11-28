"""Ingestion runner against a local PostgreSQL with fake adapters (no network)."""

from datetime import UTC, datetime, timedelta

import pytest

from services.weather_ingestion.jobs.runner import AdapterGroup, run_ingestion
from services.weather_ingestion.registry import venue_from_location
from services.weather_ingestion.sources.base import (
    FetchFailure,
    SourceFetch,
    SourceUnavailableError,
    SourceUnchanged,
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
        if self.behaviour == "refused":
            raise SourceUnavailableError("Forbidden.", "HTTP_403")
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


def _pagasa(adapter, cooldown=timedelta(minutes=15)):
    return AdapterGroup("pagasa", ("pagasa_atmo",), lambda: adapter,
                        min_interval=timedelta(hours=4), failure_cooldown=cooldown)  # fmt: skip


def _at(delta):
    return lambda: datetime.now(UTC) + delta


def test_ordinary_failure_waits_only_the_cooldown(env) -> None:
    """P-27 A1: a timeout/5xx no longer starts PAGASA's 4-hour gap; 15 minutes, checked in the
    runner (under the lock), so no retry storm before that."""
    down = FakeAdapter(("pagasa_atmo",), "down")
    group = _pagasa(down)
    first = run(env, [group], {"pagasa_atmo"})
    assert {(r.status, r.error_code) for r in first.results} == {("failed", "HTTP_503")}
    soon = run(env, [group], {"pagasa_atmo"}, now=_at(timedelta(minutes=10)))
    assert down.calls == 2 and {r.status for r in soon.results} == {"skipped_recent"}
    after = run(env, [group], {"pagasa_atmo"}, now=_at(timedelta(minutes=16)))
    assert down.calls == 4 and {r.status for r in after.results} == {"failed"}


def test_failure_without_cooldown_is_not_held_by_the_runner(env) -> None:
    down = FakeAdapter(("pagasa_atmo",), "down")
    run(env, [_pagasa(down, cooldown=None)], {"pagasa_atmo"})
    run(env, [_pagasa(down, cooldown=None)], {"pagasa_atmo"})
    assert down.calls == 4  # no 4-hour gap after a plain failure any more


def test_refusal_by_the_source_still_waits_four_hours(env) -> None:
    refused = FakeAdapter(("pagasa_atmo",), "refused")
    group = _pagasa(refused)
    run(env, [group], {"pagasa_atmo"})
    later = run(env, [group], {"pagasa_atmo"}, now=_at(timedelta(hours=3, minutes=59)))
    assert refused.calls == 2 and {r.status for r in later.results} == {"skipped_recent"}
    assert all("source_refused" in r.message for r in later.results)
    run(env, [group], {"pagasa_atmo"}, now=_at(timedelta(hours=4, minutes=1)))
    assert refused.calls == 4


def test_failure_after_a_success_keeps_the_gap_from_the_success(env) -> None:
    venues, _, forecasts = env
    adapter = FakeAdapter(("pagasa_atmo",))
    group = _pagasa(adapter)
    run(env, [group], {"pagasa_atmo"})  # success now
    for v in venues:  # then an ordinary failure (e.g. a manual run that timed out)
        forecasts.record_failed_fetch("pagasa_atmo", v.location_id, None, "TIMEOUT", "Slow.")
    later = run(env, [group], {"pagasa_atmo"}, now=_at(timedelta(minutes=20)))
    assert adapter.calls == 2  # cooldown over, but the success 20 min ago still holds 4 h
    assert all("min_interval" in r.message for r in later.results)


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


# --- P-27 A2: run check -------------------------------------------------------------------------

RUN = T0 - timedelta(hours=6)


class RunCheckAdapter:
    """Lists ``RUN`` for every model: downloads unless the stored run is the same."""

    def __init__(self, source_ids):
        self.source_ids, self.downloads, self.known_seen = source_ids, 0, []

    def fetch(self, venue, known_runs=None):
        self.known_seen.append(dict(known_runs or {}))
        outcomes = []
        for sid in self.source_ids:
            if (known_runs or {}).get(sid) == RUN:
                outcomes.append(SourceUnchanged(sid, venue, RUN))
            else:
                self.downloads += 1
                outcomes.append(SourceFetch(sid, venue, [value()], '{"raw": 1}',
                                            source_issued_at=RUN))  # fmt: skip
        return outcomes


def _checked(adapter):
    return AdapterGroup("pagasa", adapter.source_ids, lambda: adapter,
                        min_interval=timedelta(hours=4), run_check=True)  # fmt: skip


def test_run_check_skips_the_download_and_records_unchanged(env, conn) -> None:
    ids = ("pagasa_atmo", "pagasa_ecmwf")
    adapter = RunCheckAdapter(ids)
    first = run(env, [_checked(adapter)], set(ids))
    assert {r.status for r in first.results} == {"stored"} and adapter.downloads == 4
    assert adapter.known_seen[0] == {"pagasa_atmo": None, "pagasa_ecmwf": None}

    later = run(env, [_checked(adapter)], set(ids), now=_at(timedelta(hours=4, minutes=1)))
    assert {r.status for r in later.results} == {"unchanged"}
    assert adapter.downloads == 4  # nothing downloaded again
    assert adapter.known_seen[-1] == {"pagasa_atmo": RUN, "pagasa_ecmwf": RUN}
    rows = conn.execute(
        "select f.source_issued_at, f.raw_payload, f.error_code,"
        " (select count(*) from public.forecast_values v where v.fetch_id = f.id)"
        " from public.source_fetches f where f.status = 'unchanged'"
    ).fetchall()
    assert rows == [(RUN, None, None, 0)] * 4  # 2 venues x 2 models
    newest_jobs = conn.execute(
        "select state from public.ingestion_jobs order by requested_at desc limit 2"
    ).fetchall()
    assert newest_jobs == [("succeeded",), ("succeeded",)]


def test_an_unchanged_check_starts_the_gap_like_a_success(env, conn) -> None:
    ids = ("pagasa_atmo",)
    adapter = RunCheckAdapter(ids)
    run(env, [_checked(adapter)], set(ids))
    conn.execute("update public.source_fetches set requested_at = requested_at - interval '5h'")
    run(env, [_checked(adapter)], set(ids))  # 5 h later: run check, unchanged
    again = run(env, [_checked(adapter)], set(ids), now=_at(timedelta(hours=1)))
    assert {r.status for r in again.results} == {"skipped_recent"}
    assert all("min_interval" in r.message for r in again.results)
    assert len(adapter.known_seen) == 4  # 2 venues x 2 runs; the third run never asked


def test_groups_without_run_check_get_no_known_runs(env) -> None:
    adapter = FakeAdapter(("open_meteo",))  # fetch(venue) only: would fail on known_runs
    report = run(env, [AdapterGroup("open_meteo", ("open_meteo",), lambda: adapter)],
                 {"open_meteo"})  # fmt: skip
    assert {r.status for r in report.results} == {"stored"}


def test_atmo_run_not_served_is_stored_and_the_gap_still_holds(env, conn) -> None:
    """PAGASA serving ``[]`` for the listed ATMO run (2026-11-26): ATMO fails with its own
    code and our own text, ECMWF is stored, and the 4 h gap stops a second request."""
    from tests.sources.pagasa.test_pagasa_adapter_parallel import FakePanahon, adapter_for

    fake = FakePanahon()
    fake.forecasts["atmo"] = []
    ids = ("pagasa_atmo", "pagasa_ecmwf")
    group = AdapterGroup("pagasa", ids, lambda: adapter_for(fake),
                         min_interval=timedelta(hours=4), run_check=True)  # fmt: skip
    report = run(env, [group], set(ids))
    assert {(r.source_id, r.status) for r in report.results} == {
        ("pagasa_atmo", "failed"), ("pagasa_ecmwf", "stored")
    }  # fmt: skip
    rows = conn.execute(
        "select distinct error_code, error_summary from public.source_fetches"
        " where source_id = 'pagasa_atmo'"
    ).fetchall()
    summary = "PAGASA lists ATMO run 2026-11-21T18:00Z but serves no data for it."
    assert rows == [("PAGASA_RUN_NOT_SERVED", summary)]
    hits = dict(fake.hits)
    second = run(env, [group], set(ids))
    assert fake.hits == hits  # nothing sent to PAGASA again
    assert {r.status for r in second.results} == {"skipped_recent"}
