"""B3 API: venues, match contexts, weather status and manual ingestion (local PostgreSQL).

Covers the B3 brief's test list: simultaneous requests (2 and 3+), requests while running,
after success and after failure, lease expiry, unrelated scopes, recent data that does not
cover the match, stale fallback, unavailable sources and PAGASA's 4-hour gap. No network: the
source adapters are fakes and background jobs run when the test says so.
"""

import threading
from concurrent.futures import Future
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from api.deps import get_adapter_groups, get_connect, get_ingestion_executor
from services.weather_ingestion.jobs.runner import AdapterGroup
from services.weather_ingestion.sources.base import SourceFetch, SourceUnavailableError
from shared.db.records import NewForecastValue
from shared.db.repositories import PgForecastRepository, PgLocationRepository
from shared.settings import Settings
from tests.conftest import requires_db

pytestmark = requires_db
API = API_V1_PREFIX
HOUR = timedelta(hours=1)
KICKOFF = (datetime.now(UTC) + timedelta(days=1)).replace(minute=0, second=0, microsecond=0)


def hourly(start: datetime, hours: int, name: str = "temperature_2m") -> list[NewForecastValue]:
    return [
        NewForecastValue(name, 30.0, "°C", "ok", start + i * HOUR, start + (i + 1) * HOUR, None)
        for i in range(hours)
    ]


class FakeAdapter:
    """Answers for every venue with values around the match. ``mode``: ok | down."""

    def __init__(self, source_ids, state):
        self.source_ids, self.state = source_ids, state

    def fetch(self, venue):
        self.state["calls"] += 1
        if self.state["mode"] == "down":
            raise SourceUnavailableError("Site down.", "HTTP_503")
        issued = datetime.now(UTC) - HOUR if self.state.get("issued") else None
        return [
            SourceFetch(s, venue, hourly(self.state["from"], 6), "{}", source_issued_at=issued)
            for s in self.source_ids
        ]


class ManualExecutor:
    """Holds background jobs until ``run_all`` so tests can look at the 'running' state."""

    def __init__(self):
        self.pending, self.lock = [], threading.Lock()

    def submit(self, fn, *args, **kwargs):
        with self.lock:
            self.pending.append((fn, args, kwargs))
        return Future()

    def run_all(self) -> int:
        with self.lock:
            pending, self.pending = self.pending, []
        for fn, args, kwargs in pending:
            fn(*args, **kwargs)
        return len(pending)


@pytest.fixture
def sources():
    return {
        "open_meteo": {"mode": "ok", "calls": 0, "from": KICKOFF - HOUR},
        "pagasa": {"mode": "ok", "calls": 0, "from": KICKOFF - HOUR, "issued": True},
    }


@pytest.fixture
def executor():
    return ManualExecutor()


@pytest.fixture
def client(connect, sources, executor):
    groups = [
        AdapterGroup("open_meteo", ("open_meteo",),
                     lambda: FakeAdapter(("open_meteo",), sources["open_meteo"])),
        AdapterGroup("pagasa", ("pagasa_atmo", "pagasa_ecmwf"),
                     lambda: FakeAdapter(("pagasa_atmo", "pagasa_ecmwf"), sources["pagasa"]),
                     min_interval=timedelta(hours=4)),
    ]  # fmt: skip
    app = create_app(Settings(env="test"))
    app.dependency_overrides[get_connect] = lambda: connect
    app.dependency_overrides[get_adapter_groups] = lambda: groups
    app.dependency_overrides[get_ingestion_executor] = lambda: executor
    return TestClient(app)


def new_match(client, venue="rizal_memorial", kickoff=KICKOFF) -> str:
    res = client.post(f"{API}/match-contexts", json={"kickoff_at": kickoff.isoformat(),
                                                     "venue": venue})  # fmt: skip
    assert res.status_code == 201, res.text
    return res.json()["id"]


def status(client, match_id) -> dict:
    res = client.get(f"{API}/match-contexts/{match_id}/weather-status")
    assert res.status_code == 200, res.text
    return res.json()


def states(body) -> dict[str, str]:
    return {s["source_id"]: s["state"] for s in body["sources"]}


