"""Safety engine rules at their edges (no database). WBGT is pinned so each edge is exact."""

from datetime import UTC, datetime, timedelta

import pytest

from services.safety_engine import engine
from services.safety_engine.rules import get_rules
from services.safety_engine.wbgt.liljegren import ScreeningResult, WbgtResult

H = timedelta(hours=1)
KICKOFF = datetime(2026, 12, 1, 10, 0, tzinfo=UTC)  # 18:00 Manila time (outside PFF window)
LAT, LON = 14.5634, 120.9919


def rows_for(stamps, *, drop: str | None = None):
    rows, n = [], 0
    for t in stamps:
        for name, unit in engine.INSTANT.items():
            if name != drop:
                n += 1
                rows.append(engine.WeatherRow(n, name, 1.0, unit, "ok", t, t + H))
        for name, unit in engine.PRECEDING.items():
            if name != drop:
                n += 1
                rows.append(engine.WeatherRow(n, name, 500.0, unit, "ok", t - H, t))
    return rows


def weather(current=True, **kw):
    stamps = [KICKOFF - 3 * H + i * H for i in range(8)]
    return engine.OpenMeteoData(current, KICKOFF - 2 * H, None, rows_for(stamps, **kw))


@pytest.fixture
def pin(monkeypatch):
    """Make WBGT a chosen value per forecast stamp (default for all stamps)."""
    values: dict = {}

    def fake(at, **_):
        w = values.get(at, values.get("default", 30.0))
        r = WbgtResult(True, w, w + 5, w - 2, w - 3, 1.0, 0.5, 0.5, 500.0)
        return ScreeningResult(r, True, -1.0, values.get("spread", 0.0))

    monkeypatch.setattr(engine, "wbgt_screening", fake)
    return values


def run(*, age="senior", kickoff=KICKOFF, data=None, lightning=None, alert=False, rules=None):
    return engine.assess(
        rules or get_rules(), age_group=age, kickoff_at=kickoff, latitude=LAT, longitude=LON,
        weather=weather() if data is None else data, lightning=lightning,
        thunderstorm_alert=alert, match_hours=2,
    )  # fmt: skip


def heat(a):
    return next(i for i in a.indicators if i.hazard == "heat")


def lightning_of(a):
    return next(i for i in a.indicators if i.hazard == "lightning")


@pytest.mark.parametrize(
    ("age", "value", "level"),
    [
        ("senior", 31.99, "below_cooling_break_level"),
        ("senior", 32.0, "cooling_breaks_required"),
        ("youth_u20", 27.99, "below_cooling_break_level"),
        ("youth_u20", 28.0, "cooling_breaks_required"),
        ("youth_u20", 31.0, "cooling_breaks_required"),
    ],
)
def test_heat_levels_at_their_edges(pin, age, value, level) -> None:
    pin["default"] = value
    h = heat(run(age=age))
    assert (h.status, h.level.id, h.value) == ("available", level, value)
    assert h.level.severity == ("warning" if level == "cooling_breaks_required" else "advisory")
    assert h.level.reference.issuer in {"FIFA", "Asian Football Confederation (AFC)"}
    assert "match management team" in h.decided_by


def test_the_higher_fifa_measurement_sets_the_level(pin) -> None:
    kickoff = KICKOFF + timedelta(minutes=30)  # 10:30 UTC: points at 09:00 and 09:30
    pin[KICKOFF - H] = 33.0  # stamp 09:00 (for the -90 min point)
    pin[KICKOFF] = 31.0  # stamp 10:00 (for the -60 min point, 09:30 rounded up)
    h = heat(run(kickoff=kickoff))
    assert [p.stamp for p in h.points] == [KICKOFF - H, KICKOFF]
    assert h.value == 33.0 and h.level.id == "cooling_breaks_required"
    assert [p.used_for_level for p in h.points] == [True, False]


def test_points_are_at_90_and_60_minutes_before_kickoff(pin) -> None:
    h = heat(run())
    assert [p.at for p in h.points] == [KICKOFF - timedelta(minutes=90), KICKOFF - H]
    assert [p.stamp for p in h.points] == [KICKOFF - H, KICKOFF - H]  # whole hour at or after
    assert len(h.hourly) == 3  # kickoff, +1 h, +2 h


def test_stale_forecast_is_shown_but_never_classified(pin) -> None:
    pin["default"] = 35.0
    h = heat(run(data=weather(current=False)))
    assert h.status == "limited" and h.level is None and h.value == 35.0
    assert "STALE_INPUT" in [n.code for n in h.limitations]


def test_missing_pressure_makes_wbgt_unavailable_not_estimated(pin) -> None:
    h = heat(run(data=weather(drop="surface_pressure")))
    assert h.status == "unavailable" and h.value is None and h.level is None
    assert all("surface_pressure" in p.missing for p in h.points)


