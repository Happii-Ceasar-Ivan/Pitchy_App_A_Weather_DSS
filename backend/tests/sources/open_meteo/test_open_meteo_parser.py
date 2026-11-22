import copy
import json
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from services.weather_ingestion.sources.base import SourceResponseChangedError, Venue
from services.weather_ingestion.sources.open_meteo.adapter import (
    HOURLY_UNITS,
    parse,
    request_params,
)

FIXTURE = Path(__file__).parent / "fixtures" / "rizal_memorial_2026-11-22.json"
VENUE = Venue("loc-1", "rizal_memorial", "Rizal", 14.563405271502504, 120.99193149681405)


@pytest.fixture
def payload() -> dict:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def test_parses_every_variable_for_every_hour(payload) -> None:
    fetch = parse(payload, VENUE)
    hours = len(payload["hourly"]["time"])
    assert len(fetch.values) == hours * len(HOURLY_UNITS)
    assert {v.parameter for v in fetch.values} == set(HOURLY_UNITS)
    assert fetch.source_id == "open_meteo" and fetch.source_issued_at is None


def test_times_are_utc_hour_windows(payload) -> None:
    temps = [v for v in parse(payload, VENUE).values if v.parameter == "temperature_2m"]
    assert temps[0].forecast_valid_from == datetime(2026, 11, 22, 0, tzinfo=UTC)
    assert all(v.forecast_valid_until - v.forecast_valid_from == timedelta(hours=1) for v in temps)
    assert temps[0].unit == "°C" and temps[0].value_state == "ok"


def test_values_match_the_source_exactly(payload) -> None:
    i = payload["hourly"]["time"].index("2026-11-22T06:00")
    by_name = {
        v.parameter: v.value
        for v in parse(payload, VENUE).values
        if v.forecast_valid_from == datetime(2026, 11, 22, 6, tzinfo=UTC)
    }
    assert by_name["temperature_2m"] == payload["hourly"]["temperature_2m"][i]
    assert by_name["shortwave_radiation"] == payload["hourly"]["shortwave_radiation"][i]


def test_null_becomes_missing_not_a_guess(payload) -> None:
    payload["hourly"]["cape"][3] = None
    cape = [v for v in parse(payload, VENUE).values if v.parameter == "cape"][3]
    assert cape.value is None and cape.value_state == "missing"


@pytest.mark.parametrize(
    "break_it",
    [
        lambda p: p.update(utc_offset_seconds=28800),
        lambda p: p["hourly_units"].update(temperature_2m="°F"),
        lambda p: p["hourly"].pop("relative_humidity_2m"),
        lambda p: p["hourly"]["time"].__setitem__(0, "yesterday"),
        lambda p: p.pop("hourly"),
    ],
    ids=["non-utc", "unit-changed", "variable-missing", "bad-time", "no-hourly"],
)
def test_unexpected_responses_are_rejected(payload, break_it) -> None:
    broken = copy.deepcopy(payload)
    break_it(broken)
    with pytest.raises(SourceResponseChangedError):
        parse(broken, VENUE)


def test_request_asks_for_utc_ms_and_all_variables() -> None:
    params = request_params(VENUE)
    assert params["timezone"] == "GMT" and params["wind_speed_unit"] == "ms"
    assert params["hourly"].split(",") == list(HOURLY_UNITS)
    assert float(params["latitude"]) == VENUE.latitude
