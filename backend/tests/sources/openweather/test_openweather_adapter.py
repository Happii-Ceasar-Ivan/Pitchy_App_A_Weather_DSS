import copy
import json
import logging
from datetime import UTC, datetime, timedelta
from pathlib import Path

import httpx
import pytest

from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import (
    SourceResponseChangedError,
    SourceUnavailableError,
    Venue,
)
from services.weather_ingestion.sources.openweather.adapter import (
    BASE_URL,
    FIELDS,
    OpenWeatherAdapter,
    parse,
    request_params,
)

FIXTURE = Path(__file__).parent / "fixtures" / "onecall_rizal_2026-11-28T04Z.json"
VENUE = Venue("loc-1", "rizal_memorial", "Rizal", 14.563405271502504, 120.99193149681405)
KEY = "test-key-0123456789abcdef"


@pytest.fixture
def payload() -> dict:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def adapter_with(handler) -> tuple[OpenWeatherAdapter, list[httpx.Request]]:
    seen: list[httpx.Request] = []

    def record(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)

    client = httpx.Client(transport=httpx.MockTransport(record), follow_redirects=False)
    return OpenWeatherAdapter(AllowlistedClient("test", client), KEY), seen


def test_parses_every_field_for_every_hour(payload) -> None:
    fetch = parse(payload, VENUE)
    assert len(payload["hourly"]) == 48
    assert len(fetch.values) == 48 * len(FIELDS)
    assert {v.parameter for v in fetch.values} == set(FIELDS)
    assert fetch.source_id == "openweather" and fetch.source_issued_at is None


def test_times_are_utc_hour_windows(payload) -> None:
    temps = [v for v in parse(payload, VENUE).values if v.parameter == "temp"]
    assert temps[0].forecast_valid_from == datetime(2026, 11, 28, 4, tzinfo=UTC)
    assert all(v.forecast_valid_until - v.forecast_valid_from == timedelta(hours=1) for v in temps)
    assert temps[0].value == payload["hourly"][0]["temp"] and temps[0].unit == "°C"


def test_pop_is_stored_as_percent_and_rain_as_mm_per_hour(payload) -> None:
    i = next(n for n, h in enumerate(payload["hourly"]) if "rain" in h)
    hour = datetime.fromtimestamp(payload["hourly"][i]["dt"], UTC)
    by_code = {v.parameter: v for v in parse(payload, VENUE).values
               if v.forecast_valid_from == hour}  # fmt: skip
    assert by_code["pop"].value == pytest.approx(payload["hourly"][i]["pop"] * 100)
    assert by_code["pop"].unit == "%"
    assert by_code["rain_1h"].value == payload["hourly"][i]["rain"]["1h"]
    assert by_code["rain_1h"].unit == "mm/h" and by_code["rain_1h"].value_state == "ok"
    assert by_code["pressure_msl"].unit == "hPa"


def test_absent_optional_fields_are_missing_not_zero(payload) -> None:
    payload["hourly"][0].pop("wind_gust")
    payload["hourly"][0].pop("rain", None)
    first = {v.parameter: v for v in parse(payload, VENUE).values
             if v.forecast_valid_from == datetime(2026, 11, 28, 4, tzinfo=UTC)}  # fmt: skip
    for code in ("wind_gust", "rain_1h"):
        assert first[code].value is None and first[code].value_state == "missing"


def test_null_becomes_missing(payload) -> None:
    payload["hourly"][2]["humidity"] = None
    hum = [v for v in parse(payload, VENUE).values if v.parameter == "humidity"][2]
    assert hum.value is None and hum.value_state == "missing"


@pytest.mark.parametrize(
    "break_it",
    [
        lambda p: p.pop("hourly"),
        lambda p: p.update(hourly=[]),
        lambda p: p.pop("lat"),
        lambda p: p.update(lat=p["lat"] + 1),  # answered for another point
        lambda p: p["hourly"][0].pop("temp"),  # a required field
        lambda p: p["hourly"][1].update(dt=p["hourly"][1]["dt"] + 1800),  # off the hour
        lambda p: p["hourly"].pop(3),  # a gap: steps no longer 1 h apart
        lambda p: p["hourly"][0].update(dt="2026-11-28T04:00"),
    ],
)
def test_unexpected_shapes_raise_instead_of_guessing(payload, break_it) -> None:
    broken = copy.deepcopy(payload)
    break_it(broken)
    with pytest.raises(SourceResponseChangedError):
        parse(broken, VENUE)


def test_request_params_are_metric_hourly_only() -> None:
    params = request_params(VENUE, KEY)
    assert params["units"] == "metric"
    assert params["exclude"] == "current,minutely,daily,alerts"
    assert params["appid"] == KEY


def test_fetch_sends_one_request_and_keeps_no_key(payload, caplog) -> None:
    adapter, seen = adapter_with(lambda r: httpx.Response(200, json=payload))
    with caplog.at_level(logging.DEBUG):
        (fetch,) = adapter.fetch(VENUE)
    assert len(seen) == 1 and str(seen[0].url).startswith(BASE_URL)
    assert KEY not in fetch.raw_payload and all(KEY not in n for n in fetch.notes)
    assert KEY not in caplog.text


def test_no_key_sends_nothing() -> None:
    seen: list[httpx.Request] = []
    client = httpx.Client(transport=httpx.MockTransport(lambda r: seen.append(r)))
    adapter = OpenWeatherAdapter(AllowlistedClient("test", client), None)
    with pytest.raises(SourceUnavailableError) as err:
        adapter.fetch(VENUE)
    assert err.value.code == "NOT_CONFIGURED" and seen == []


@pytest.mark.parametrize("status", [401, 429])
def test_blocking_answers_give_safe_codes_without_the_key(status, caplog) -> None:
    body = {"cod": status, "message": "refused"}
    adapter, seen = adapter_with(lambda r: httpx.Response(status, json=body))
    with caplog.at_level(logging.DEBUG), pytest.raises(SourceUnavailableError) as err:
        adapter.fetch(VENUE)
    assert err.value.code == f"HTTP_{status}" and len(seen) == 1  # no retry inside the adapter
    assert KEY not in str(err.value) and "openweathermap" not in str(err.value)
    assert KEY not in caplog.text


def test_non_json_is_a_changed_response() -> None:
    adapter, _ = adapter_with(lambda r: httpx.Response(200, text="<html>"))
    with pytest.raises(SourceResponseChangedError):
        adapter.fetch(VENUE)