def ingest(client, match_id):
    return client.post(f"{API}/match-contexts/{match_id}/ingestions")


def job_count(conn) -> int:
    return conn.execute("select count(*) from public.ingestion_jobs").fetchone()[0]


def store(connect, source_id, start, hours, issued=None, scope="rizal_memorial"):
    location = PgLocationRepository(connect).get_by_scope_key(scope)
    PgForecastRepository(connect).record_fetch(
        source_id, location.id, None, hourly(start, hours), source_issued_at=issued
    )


def age_fetches(conn, source_id, by: timedelta) -> None:
    """Pretend the stored fetches of a source happened ``by`` earlier (admin connection)."""
    conn.execute(
        "update public.source_fetches set requested_at = requested_at - %s,"
        " completed_at = completed_at - %s where source_id = %s",
        (by, by, source_id),
    )
    conn.execute(
        "update public.forecast_values set retrieved_at = retrieved_at - %s where source_id = %s",
        (by, source_id),
    )


# --- Venues and match contexts --------------------------------------------------------------


def test_venue_list_has_the_two_venues_only_by_key(client) -> None:
    res = client.get(f"{API}/venues")
    assert res.status_code == 200
    venues = {v["scope_key"]: v for v in res.json()["venues"]}
    assert set(venues) == {"rizal_memorial", "new_clark_city"}
    assert venues["rizal_memorial"]["latitude"] == pytest.approx(14.563405271502504)
    assert set(venues["new_clark_city"]) == {"scope_key", "name", "latitude", "longitude"}


def test_match_context_round_trip_returns_the_selected_venue(client) -> None:
    match_id = new_match(client, "new_clark_city", KICKOFF.astimezone())
    body = client.get(f"{API}/match-contexts/{match_id}").json()
    assert body["venue"]["scope_key"] == "new_clark_city"
    assert body["venue"]["name"].startswith("New Clark City")
    assert datetime.fromisoformat(body["kickoff_at"]) == KICKOFF


def test_unknown_venue_is_rejected(client) -> None:
    res = client.post(f"{API}/match-contexts", json={"kickoff_at": KICKOFF.isoformat(),
                                                     "venue": "somewhere_else"})  # fmt: skip
    assert res.status_code == 422
    assert res.json()["error"]["details"][0]["field"] == "body.venue"


def test_unknown_match_and_job_are_not_found(client) -> None:
    missing = "00000000-0000-4000-8000-000000000001"
    assert client.get(f"{API}/match-contexts/{missing}").status_code == 404
    assert client.get(f"{API}/match-contexts/{missing}/weather-status").status_code == 404
    assert ingest(client, missing).status_code == 404
    assert client.get(f"{API}/ingestions/{missing}").status_code == 404


# --- Weather status -------------------------------------------------------------------------


def test_no_data_is_missing_and_ingestion_is_needed(client) -> None:
    body = status(client, new_match(client))
    assert states(body) == dict.fromkeys(["open_meteo", "pagasa_atmo", "pagasa_ecmwf"], "missing")
    assert body["ingestion_needed"] is True and body["active_job_ids"] == []
    assert body["sources"][0]["limitations"][0]["code"] == "NO_DATA"
    window = body["coverage"]
    assert datetime.fromisoformat(window["end"]) - datetime.fromisoformat(window["start"]) == (
        2 * HOUR
    )


def test_recent_data_that_does_not_cover_the_match_is_missing(client, connect) -> None:
    store(connect, "open_meteo", KICKOFF - HOUR, 2)  # stops at kickoff + 1 h, not + 2 h
    body = status(client, new_match(client))
    om = body["sources"][0]
    assert om["state"] == "missing" and not om["covers_match_time"]
    assert om["limitations"][0]["code"] == "NOT_COVERED"
    assert body["ingestion_needed"] is True


def test_gap_inside_the_match_window_is_not_coverage(client, connect, conn) -> None:
    store(connect, "open_meteo", KICKOFF - HOUR, 6)
    conn.execute(
        "delete from public.forecast_values where source_id = 'open_meteo'"
        " and forecast_valid_from = %s",
        (KICKOFF + HOUR,),
    )
    assert states(status(client, new_match(client)))["open_meteo"] == "missing"


