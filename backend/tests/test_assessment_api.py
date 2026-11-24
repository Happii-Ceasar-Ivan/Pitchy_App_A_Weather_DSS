"""GET /match-contexts/{id}/assessment end to end (local PostgreSQL, no network).

Open-Meteo values are stored directly; WBGT is the real Liljegren calculation."""

import json
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from api.deps import get_adapter_groups, get_connect, get_lightning_fetcher
from services.safety_engine.rules import get_rules
from services.weather_ingestion import registry
from services.weather_ingestion.sources.xweather.lightning import parse
from shared.db.records import NewForecastValue
from shared.db.repositories import (
    PgForecastRepository,
    PgLocationRepository,
    PgRetentionRepository,
)
from shared.settings import Settings
from tests.conftest import requires_db

pytestmark = requires_db
API = API_V1_PREFIX
H = timedelta(hours=1)
# Tomorrow 06:00 UTC = 14:00 Manila: inside the PFF 09:00-15:00 window, outside the live
# lightning window.
KICKOFF = (datetime.now(UTC) + timedelta(days=1)).replace(hour=6, minute=0, second=0,
                                                          microsecond=0)  # fmt: skip
EMPTY = '{"success":true,"error":{"code":"warn_no_data"},"response":[]}'


def forecast(temp=33.0, rh=60.0, solar=800.0):
    values = []
    for i in range(-4, 6):
        t = KICKOFF + i * H
        for name, v, unit in (
            ("temperature_2m", temp, "°C"),
            ("relative_humidity_2m", rh, "%"),
            ("wind_speed_10m", 2.0, "m/s"),
            ("surface_pressure", 1008.0, "hPa"),
        ):
            values.append(NewForecastValue(name, v, unit, "ok", t, t + H, None))
        values.append(NewForecastValue("shortwave_radiation", solar, "W/m²", "ok", t - H, t, None))
    return values  # fmt: skip


def store(connect, **kw):
    loc = PgLocationRepository(connect).get_by_scope_key("rizal_memorial")
    return PgForecastRepository(connect).record_fetch("open_meteo", loc.id, None, forecast(**kw))


def quiet_sky(lat, lon, radius):
    return parse(EMPTY, lat, lon, radius)


@pytest.fixture
def client(connect):
    app = create_app(Settings(env="test"))
    app.dependency_overrides[get_connect] = lambda: connect
    app.dependency_overrides[get_adapter_groups] = lambda: registry.adapter_groups(Settings())
    app.dependency_overrides[get_lightning_fetcher] = lambda: quiet_sky
    return TestClient(app)


def new_match(client, age_group="senior") -> str:
    body = {"kickoff_at": KICKOFF.isoformat(), "venue": "rizal_memorial", "age_group": age_group}
    res = client.post(f"{API}/match-contexts", json=body)
    assert res.status_code == 201, res.text
    assert res.json()["age_group"] == age_group
    return res.json()["id"]


def assess(client, match_id) -> dict:
    res = client.get(f"{API}/match-contexts/{match_id}/assessment")
    assert res.status_code == 200, res.text
    return res.json()


def hazard(body, name) -> dict:
    return next(i for i in body["indicators"] if i["hazard"] == name)


def test_heat_assessment_from_the_real_wbgt_calculation(client, connect) -> None:
    store(connect)
    body = assess(client, new_match(client))
    heat = hazard(body, "heat")
    assert heat["status"] == "available"
    wbgt = heat["indicator_value"]
    assert 25.0 < wbgt < 40.0
    expected = "cooling_breaks_required" if wbgt >= 32.0 else "below_cooling_break_level"
    assert heat["classification"] == heat["level"]["id"] == expected
    assert heat["level"]["source"]["authority"] == "FIFA"
    assert [p["at"] for p in heat["points"]] == [
        (KICKOFF - timedelta(minutes=90)).isoformat().replace("+00:00", "Z"),
        (KICKOFF - H).isoformat().replace("+00:00", "Z"),
    ]
    assert {i["parameter"] for i in heat["inputs"]} == {
        "temperature_2m", "relative_humidity_2m", "wind_speed_10m", "surface_pressure",
        "shortwave_radiation"}  # fmt: skip
    assert all(i["provenance"]["source_id"] == "open_meteo" for i in heat["inputs"])
    assert "FORECAST_ESTIMATE" in [x["code"] for x in heat["limitations"]]
    assert [n["id"] for n in heat["notices"]] == ["pff_avoid_midday"]  # 14:00 Manila

    lightning = hazard(body, "lightning")
    assert "OUTSIDE_LIVE_WINDOW" in [x["code"] for x in lightning["limitations"]]
    assert hazard(body, "rainfall")["classification"] is None
    assert body["rules_approved"] is True and body["age_group"] == "senior"
    assert body["rule_version"].startswith(f"rules {get_rules().rule_set_version}")


