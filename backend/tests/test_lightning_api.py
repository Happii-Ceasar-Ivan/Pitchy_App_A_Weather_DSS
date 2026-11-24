"""Live lightning route (DEC-06): shared 5-minute checks, live window, guidance (local DB)."""

import json
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from api.deps import get_connect, get_lightning_fetcher
from services.weather_ingestion.sources.base import SourceUnavailableError
from services.weather_ingestion.sources.xweather.lightning import parse
from shared.db.repositories import PgAlertRepository, PgRetentionRepository
from shared.settings import Settings
from tests.conftest import requires_db

pytestmark = requires_db
API = API_V1_PREFIX
EMPTY = '{"success":true,"error":{"code":"warn_no_data"},"response":[]}'


def _flash_payload(lat=14.60, lon=121.04) -> str:
    ts = int(datetime.now(UTC).timestamp()) - 60
    flash = {"id": "a", "loc": {"lat": lat, "long": lon}, "ob": {"timestamp": ts}}
    return json.dumps({"success": True, "error": None, "response": [flash]})


class FakeFetcher:
    def __init__(self, text=EMPTY, error=None):
        self.text, self.error, self.calls = text, error, 0

    def __call__(self, lat, lon, radius):
        self.calls += 1
        if self.error:
            raise self.error
        return parse(self.text, lat, lon, radius)


@pytest.fixture
def api(connect):
    holder = {"fetcher": FakeFetcher()}
    app = create_app(Settings(env="test"))
    app.dependency_overrides[get_connect] = lambda: connect
    app.dependency_overrides[get_lightning_fetcher] = lambda: holder["fetcher"]
    return TestClient(app), holder


def _match(client, kickoff, venue="rizal_memorial") -> str:
    res = client.post(f"{API}/match-contexts",
                      json={"kickoff_at": kickoff.isoformat(), "venue": venue})  # fmt: skip
    return res.json()["id"]


def _lightning(client, match_id) -> dict:
    res = client.get(f"{API}/match-contexts/{match_id}/lightning")
    assert res.status_code == 200, res.text
    return res.json()


def test_quiet_sky_is_current_with_no_flashes_and_credit(api) -> None:
    client, holder = api
    body = _lightning(client, _match(client, datetime.now(UTC) + timedelta(minutes=30)))
    assert holder["fetcher"].calls == 1 and body["in_live_window"] is True
    assert body["status"]["state"] == "current" and body["flash_count"] == 0
    assert body["guidance"] is None and body["level"] is None
    assert body["attribution"]["text"] == "Powered by Vaisala Xweather"
    assert "Officials on site decide" in body["note"]


def test_checks_are_shared_per_venue_for_five_minutes(api) -> None:
    client, holder = api
    kickoff = datetime.now(UTC) + timedelta(minutes=30)
    for _ in range(3):  # three users, two matches at the same venue
        _lightning(client, _match(client, kickoff))
    assert holder["fetcher"].calls == 1
    _lightning(client, _match(client, kickoff, "new_clark_city"))  # another venue: own check
    assert holder["fetcher"].calls == 2


def test_outside_the_live_window_nothing_is_fetched(api) -> None:
    client, holder = api
    body = _lightning(client, _match(client, datetime.now(UTC) + timedelta(days=2)))
    assert holder["fetcher"].calls == 0 and body["in_live_window"] is False
    assert body["status"]["state"] == "missing" and body["flash_count"] is None


def test_detected_lightning_shows_the_afc_procedure(api) -> None:
    client, holder = api
    holder["fetcher"] = FakeFetcher(_flash_payload())
    body = _lightning(client, _match(client, datetime.now(UTC) + timedelta(minutes=10)))
    assert body["flash_count"] == 1 and 0 < body["nearest_km"] < 10
    assert body["level"]["id"] == "within_30_second_distance"
    assert "Pitchy" in body["level"]["basis"]
    assert body["level"]["severity"] == "danger"
    guidance = body["guidance"]
    assert guidance["shown_because"] == ["LIGHTNING_DETECTED"]
    assert guidance["source"].startswith("AFC Competition Operations Manual")
    assert any("30 minutes" in step for step in guidance["procedure"])


def test_far_lightning_shows_guidance_but_no_level(api) -> None:
    client, holder = api
    holder["fetcher"] = FakeFetcher(_flash_payload(lat=14.75, lon=121.25))  # about 35 km
    body = _lightning(client, _match(client, datetime.now(UTC) + timedelta(minutes=10)))
    assert body["nearest_km"] > 30 and body["level"] is None
    assert body["guidance"]["shown_because"] == ["LIGHTNING_DETECTED"]


def test_pagasa_thunderstorm_alert_also_shows_the_procedure(api, connect) -> None:
    client, _ = api
    PgAlertRepository(connect).record_check(None, [{
        "identifier": "t", "issuer": "NCRPRSD", "event": "THUNDERSTORM", "subtype": "advisory",
        "headline": "h", "message": "m", "issued_at": None,
        "valid_until": datetime.now(UTC) + timedelta(hours=2), "areas": [],
        "matched_venues": ["rizal_memorial"]}], 0)  # fmt: skip
    body = _lightning(client, _match(client, datetime.now(UTC) + timedelta(days=2)))
    assert body["guidance"]["shown_because"] == ["PAGASA_THUNDERSTORM_ALERT"]


def test_failed_check_is_unavailable_and_counts_toward_the_interval(api) -> None:
    client, holder = api
    holder["fetcher"] = FakeFetcher(error=SourceUnavailableError("down", "HTTP_503"))
    kickoff = datetime.now(UTC) + timedelta(minutes=30)
    body = _lightning(client, _match(client, kickoff))
    assert body["status"]["state"] == "unavailable"
    assert body["status"]["last_error_code"] == "HTTP_503"
    _lightning(client, _match(client, kickoff))
    assert holder["fetcher"].calls == 1  # no hammering a source that is down


def test_lightning_checks_rotate_but_the_newest_per_venue_stays(api, connect, conn) -> None:
    client, holder = api
    kickoff = datetime.now(UTC) + timedelta(minutes=30)
    _lightning(client, _match(client, kickoff))
    conn.execute("update public.lightning_checks set checked_at = now() - interval '20 days'")
    conn.execute("update public.ingestion_jobs set requested_at = now() - interval '40 days'")
    assert (
        PgRetentionRepository(connect).purge(timedelta(days=14), timedelta(days=30))[
            "lightning_checks_deleted"
        ]
        == 0
    )  # it is the newest for Rizal
    assert conn.execute("select count(*) from public.lightning_checks").fetchone()[0] == 1