def test_fresh_covering_data_is_current_with_provenance(client, connect) -> None:
    issued = datetime.now(UTC) - 2 * HOUR
    store(connect, "open_meteo", KICKOFF - HOUR, 6)
    store(connect, "pagasa_atmo", KICKOFF - HOUR, 6, issued=issued)
    store(connect, "pagasa_ecmwf", KICKOFF - HOUR, 6, issued=issued)
    body = status(client, new_match(client))
    assert set(states(body).values()) == {"current"}
    assert body["ingestion_needed"] is False
    atmo = body["sources"][1]
    assert datetime.fromisoformat(atmo["provenance"]["source_issued_at"]) == issued
    assert datetime.fromisoformat(atmo["current_until"]) == issued + 12 * HOUR
    assert atmo["provenance"]["source_name"].startswith("PAGASA ATMO")


def test_old_data_is_stale_never_current(client, connect, conn) -> None:
    store(connect, "open_meteo", KICKOFF - HOUR, 6)
    age_fetches(conn, "open_meteo", 8 * HOUR)  # Open-Meteo: current for 7 h after retrieval
    old_run = datetime.now(UTC) - 13 * HOUR  # ATMO: 12 h by run; ECMWF: 24 h by run
    store(connect, "pagasa_atmo", KICKOFF - HOUR, 6, issued=old_run)
    store(connect, "pagasa_ecmwf", KICKOFF - HOUR, 6, issued=old_run)
    body = status(client, new_match(client))
    assert states(body) == {"open_meteo": "stale", "pagasa_atmo": "stale",
                            "pagasa_ecmwf": "current"}  # fmt: skip
    om = body["sources"][0]
    assert om["provenance"] is not None
    assert datetime.fromisoformat(om["current_until"]) < datetime.now(UTC)
    assert body["ingestion_needed"] is True


def test_stale_fallback_when_the_newest_fetch_does_not_cover(client, connect, conn) -> None:
    store(connect, "open_meteo", KICKOFF - HOUR, 6)
    age_fetches(conn, "open_meteo", 8 * HOUR)
    store(connect, "open_meteo", KICKOFF + 10 * HOUR, 6)  # newer, but misses the match
    om = status(client, new_match(client))["sources"][0]
    assert om["state"] == "stale"
    assert [lim["code"] for lim in om["limitations"]] == ["OLDER_FORECAST_USED"]


# --- Manual ingestion -----------------------------------------------------------------------


def test_ingest_runs_each_group_once_then_reuses_the_cache(client, executor, sources) -> None:
    match_id = new_match(client)
    res = ingest(client, match_id)
    assert res.status_code == 202, res.text
    jobs = res.json()["jobs"]
    assert [j["source_ids"] for j in jobs] == [["open_meteo"], ["pagasa_atmo", "pagasa_ecmwf"]]
    assert all(j["state"] == "running" and not j["reused_existing_job"] for j in jobs)

    during = status(client, match_id)
    assert set(states(during).values()) == {"updating"}
    assert during["ingestion_needed"] is False
    assert sorted(during["active_job_ids"]) == sorted(j["id"] for j in jobs)

    again = ingest(client, match_id).json()["jobs"]  # arrives while running
    assert [j["id"] for j in again] == [j["id"] for j in jobs]
    assert all(j["reused_existing_job"] for j in again)

    assert executor.run_all() == 2
    assert (sources["open_meteo"]["calls"], sources["pagasa"]["calls"]) == (1, 1)
    for job in jobs:
        polled = client.get(f"{API}/ingestions/{job['id']}").json()
        assert polled["state"] == "succeeded" and polled["failures"] == []
        assert polled["venue"] == "rizal_memorial" and polled["reused_existing_job"] is False

    after = status(client, match_id)
    assert set(states(after).values()) == {"current"} and after["active_job_ids"] == []
    res = ingest(client, match_id)  # after success: the shared cache is reused
    assert res.status_code == 409
    assert res.json()["error"]["code"] == "INGESTION_NOT_NEEDED"
    assert executor.run_all() == 0