def test_hot_youth_match_uses_the_28_degree_level(client, connect) -> None:
    store(connect, temp=30.0, rh=70.0, solar=700.0)
    senior = hazard(assess(client, new_match(client)), "heat")
    youth = hazard(assess(client, new_match(client, "youth_u20")), "heat")
    assert senior["indicator_value"] == youth["indicator_value"]
    if 28.0 <= youth["indicator_value"] < 32.0:
        assert senior["classification"] == "below_cooling_break_level"
        assert youth["classification"] == "cooling_breaks_required"
    assert youth["level"]["source"]["document_id"] == "afc_com_2026"


def test_saved_only_when_the_result_changes(client, connect, conn) -> None:
    store(connect)
    match_id = new_match(client)
    first, again = assess(client, match_id), assess(client, match_id)
    assert again["id"] == first["id"] and again["assessed_at"] == first["assessed_at"]
    assert conn.execute("select count(*) from public.safety_assessments").fetchone()[0] == 1
    used = conn.execute("select count(*) from public.assessment_inputs where assessment_id = %s",
                        (first["id"],)).fetchone()[0]  # fmt: skip
    assert used == len(hazard(first, "heat")["inputs"]) > 0
    saved = conn.execute("select result from public.safety_assessments").fetchone()[0]
    assert saved["input_fingerprint"] and saved["rule_version"] == first["rule_version"]

    store(connect, temp=34.0)  # a newer forecast: new inputs, new assessment
    changed = assess(client, match_id)
    assert changed["id"] != first["id"]
    assert conn.execute("select count(*) from public.safety_assessments").fetchone()[0] == 2


def test_stale_forecast_gives_no_level(client, connect, conn) -> None:
    fetch = store(connect)
    conn.execute(
        "update public.source_fetches set requested_at = requested_at - interval '8h',"
        " completed_at = completed_at - interval '8h' where id = %s",
        (fetch,),
    )
    heat = hazard(assess(client, new_match(client)), "heat")
    assert heat["status"] == "limited" and heat["classification"] is None
    assert heat["indicator_value"] is not None
    assert "STALE_INPUT" in [x["code"] for x in heat["limitations"]]


def test_audited_inputs_survive_rotation(client, connect, conn) -> None:
    old = store(connect)
    body = assess(client, new_match(client))
    store(connect, temp=31.0)
    conn.execute("update public.source_fetches set requested_at = requested_at - interval '20 days'"
                 " where id = %s", (old,))  # fmt: skip
    PgRetentionRepository(connect).purge(timedelta(days=14), timedelta(days=30))
    kept = conn.execute(
        "select count(*) from public.assessment_inputs ai join public.forecast_values v"
        " on v.id = ai.forecast_value_id where ai.assessment_id = %s", (body["id"],),
    ).fetchone()[0]  # fmt: skip
    assert kept == len(hazard(body, "heat")["inputs"])


def test_without_forecast_the_heat_indicator_is_unavailable(client) -> None:
    heat = hazard(assess(client, new_match(client)), "heat")
    assert heat["status"] == "unavailable" and heat["indicator_value"] is None


def test_unknown_match_is_not_found(client) -> None:
    missing = "00000000-0000-4000-8000-000000000001"
    assert client.get(f"{API}/match-contexts/{missing}/assessment").status_code == 404


def test_assessment_never_contains_raw_alert_html(client, connect) -> None:
    store(connect)
    assert "<" not in json.dumps(assess(client, new_match(client))["official_notices"])
