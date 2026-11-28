"""Pure checks of the coverage, hourly-value and direction-range helpers (no database)."""

from datetime import UTC, datetime, timedelta

from services.weather_ingestion.relevance.consolidation import (
    SourceParam,
    StoredValue,
    _arc,
    hourly_value,
)
from services.weather_ingestion.relevance.freshness import (
    FreshnessRule,
    assess_source,
    covers,
)
from shared.db.records import FetchAttempt, FetchCoverage

T = datetime(2026, 12, 1, 7, tzinfo=UTC)
H = timedelta(hours=1)


def test_covers_needs_the_whole_window_without_gaps() -> None:
    assert covers([(T, T + H), (T + H, T + 2 * H)], T, T + 2 * H)
    assert covers([(T - 3 * H, T + 3 * H)], T, T + 2 * H)  # one long PAGASA step
    assert not covers([(T, T + H), (T + 90 * H / 60, T + 2 * H)], T, T + 2 * H)  # 30-min gap
    assert not covers([(T + H, T + 3 * H)], T, T + 2 * H)  # starts after kickoff
    assert not covers([], T, T + H)


def _row(value, start, minutes, unit="mm/h", state="ok"):
    return StoredValue("p", value, unit, state, start, start + timedelta(minutes=minutes))


def test_hourly_values_by_kind() -> None:
    quarters = [_row(v, T + timedelta(minutes=15 * i), 15) for i, v in enumerate([0, 1, 2, 1])]
    assert hourly_value(quarters, SourceParam("s", "p", "mm/h", "rate"), T) == 1.0
    assert hourly_value(quarters[:3], SourceParam("s", "p", "mm/h", "rate"), T) is None
    three_hours = [_row(9.0, T, 180, unit="mm")]
    assert hourly_value(three_hours, SourceParam("s", "p", "mm", "amount"), T) is None
    assert hourly_value([_row(0.4, T, 60, "mm")], SourceParam("s", "p", "mm", "amount"), T) == 0.4
    assert hourly_value(three_hours, SourceParam("s", "p", "°C"), T + H) is None  # unit differs
    assert hourly_value([_row(5, T, 60, "°C", "missing")], SourceParam("s", "p", "°C"), T) is None


def test_direction_range_is_the_smallest_arc() -> None:
    assert _arc([350, 20]) == (350, 20)
    assert _arc([10, 90, 50]) == (10, 90)


def _fetch(retrieved, issued=None, windows=((T, T + 2 * H),)):
    return FetchCoverage("f", retrieved, issued, windows)


def test_state_rules() -> None:
    rule = FreshnessRule(12 * H, "issued")
    now = T
    fresh = assess_source("a", rule, [_fetch(now, issued=now - H)], None, None, T, T + 2 * H, now)
    assert (fresh.state, fresh.current_until) == ("current", now + 11 * H)
    old = assess_source("a", rule, [_fetch(now, now - 13 * H)], None, None, T, T + 2 * H, now)
    assert old.state == "stale"
    failed = FetchAttempt("x", "failed", now, "HTTP_503", "down")
    gone = assess_source("a", rule, [], failed, None, T, T + 2 * H, now)
    assert gone.state == "unavailable" and gone.notes[0].code == "SOURCE_ERROR"
    assert gone.notes[0].detail_code == "HTTP_503" and "HTTP" not in gone.notes[0].message
    no_rule = assess_source("a", None, [_fetch(now)], None, None, T, T + 2 * H, now)
    assert no_rule.state == "unavailable"  # never "current" without a configured rule


def test_unavailable_needs_data() -> None:
    failed = FetchAttempt("x", "failed", T, "HTTP_503", "down")
    gone = assess_source("a", FreshnessRule(H, "retrieved"), [], failed, None, T, T + H, T)
    assert gone.state == "unavailable" and gone.needs_data


def test_openweather_is_lowest_priority_and_unconfirmed_windows_stay_out_of_range() -> None:
    """P-30: OpenWeather is chosen only when no other source has a value; its `pop` and
    `rain_1h` are shown per source but not counted in the range (window not stated)."""
    from services.weather_ingestion.relevance.consolidation import (
        QUANTITIES,
        SourceData,
        consolidate,
    )

    for spec in QUANTITIES:
        ids = [p.source_id for p in spec.sources]
        if "openweather" in ids:
            assert ids[-1] == "openweather", spec.key
    ow = {(q.key, p.parameter): p for q in QUANTITIES for p in q.sources
          if p.source_id == "openweather"}  # fmt: skip
    assert not ow[("rain", "rain_1h")].in_range and not ow[("rain_probability", "pop")].in_range
    assert ow[("air_temperature", "temp")].in_range

    def data(sid, param, unit, value):
        return SourceData(sid, sid, "current", [StoredValue(param, value, unit, "ok", T, T + H)])

    views = {v.spec.key: v for v in consolidate({
        "open_meteo": data("open_meteo", "precipitation_probability", "%", 40.0),
        "openweather": data("openweather", "pop", "%", 37.0),
    }, T, T + H)}  # fmt: skip
    slot = views["rain_probability"].slots[0]
    assert slot.source_id == "open_meteo" and slot.value == 40.0
    assert {v.source_id for v in slot.by_source} == {"open_meteo", "openweather"}
    assert slot.range is None  # only one comparable source
    temp = consolidate({"openweather": data("openweather", "temp", "°C", 31.2)}, T, T + H)
    chosen = next(v for v in temp if v.spec.key == "air_temperature").slots[0]
    assert chosen.source_id == "openweather" and chosen.value == 31.2