@pytest.mark.parametrize("users", [2, 3, 6])
def test_simultaneous_requests_start_one_job_per_group(client, executor, conn, users) -> None:
    match_ids = [new_match(client) for _ in range(users)]  # separate matches, same venue
    barrier, answers = threading.Barrier(users), []

    def press_ingest(match_id):
        barrier.wait()
        answers.append(ingest(client, match_id))

    threads = [threading.Thread(target=press_ingest, args=(m,)) for m in match_ids]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)

    assert [a.status_code for a in answers] == [202] * users
    assert job_count(conn) == 2
    assert executor.run_all() == 2
    by_group: dict[str, set] = {}
    started = 0
    for answer in answers:
        for job in answer.json()["jobs"]:
            by_group.setdefault(job["source_ids"][0], set()).add(job["id"])
            started += not job["reused_existing_job"]
    assert all(len(ids) == 1 for ids in by_group.values())  # everyone sees the same jobs
    assert started == 2  # exactly one starter per group


def test_failed_ingestion_is_recorded_and_releases_the_lock(client, executor, sources) -> None:
    sources["open_meteo"]["mode"] = "down"
    match_id = new_match(client)
    jobs = ingest(client, match_id).json()["jobs"]
    executor.run_all()
    om_job = client.get(f"{API}/ingestions/{jobs[0]['id']}").json()
    assert om_job["state"] == "failed"
    assert om_job["failures"] == [
        {"source_id": "open_meteo", "code": "HTTP_503", "message": "Site down."}
    ]
    body = status(client, match_id)
    assert states(body)["open_meteo"] == "unavailable"
    limitation = body["sources"][0]["limitations"][0]
    assert limitation["code"] == "SOURCE_ERROR" and limitation["detail_code"] == "HTTP_503"
    assert "HTTP" not in limitation["message"]


def test_unavailable_offers_ingest_after_a_cooldown(client, executor, sources, conn) -> None:
    """DEC-04 option C: unavailable needs data, but only 15 min after the failed attempt."""
    sources["open_meteo"]["mode"] = "down"
    match_id = new_match(client)
    ingest(client, match_id)
    executor.run_all()  # Open-Meteo fails; PAGASA succeeds and is current

    body = status(client, match_id)
    assert states(body)["open_meteo"] == "unavailable"
    assert body["ingestion_needed"] is True
    wait = datetime.fromisoformat(body["next_ingestion_at"]) - datetime.now(UTC)
    assert timedelta(minutes=14) < wait <= timedelta(minutes=15)
    res = ingest(client, match_id)
    assert res.status_code == 429
    assert res.json()["error"]["retry_at"] == body["next_ingestion_at"]
    assert executor.run_all() == 0 and sources["open_meteo"]["calls"] == 1

    age_fetches(conn, "open_meteo", timedelta(minutes=16))  # the cooldown has passed
    sources["open_meteo"]["mode"] = "ok"
    assert status(client, match_id)["next_ingestion_at"] is None
    jobs = ingest(client, match_id).json()["jobs"]
    assert [j["source_ids"] for j in jobs] == [["open_meteo"]]
    executor.run_all()
    assert states(status(client, match_id))["open_meteo"] == "current"


def test_retry_after_failure_starts_a_new_job(client, executor, sources, connect, conn) -> None:
    sources["open_meteo"]["mode"] = "down"
    match_id = new_match(client)
    first = ingest(client, match_id).json()["jobs"][0]
    executor.run_all()
    store(connect, "open_meteo", KICKOFF - HOUR, 6)  # an older usable forecast...
    age_fetches(conn, "open_meteo", 8 * HOUR)  # ...that is now stale
    sources["open_meteo"]["mode"] = "ok"
    second = ingest(client, match_id).json()["jobs"][0]
    assert second["id"] != first["id"] and second["reused_existing_job"] is False
    executor.run_all()
    assert states(status(client, match_id))["open_meteo"] == "current"


