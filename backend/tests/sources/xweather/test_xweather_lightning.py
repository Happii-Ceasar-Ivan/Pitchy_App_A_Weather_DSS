from datetime import UTC, datetime
from pathlib import Path

import httpx
import pytest

from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import (
    SourceResponseChangedError,
    SourceUnavailableError,
)
from services.weather_ingestion.sources.xweather.lightning import (
    XweatherLightning,
    distance_km,
    parse,
)

FIXTURES = Path(__file__).parent / "fixtures"
RIZAL = (14.563405271502504, 120.99193149681405)


def _text(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def test_real_empty_response_means_nothing_detected() -> None:
    reading = parse(_text("flash_closest_rizal_empty_2026-11-23.json"), *RIZAL, 40)
    assert reading.flashes == [] and reading.nearest_km is None and reading.latest_at is None
    assert len(reading.raw_payload_sha256) == 64


def test_flashes_get_distance_and_are_sorted_nearest_first() -> None:
    reading = parse(_text("flash_closest_docs_example.json"), *RIZAL, 40)
    # By hand: 0.0366° lat ≈ 4.07 km, 0.0481° lon × cos(14.58°) ≈ 5.18 km → ≈ 6.58 km.
    distances = [f.distance_km for f in reading.flashes]
    assert distances == [pytest.approx(6.58, abs=0.01), pytest.approx(34.66, abs=0.01)]
    assert reading.flashes[0].detected_at == datetime(2026, 11, 23, 15, 3, 14, tzinfo=UTC)
    assert reading.latest_at == reading.flashes[0].detected_at


def test_distance_is_great_circle() -> None:
    assert distance_km(0, 0, 0, 1) == pytest.approx(111.19, abs=0.01)
    assert distance_km(*RIZAL, *RIZAL) == 0


@pytest.mark.parametrize(
    ("text", "error"),
    [
        ('{"success": false, "error": {"code": "invalid_client"}, "response": []}',
         SourceUnavailableError),
        ("<html>maintenance</html>", SourceResponseChangedError),
        ('{"success": true, "error": null, "response": [{"loc": {}, "ob": {}}]}',
         SourceResponseChangedError),
        ('{"success": true, "error": {"code": "warn_other"}, "response": [{"x": 1}]}',
         SourceResponseChangedError),
    ],
)  # fmt: skip
def test_failures_are_reported_never_guessed(text, error) -> None:
    with pytest.raises(error):
        parse(text, *RIZAL, 40)


def test_refused_request_code_is_safe() -> None:
    with pytest.raises(SourceUnavailableError) as exc:
        parse('{"success": false, "error": {"code": "invalid client!"}}', *RIZAL, 40)
    assert exc.value.code == "XWEATHER_INVALID_CLIENT_"


def test_missing_keys_never_call_out() -> None:
    def no_network(request):
        raise AssertionError("must not call Xweather without keys")

    client = AllowlistedClient("t", httpx.Client(transport=httpx.MockTransport(no_network)))
    with pytest.raises(SourceUnavailableError) as exc:
        XweatherLightning(client, None, None).fetch(*RIZAL, 40)
    assert exc.value.code == "NOT_CONFIGURED"


def test_request_shape_and_keys_stay_out_of_errors() -> None:
    seen = {}

    def answer(request):
        seen.update(request.url.params)
        return httpx.Response(503)

    client = AllowlistedClient("t", httpx.Client(transport=httpx.MockTransport(answer)))
    with pytest.raises(SourceUnavailableError) as exc:
        XweatherLightning(client, "id-123", "secret-456").fetch(*RIZAL, 99)
    assert seen["radius"] == "40km" and seen["limit"] == "1000"  # capped at Xweather's max
    assert seen["p"] == f"{RIZAL[0]},{RIZAL[1]}"
    assert "secret-456" not in exc.value.message and exc.value.code == "HTTP_503"
