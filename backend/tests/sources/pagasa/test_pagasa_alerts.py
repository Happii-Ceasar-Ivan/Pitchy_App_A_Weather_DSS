import json
from datetime import UTC, datetime
from pathlib import Path

import pytest

from services.weather_ingestion.sources.base import SourceResponseChangedError
from services.weather_ingestion.sources.pagasa.alerts import (
    normalize_code,
    parse_alerts,
    parse_cyclone_track,
    plain_text,
)

FIXTURE = Path(__file__).parent / "fixtures" / "cap_alerts_2026-11-22.json"
RIZAL = {"133900000", "130000000"}  # City of Manila, Metro Manila
CLARK = {"036900000"}  # Tarlac


@pytest.fixture
def alerts():
    return parse_alerts(json.loads(FIXTURE.read_text(encoding="utf-8")))


def test_note_items_are_skipped(alerts) -> None:
    assert [a.event for a in alerts] == ["THUNDERSTORM", "THUNDERSTORM"]


def test_ncr_watch_covers_rizal_at_province_level(alerts) -> None:
    ncr = next(a for a in alerts if a.issuer == "NCRPRSD")
    assert ncr.covers(RIZAL) and not ncr.covers(CLARK)
    (area,) = ncr.matching_areas(RIZAL)
    assert (area.province, area.level, area.relation) == ("Metro Manila", "province", "watch")


def test_times_are_converted_from_philippine_time(alerts) -> None:
    ncr = next(a for a in alerts if a.issuer == "NCRPRSD")
    assert ncr.issued_at == datetime(2026, 11, 22, 2, 0, tzinfo=UTC)  # 10:00 PHT
    assert ncr.valid_until == datetime(2026, 11, 22, 14, 0, tzinfo=UTC)  # 22:00 PHT


def test_municipality_codes_missing_a_leading_zero_still_match(alerts) -> None:
    advisory = next(a for a in alerts if a.subtype == "thunderstorm advisory")
    assert all(len(a.code) == 9 and a.level == "municipality" for a in advisory.areas)
    assert normalize_code("97219000") == "097219000"
    assert normalize_code("") == normalize_code(None) == normalize_code("12a") == ""


def test_alert_text_is_plain_text_only() -> None:
    raw_note = json.loads(FIXTURE.read_text(encoding="utf-8"))["data"]["alert_data"][0]
    assert "<script>" in raw_note["headline"]  # what PAGASA really sent
    assert plain_text(raw_note["headline"]) == ""
    assert plain_text("<b>Heavy</b> rain &amp; wind\n\n now") == "Heavy rain & wind now"
    assert "<" not in plain_text('<img src=x onerror="alert(1)">Thunderstorm')


def test_failed_or_changed_alert_payloads_are_rejected() -> None:
    with pytest.raises(SourceResponseChangedError):
        parse_alerts({"success": False})
    with pytest.raises(SourceResponseChangedError):
        parse_alerts({"success": True, "data": {}})


def test_no_active_cyclone() -> None:
    assert parse_cyclone_track([]) == 0
    with pytest.raises(SourceResponseChangedError):
        parse_cyclone_track("maintenance")