def test_abandoned_job_expires_and_is_taken_over(client, conn) -> None:
    match_id = new_match(client)
    location_id = conn.execute(
        "select id from public.locations where scope_key = 'rizal_memorial'"
    ).fetchone()[0]
    abandoned = conn.execute(
        "insert into public.ingestion_jobs (scope_key, source_id, location_id, state,"
        " started_at, lease_expires_at) values ('open_meteo:rizal_memorial', 'open_meteo', %s,"
        " 'running', now() - interval '10 minutes', now() - interval '5 minutes') returning id",
        (location_id,),
    ).fetchone()[0]
    assert states(status(client, match_id))["open_meteo"] == "missing"  # not "updating"
    assert client.get(f"{API}/ingestions/{abandoned}").json()["state"] == "expired"

    jobs = ingest(client, match_id).json()["jobs"]
    assert jobs[0]["id"] != str(abandoned) and not jobs[0]["reused_existing_job"]
    row = conn.execute(
        "select state, failure_code from public.ingestion_jobs where id = %s", (abandoned,)
    ).fetchone()
    assert row == ("expired", "LEASE_EXPIRED")


def test_unrelated_venues_ingest_independently(client, executor) -> None:
    rizal = ingest(client, new_match(client, "rizal_memorial")).json()["jobs"]
    clark = ingest(client, new_match(client, "new_clark_city")).json()["jobs"]
    assert not any(j["reused_existing_job"] for j in rizal + clark)
    assert {j["venue"] for j in clark} == {"new_clark_city"}
    assert executor.run_all() == 4


def test_pagasa_inside_its_four_hour_gap_returns_retry_at(client, connect, conn) -> None:
    store(connect, "open_meteo", KICKOFF - HOUR, 6)
    old_run = datetime.now(UTC) - 30 * HOUR
    store(connect, "pagasa_atmo", KICKOFF - HOUR, 6, issued=old_run)
    store(connect, "pagasa_ecmwf", KICKOFF - HOUR, 6, issued=old_run)
    age_fetches(conn, "pagasa_atmo", HOUR)
    age_fetches(conn, "pagasa_ecmwf", HOUR)
    match_id = new_match(client)

    body = status(client, match_id)
    assert states(body) == {"open_meteo": "current", "pagasa_atmo": "stale",
                            "pagasa_ecmwf": "stale"}  # fmt: skip
    assert body["ingestion_needed"] is True
    next_at = datetime.fromisoformat(body["next_ingestion_at"])
    wait = next_at - datetime.now(UTC)
    assert timedelta(hours=2, minutes=50) < wait < timedelta(hours=3, minutes=1)

    res = ingest(client, match_id)
    assert res.status_code == 429
    assert res.json()["error"]["code"] == "RATE_LIMITED"
    assert datetime.fromisoformat(res.json()["error"]["retry_at"]) == next_at
    assert int(res.headers["Retry-After"]) > 0


def test_manual_ingest_inside_the_gap_refreshes_open_meteo_only(client, executor, sources,
                                                                connect, conn) -> None:  # fmt: skip
    store(connect, "pagasa_atmo", KICKOFF - HOUR, 6, issued=datetime.now(UTC) - 30 * HOUR)
    match_id = new_match(client)
    jobs = ingest(client, match_id).json()["jobs"]
    assert [j["source_ids"] for j in jobs] == [["open_meteo"]]
    executor.run_all()
    assert sources["pagasa"]["calls"] == 0
    assert status(client, match_id)["next_ingestion_at"] is not None


# --- Consolidated weather (P-09) ------------------------------------------------------------


def _store_values(connect, source_id, values, issued=None):
    location = PgLocationRepository(connect).get_by_scope_key("rizal_memorial")
    PgForecastRepository(connect).record_fetch(
        source_id, location.id, None, values, source_issued_at=issued
    )


def _v(name, value, unit, start, hours=1):
    return NewForecastValue(name, value, unit, "ok", start, start + hours * HOUR, None)


def _quantity(body, key):
    return next(q for q in body["quantities"] if q["quantity"] == key)


def _cover(source_id, unit="°C"):  # makes the source cover the match window
    return [_v("temperature_2m" if source_id == "open_meteo" else "heat_index", 30.0, unit,
               KICKOFF + i * HOUR) for i in range(2)]  # fmt: skip


