"""Alert storage, the hourly limit and the alerts route (local PostgreSQL, fake fetcher)."""

import json
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from api.deps import get_alert_fetcher, get_connect
from services.weather_ingestion.jobs.alerts import refresh_alerts
from services.weather_ingestion.sources.base import SourceUnavailableError
from services.weather_ingestion.sources.pagasa.alerts import parse_alerts
from shared.db.repositories import (
    PgAlertRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
)
from shared.settings import Settings
from tests.conftest import requires_db

pytestmark = requires_db
HOUR = timedelta(hours=1)
FIXTURE = Path(__file__).parent / "sources" / "pagasa" / "fixtures" / "cap_alerts_2026-11-22.json"
SOON = datetime.now(UTC) + 3 * HOUR


def _capas_alert(valid_until: datetime, headline="Thunderstorm <b>advisory</b>") -> dict:
    pht = valid_until.astimezone(UTC) + timedelta(hours=8)
    return {
        "event": "THUNDERSTORM", "subtype": "thunderstorm advisory", "headline": headline,
        "message": "Heavy rain expected.", "published_by": "PRSD", "identifier": "capas-1",
        "issued_date": "2026-11-22 10:00:00", "valid_date": pht.strftime("%Y-%m-%d %H:%M:%S"),
        "provinces": [{"municipality": "Capas", "province": "Tarlac", "psgc_code": "36904000",
                       "type": "affecting"}],
    }  # fmt: skip


class FakeFetcher:
    def __init__(self, items=None, error=None):
        self.items, self.error, self.calls = items, error, 0

    def __call__(self):
        self.calls += 1
        if self.error:
            raise self.error
        payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
        payload["data"]["alert_data"] += self.items or []
        return parse_alerts(payload), 0


@pytest.fixture
def repos(connect):
    return (PgLocationRepository(connect).list_all(), PgIngestionJobRepository(connect),
            PgAlertRepository(connect))  # fmt: skip


def test_check_is_stored_with_matched_venues(repos) -> None:
    locations, jobs, alerts = repos
    assert refresh_alerts(FakeFetcher([_capas_alert(SOON)]), locations, jobs, alerts, HOUR
                          ).status == "refreshed"  # fmt: skip
    check = alerts.last_successful_check()
    stored = {a.identifier: a for a in alerts.alerts_of_check(check.id)}
    assert check.alert_count == len(stored) == 3 and check.active_cyclones == 0
    assert stored["capas-1"].matched_venues == ["new_clark_city"]
    assert stored["capas-1"].headline == "Thunderstorm advisory"  # plain text only
    ncr = next(a for a in stored.values() if a.issuer == "NCRPRSD")
    assert ncr.matched_venues == ["rizal_memorial"]
    assert ncr.areas[0]["level"] == "province"


def test_alerts_are_checked_at_most_hourly_including_failures(repos) -> None:
    locations, jobs, alerts = repos
    down = FakeFetcher(error=SourceUnavailableError("down", "HTTP_503"))
    assert refresh_alerts(down, locations, jobs, alerts, HOUR).status == "failed"
    assert alerts.last_check().error_code == "HTTP_503"
    working = FakeFetcher()
    assert refresh_alerts(working, locations, jobs, alerts, HOUR).status == "skipped_recent"
    assert working.calls == 0
    later = refresh_alerts(working, locations, jobs, alerts, HOUR,
                           now=lambda: datetime.now(UTC) + 2 * HOUR)  # fmt: skip
    assert later.status == "refreshed" and working.calls == 1


def test_a_running_check_is_not_duplicated(repos) -> None:
    locations, jobs, alerts = repos
    jobs.acquire("pagasa_alerts", "pagasa", None, timedelta(minutes=5))
    fetcher = FakeFetcher()
    assert refresh_alerts(fetcher, locations, jobs, alerts, HOUR).status == "in_progress"
    assert fetcher.calls == 0


@pytest.fixture
def client(connect):
    holder = {"fetcher": FakeFetcher([_capas_alert(SOON),
                                      _capas_alert(datetime.now(UTC) - HOUR) | {
                                          "identifier": "capas-old"}])}  # fmt: skip
    app = create_app(Settings(env="test"))
    app.dependency_overrides[get_connect] = lambda: connect
    app.dependency_overrides[get_alert_fetcher] = lambda: holder["fetcher"]
    return TestClient(app), holder


def _match(client, venue):
    res = client.post(f"{API_V1_PREFIX}/match-contexts",
                      json={"kickoff_at": SOON.isoformat(), "venue": venue})  # fmt: skip
    return res.json()["id"]


def test_alerts_route_refreshes_on_open_and_shows_only_this_venue(client) -> None:
    client, holder = client
    clark = _match(client, "new_clark_city")
    body = client.get(f"{API_V1_PREFIX}/match-contexts/{clark}/alerts").json()
    assert holder["fetcher"].calls == 1
    assert body["status"]["state"] == "current"
    assert [a["subtype"] for a in body["alerts"]] == ["thunderstorm advisory"]  # expired one hidden
    assert body["alerts"][0]["matched_areas"] == [
        {"name": "Capas", "code": "036904000", "level": "municipality", "relation": "affecting"}
    ]
    assert "Not a Pitchy classification" in body["label"]

    rizal = _match(client, "rizal_memorial")
    body = client.get(f"{API_V1_PREFIX}/match-contexts/{rizal}/alerts").json()
    assert holder["fetcher"].calls == 1  # within the hour: answered from the database
    assert [a["issuer"] for a in body["alerts"]] == ["NCRPRSD"]

    status = client.get(f"{API_V1_PREFIX}/match-contexts/{rizal}/weather-status").json()
    assert status["alerts"]["state"] == "current"
    assert status["ingestion_needed"] is True  # alerts never trigger Ingest


def test_alerts_unavailable_when_the_first_check_fails(client) -> None:
    client, holder = client
    holder["fetcher"] = FakeFetcher(error=SourceUnavailableError("blocked", "HTTP_403"))
    body = client.get(f"{API_V1_PREFIX}/match-contexts/{_match(client, 'rizal_memorial')}/alerts")
    body = body.json()
    assert body["status"] == {"state": "unavailable", "last_checked_at": None,
                              "current_until": None, "last_error_code": "HTTP_403"}  # fmt: skip
    assert body["alerts"] == [] and body["active_tropical_cyclones"] is None