def test_no_forecast_at_all(pin) -> None:
    h = heat(engine.assess(get_rules(), age_group="senior", kickoff_at=KICKOFF, latitude=LAT,
                           longitude=LON, weather=None, lightning=None, thunderstorm_alert=False,
                           match_hours=2))  # fmt: skip
    assert h.status == "unavailable" and "MISSING_INPUT" in [n.code for n in h.limitations]


def test_screening_note_only_when_the_unknown_inputs_matter(pin) -> None:
    assert "SCREENING_ASSUMPTION" not in [n.code for n in heat(run()).limitations]
    pin["spread"] = 0.4
    assert "SCREENING_ASSUMPTION" in [n.code for n in heat(run()).limitations]


@pytest.mark.parametrize(
    ("local", "shown"),
    [("08:59", False), ("09:00", True), ("12:00", True), ("15:00", True), ("15:01", False)],
)
def test_pff_midday_notice_by_manila_kickoff_time(pin, local, shown) -> None:
    hh, mm = map(int, local.split(":"))
    kickoff = datetime(2026, 12, 1, hh - 8, mm, tzinfo=UTC)  # Manila is UTC+8
    notices = heat(run(kickoff=kickoff)).notices
    assert bool(notices) is shown
    if shown:
        assert notices[0][0] == "pff_avoid_midday" and notices[0][2].issuer.startswith("Philippine")


def live(km, count=1, state="current"):
    return engine.LightningInput(state, True, KICKOFF, count, km)


@pytest.mark.parametrize(
    ("km", "level"), [(9.9, "within_30_second_distance"), (10.0, "within_30_second_distance"),
                      (10.1, None)],
)  # fmt: skip
def test_lightning_10_km_level(pin, km, level) -> None:
    ind = lightning_of(run(lightning=live(km)))
    assert ind.status == "available" and ind.value == km
    assert (ind.level.id if ind.level else None) == level
    assert (ind.level.severity if ind.level else None) == ("danger" if level else None)
    assert ind.procedure  # AFC 30/30 shown whenever lightning is detected


def test_no_lightning_detected_is_never_called_safe(pin) -> None:
    ind = lightning_of(run(lightning=live(None, count=0)))
    assert ind.status == "available" and ind.level is None and not ind.procedure
    assert "NONE_DETECTED" in [n.code for n in ind.limitations]
    assert "not a statement that it is safe" in ind.limitations[-1].message


def test_thunderstorm_alert_shows_the_procedure_without_a_level(pin) -> None:
    ind = lightning_of(run(lightning=live(None, count=0), alert=True))
    assert ind.procedure and ind.level is None


def test_lightning_outside_the_live_window_or_stale(pin) -> None:
    outside = engine.LightningInput("missing", False, None, None, None)
    assert "OUTSIDE_LIVE_WINDOW" in [
        n.code for n in lightning_of(run(lightning=outside)).limitations
    ]
    stale = lightning_of(run(lightning=live(3.0, state="stale")))
    assert stale.status == "unavailable" and stale.level is None


def test_lightning_error_code_is_kept_out_of_the_message(pin) -> None:
    failed = engine.LightningInput("unavailable", True, None, None, None, "HTTP_503")
    note = next(n for n in lightning_of(run(lightning=failed)).limitations
                if n.code == "MISSING_INPUT")  # fmt: skip
    assert note.detail_code == "HTTP_503" and "HTTP" not in note.message


def test_rain_has_no_rule_and_officials_decide(pin) -> None:
    a = run()
    rain = next(i for i in a.indicators if i.hazard == "rainfall")
    assert rain.status == "unavailable" and rain.level is None
    assert [n.code for n in a.limitations] == ["OFFICIALS_DECIDE"]
    assert a.rule_version.startswith(f"rules {get_rules().rule_set_version}; engine ")


def test_draft_rules_are_flagged(pin) -> None:
    draft = get_rules().model_copy(update={"status": "draft"})
    notes = {n.code: n.message for n in run(rules=draft).limitations}
    assert "RULES_NOT_APPROVED" in notes
    assert (
        "draft" in notes["OFFICIALS_DECIDE"] and "approved rules" not in notes["OFFICIALS_DECIDE"]
    )
    assert "approved rules" in {n.code: n.message for n in run().limitations}["OFFICIALS_DECIDE"]


def test_heat_is_flagged_until_wbgt_validation_is_complete(pin) -> None:
    codes = [n.code for n in heat(run()).limitations]
    assert ("VALIDATION_PENDING" in codes) is (not engine.WBGT_VALIDATION_COMPLETE)