def test_consolidated_rain_prefers_atmo_and_shows_the_range(client, connect) -> None:
    run = datetime.now(UTC) - HOUR
    quarter = timedelta(minutes=15)
    atmo = _cover("pagasa_atmo") + [
        NewForecastValue("accumulated_rain_1h", r, "mm/h", "ok", KICKOFF + i * quarter,
                         KICKOFF + (i + 1) * quarter, None)
        for i, r in enumerate([0.0, 1.0, 2.0, 1.0])
    ]  # fmt: skip
    atmo += [_v("wind_speed", 4.0, "m/s", KICKOFF), _v("wind_direction", 350.0, "°", KICKOFF)]
    ecmwf = _cover("pagasa_ecmwf") + [_v("accumulated_rain_1h", 9.0, "mm", KICKOFF, hours=3)]
    om = _cover("open_meteo") + [
        _v("precipitation", 0.4, "mm", KICKOFF),
        _v("wind_speed_10m", 3.0, "m/s", KICKOFF),
        _v("wind_direction_10m", 20.0, "°", KICKOFF),
    ]
    _store_values(connect, "pagasa_atmo", atmo, run)
    _store_values(connect, "pagasa_ecmwf", ecmwf, run)
    _store_values(connect, "open_meteo", om)
    res = client.get(f"{API}/match-contexts/{new_match(client)}/weather")
    assert res.status_code == 200, res.text
    body = res.json()
    assert [a["source_id"] for a in body["attributions"]] == ["open_meteo"]

    rain = _quantity(body, "rain")
    assert rain["priority"] == ["pagasa_atmo", "pagasa_ecmwf", "open_meteo"]
    first = rain["slots"][0]
    assert (first["value"], first["source_id"], first["state"]) == (1.0, "pagasa_atmo", "current")
    assert first["fallback_label"] is None
    # ECMWF's 3-hour step is not converted (meaning unconfirmed); it is out of the range anyway.
    assert {b["source_id"] for b in first["by_source"]} == {"pagasa_atmo", "open_meteo"}
    assert first["range"] == {"min": 0.4, "max": 1.0, "count": 2,
                              "source_ids": ["pagasa_atmo", "open_meteo"]}  # fmt: skip

    wind = _quantity(body, "wind_speed")["slots"][0]
    assert (wind["value"], wind["source_id"]) == (3.0, "open_meteo")
    assert wind["range"]["min"] == 3.0 and wind["range"]["max"] == 4.0
    direction = _quantity(body, "wind_direction")["slots"][0]
    assert (direction["range"]["min"], direction["range"]["max"]) == (350.0, 20.0)  # across north
    assert _quantity(body, "air_temperature")["slots"][0]["value"] == 30.0


def test_consolidated_falls_back_with_a_label_and_never_shows_stale_as_current(
    client, connect, conn
) -> None:
    old_run = datetime.now(UTC) - 13 * HOUR  # ATMO stale (12 h), ECMWF current (24 h)
    _store_values(connect, "pagasa_atmo", _cover("pagasa_atmo"), old_run)
    ecmwf = [_v("heat_index", 33.0, "°C", KICKOFF + i * HOUR) for i in range(2)]
    _store_values(connect, "pagasa_ecmwf", ecmwf, old_run)
    _store_values(connect, "open_meteo", _cover("open_meteo"))
    age_fetches(conn, "open_meteo", 8 * HOUR)  # Open-Meteo stale too
    body = client.get(f"{API}/match-contexts/{new_match(client)}/weather").json()

    heat = _quantity(body, "heat_index")["slots"][0]
    assert (heat["value"], heat["source_id"], heat["state"]) == (33.0, "pagasa_ecmwf", "current")
    assert heat["fallback_label"].endswith("PAGASA ATMO (panahon.gov.ph) stale")
    assert heat["range"] is None  # only one current source

    temp = _quantity(body, "air_temperature")["slots"][0]
    assert (temp["value"], temp["state"]) == (30.0, "stale")
    assert _quantity(body, "cape")["slots"][0]["value"] is None


# --- Update 2 (P-27): wait reasons, waiting groups, per-IP counting, trend window ------------


