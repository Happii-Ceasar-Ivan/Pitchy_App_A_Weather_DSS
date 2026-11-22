import copy
import json
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from services.weather_ingestion.sources.base import SourceResponseChangedError, Venue
from services.weather_ingestion.sources.pagasa.forecast import parse

FIXTURES = Path(__file__).parent / "fixtures"
VENUE = Venue("loc-1", "rizal_memorial", "Rizal", 14.563405271502504, 120.99193149681405)
ATMO_INIT = datetime(2026, 11, 21, 18, tzinfo=UTC)
ECMWF_INIT = datetime(2026, 11, 21, 12, tzinfo=UTC)


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


@pytest.fixture
def atmo() -> dict:
    return load("forecast_rizal_atmo_2026-11-21T18Z.json")


@pytest.fixture
def ecmwf() -> dict:
    return load("forecast_rizal_ecmwf_2026-11-21T12Z.json")


def series(fetch, name):
    return [v for v in fetch.values if v.parameter == name]


def test_atmo_first_step_is_the_run_time_in_utc(atmo) -> None:
    fetch = parse(atmo, VENUE, "atmo", ATMO_INIT)
    first = series(fetch, "heat_index")[0]
    # "2026-11-22 02:00:00" Philippine Time == 2026-11-21 18:00 UTC == the ATMO run.
    assert atmo["data"]["heat_index"][0]["forecast_at"] == "2026-11-22 02:00:00"
    assert first.forecast_valid_from == ATMO_INIT
    assert fetch.source_id == "pagasa_atmo" and fetch.source_issued_at == ATMO_INIT


def test_atmo_quarter_hour_then_hourly_windows(atmo) -> None:
    heat = series(parse(atmo, VENUE, "atmo", ATMO_INIT), "heat_index")
    widths = [v.forecast_valid_until - v.forecast_valid_from for v in heat]
    assert widths[0] == timedelta(minutes=15)
    assert widths[95] == timedelta(minutes=15) and widths[96] == timedelta(hours=1)
    assert all(
        a.forecast_valid_until == b.forecast_valid_from
        for a, b in zip(heat, heat[1:], strict=False)
    )


def test_ecmwf_uneven_steps_and_units(ecmwf) -> None:
    fetch = parse(ecmwf, VENUE, "ecmwf", ECMWF_INIT)
    heat = series(fetch, "heat_index")
    assert heat[0].forecast_valid_from == ECMWF_INIT
    widths = {v.forecast_valid_until - v.forecast_valid_from for v in heat[20:]}
    assert {timedelta(hours=3), timedelta(hours=6)} <= widths
    rain = series(fetch, "accumulated_rain_1h")[0]
    assert rain.unit == "mm" and series(fetch, "wind_speed")[0].unit == "m/s"


def test_rain_unit_comes_from_the_response(atmo) -> None:
    rain = series(parse(atmo, VENUE, "atmo", ATMO_INIT), "accumulated_rain_1h")
    assert rain[0].unit == "mm/h"


def test_icon_text_is_not_stored_as_a_value(atmo) -> None:
    fetch = parse(atmo, VENUE, "atmo", ATMO_INIT)
    assert {v.parameter for v in fetch.values} == {
        "heat_index", "wind_speed", "wind_direction", "accumulated_rain_1h"
    }  # fmt: skip
    assert "icon" in json.loads(fetch.raw_payload)["data"]


def test_utc_strings_would_be_caught_by_the_time_zone_guard(atmo) -> None:
    shifted = copy.deepcopy(atmo)
    for _name, items in shifted["data"].items():
        for item in items:
            local = datetime.strptime(item["forecast_at"], "%Y-%m-%d %H:%M:%S")
            item["forecast_at"] = (local - timedelta(hours=8)).strftime("%Y-%m-%d %H:%M:%S")
    with pytest.raises(SourceResponseChangedError, match="no longer match"):
        parse(shifted, VENUE, "atmo", ATMO_INIT)


@pytest.mark.parametrize(
    "break_it",
    [
        lambda p: p.update(success=False),
        lambda p: p.update(model="gfs"),
        lambda p: p.update(rain_unit="inch"),
        lambda p: p["data"].pop("wind_speed"),
        lambda p: p["data"]["wind_speed"].pop(),
        lambda p: p["data"]["heat_index"].__setitem__(0, {"forecast_at": "x", "value": 1}),
    ],
    ids=["not-success", "wrong-model", "rain-unit", "missing-var", "axis-differs", "bad-time"],
)
def test_unexpected_responses_are_rejected(atmo, break_it) -> None:
    broken = copy.deepcopy(atmo)
    break_it(broken)
    with pytest.raises(SourceResponseChangedError):
        parse(broken, VENUE, "atmo", ATMO_INIT)


def test_null_value_is_missing(atmo) -> None:
    atmo["data"]["heat_index"][5]["value"] = None
    heat = series(parse(atmo, VENUE, "atmo", ATMO_INIT), "heat_index")[5]
    assert heat.value is None and heat.value_state == "missing"