def _sources_by_id(body) -> dict[str, dict]:
    return {s["source_id"]: s for s in body["sources"]}


def test_status_and_429_name_the_waiting_source_and_why(client, connect, conn) -> None:
    store(connect, "open_meteo", KICKOFF - HOUR, 6)
    old_run = datetime.now(UTC) - 30 * HOUR
    for sid in ("pagasa_atmo", "pagasa_ecmwf"):
        store(connect, sid, KICKOFF - HOUR, 6, issued=old_run)
        age_fetches(conn, sid, HOUR)
    match_id = new_match(client)

    body = status(client, match_id)
    by_id = _sources_by_id(body)
    for sid in ("pagasa_atmo", "pagasa_ecmwf"):
        assert by_id[sid]["wait_reason"] == "min_interval"
        assert by_id[sid]["next_request_at"] == body["next_ingestion_at"]
    assert by_id["open_meteo"]["next_request_at"] is None  # current: nothing to wait for
    assert by_id["open_meteo"]["wait_reason"] is None

    err = ingest(client, match_id).json()["error"]
    assert err["code"] == "RATE_LIMITED"
    assert {d["field"] for d in err["details"]} == {"sources.pagasa_atmo", "sources.pagasa_ecmwf"}
    assert all("4 hours" in d["issue"] for d in err["details"])


def test_202_lists_the_groups_that_must_wait(client, executor, connect) -> None:
    store(connect, "pagasa_atmo", KICKOFF - HOUR, 6, issued=datetime.now(UTC) - 30 * HOUR)
    match_id = new_match(client)
    body = ingest(client, match_id).json()
    assert [j["source_ids"] for j in body["jobs"]] == [["open_meteo"]]
    assert [(w["source_ids"], w["reason"]) for w in body["waiting"]] == [
        (["pagasa_atmo", "pagasa_ecmwf"], "min_interval")
    ]
    assert datetime.fromisoformat(body["waiting"][0]["retry_at"]) > datetime.now(UTC)
    executor.run_all()


def test_failed_pagasa_waits_the_cooldown_not_four_hours(client, executor, sources) -> None:
    """P-27 A1: before, a failed PAGASA call blocked manual refresh for 4 hours."""
    sources["pagasa"]["mode"] = "down"
    match_id = new_match(client)
    ingest(client, match_id)
    executor.run_all()
    body = status(client, match_id)
    by_id = _sources_by_id(body)
    assert by_id["pagasa_atmo"]["state"] == "unavailable"
    assert by_id["pagasa_atmo"]["wait_reason"] == "failure_cooldown"
    wait = datetime.fromisoformat(by_id["pagasa_atmo"]["next_request_at"]) - datetime.now(UTC)
    assert timedelta(minutes=14) < wait <= timedelta(minutes=15)


def test_requests_that_start_or_reuse_a_job_use_the_ip_budget(connect, executor, sources) -> None:
    groups = [
        AdapterGroup(
            "open_meteo",
            ("open_meteo",),
            lambda: FakeAdapter(("open_meteo",), sources["open_meteo"]),
        )
    ]
    app = create_app(Settings(env="test", ip_limit_ingestion_requests_per_hour=1))
    app.dependency_overrides[get_connect] = lambda: connect
    app.dependency_overrides[get_adapter_groups] = lambda: groups
    app.dependency_overrides[get_ingestion_executor] = lambda: executor
    c = TestClient(app)
    match_id = new_match(c)
    assert ingest(c, match_id).status_code == 202  # starts a job: counted
    res = ingest(c, match_id)  # would reuse the running job: counted, over the limit
    assert res.status_code == 429 and res.json()["error"]["details"] == []
    executor.run_all()
    assert ingest(c, match_id).status_code == 409  # refused: not counted, so not a 429


def test_trend_window_reaches_six_hours_before_kickoff(client, connect) -> None:
    hours = [KICKOFF + i * HOUR for i in range(-7, 7) if i != -3]  # no value at kickoff - 3 h
    _store_values(connect, "open_meteo", [_v("temperature_2m", 30.0 + i, "°C", t)
                                          for i, t in enumerate(hours)])  # fmt: skip
    match_id = new_match(client)
    url = f"{API}/match-contexts/{match_id}/weather"

    default = client.get(url).json()
    assert datetime.fromisoformat(default["window"]["start"]) == KICKOFF  # unchanged default

    body = client.get(url, params={"hours_before": 6, "hours": 5}).json()
    assert datetime.fromisoformat(body["kickoff_at"]) == KICKOFF
    assert datetime.fromisoformat(body["window"]["start"]) == KICKOFF - 6 * HOUR
    assert datetime.fromisoformat(body["window"]["end"]) == KICKOFF + 5 * HOUR
    assert datetime.fromisoformat(body["coverage"]["end"]) == KICKOFF + 2 * HOUR
    for q in body["quantities"]:
        starts = [datetime.fromisoformat(s["valid_from"]) for s in q["slots"]]
        assert starts == [KICKOFF + i * HOUR for i in range(-6, 5)]  # contiguous, 11 hours
    temp = {datetime.fromisoformat(s["valid_from"]): s for s in
            _quantity(body, "air_temperature")["slots"]}  # fmt: skip
    gap = temp[KICKOFF - 3 * HOUR]
    assert gap["value"] is None and gap["source_id"] is None and gap["by_source"] == []
    assert temp[KICKOFF - 4 * HOUR]["source_id"] == "open_meteo"
    assert temp[KICKOFF - 4 * HOUR]["state"] == "current"

    assert client.get(url, params={"hours_before": 7}).status_code == 422
    assert client.get(url, params={"hours_before": -1}).status_code == 422


def test_trend_window_rounds_a_half_hour_kickoff_down(client, connect) -> None:
    _store_values(connect, "open_meteo", [_v("temperature_2m", 30.0, "°C", KICKOFF + i * HOUR)
                                          for i in range(-3, 4)])  # fmt: skip
    match_id = new_match(client, kickoff=KICKOFF + timedelta(minutes=30))
    body = client.get(f"{API}/match-contexts/{match_id}/weather",
                      params={"hours_before": 2, "hours": 1}).json()  # fmt: skip
    assert datetime.fromisoformat(body["window"]["start"]) == KICKOFF - 2 * HOUR
    assert datetime.fromisoformat(body["window"]["end"]) == KICKOFF + 2 * HOUR  # 10:30 + 1 h
    assert datetime.fromisoformat(body["kickoff_at"]) == KICKOFF + timedelta(minutes=30)


def test_unchanged_run_check_keeps_stale_data_stale_and_starts_the_gap(
    client, connect, conn
) -> None:
    """P-27 A2: a run check that found no newer run changes no state: the old run stays
    stale (honest), no failure note, the cached values stay, and the next check waits."""
    store(connect, "open_meteo", KICKOFF - HOUR, 6)
    old_run = datetime.now(UTC) - 13 * HOUR  # ATMO stale (12 h)
    store(connect, "pagasa_atmo", KICKOFF - HOUR, 6, issued=old_run)
    age_fetches(conn, "pagasa_atmo", 5 * HOUR)  # last download 5 h ago: gap over
    location = PgLocationRepository(connect).get_by_scope_key("rizal_memorial")
    PgForecastRepository(connect).record_unchanged_fetch("pagasa_atmo", location.id, None, old_run)
    match_id = new_match(client)

    body = status(client, match_id)
    atmo = _sources_by_id(body)["pagasa_atmo"]
    assert atmo["state"] == "stale"
    codes = [lim["code"] for lim in atmo["limitations"]]
    assert "LAST_ATTEMPT_FAILED" not in codes and "SOURCE_ERROR" not in codes
    assert atmo["wait_reason"] == "min_interval"
    assert datetime.fromisoformat(atmo["next_request_at"]) > datetime.now(UTC) + 3 * HOUR

    weather = client.get(f"{API}/match-contexts/{match_id}/weather").json()
    used = {s["source_id"]: s for s in weather["sources"]}["pagasa_atmo"]
    assert used["state"] == "stale"  # the older successful fetch, still labelled stale
    issued = datetime.fromisoformat(used["provenance"]["source_issued_at"])
    assert issued == old_run.replace(microsecond=issued.microsecond)
