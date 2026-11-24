"""Deterministic safety assessment (B4, FR-SAF-001..005). Pure functions; no I/O, no AI.

Uses only the approved rules in ``thresholds/rules.yaml`` (P-12). Pitchy explains what those
rules say about a match; the official decision stays with the people the rules name.

- Heat: outdoor WBGT estimated with Liljegren (DEC-05) from Open-Meteo, at FIFA's measurement
  times (90 and 60 minutes before kickoff). The higher value sets the level from the match's age
  group. A level is given only from **current** forecast data; stale data is shown, not classified.
- PFF midday notice: shown when local kickoff is in its window. It never changes the level.
- Lightning: the latest shared Xweather check; the AFC 10 km level if the nearest flash is
  within it. No level never means "safe".
- Rain: no approved rule (P-11), so no classification.
"""

import math
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from services.safety_engine.rules import LightningGuidance, RuleSet, Source
from services.safety_engine.wbgt.liljegren import wbgt_screening

ENGINE_VERSION = "b4.1"
WBGT_METHOD_VERSION = "liljegren-wbgt-1.1-py1"
HOUR = timedelta(hours=1)
AVERAGING_MINUTES = 60  # Open-Meteo radiation is the mean of the preceding hour
WIND_HEIGHT_M = 10.0  # Open-Meteo wind_speed_10m
# DEC-05: the port matches the original Liljegren C program on 193 reference cases within
# 0.0001 °C (tests/safety_engine/test_liljegren_reference.py; wbgt/README.md).
WBGT_VALIDATION_COMPLETE = True
SCREENING_NOTE_MIN_SPREAD = 0.05  # °C; below this the unknown site inputs don't matter

# Open-Meteo parameters the WBGT needs, and how each is read for a forecast stamp T:
INSTANT = {  # valid [T, T + 1 h)
    "temperature_2m": "°C",
    "relative_humidity_2m": "%",
    "wind_speed_10m": "m/s",
    "surface_pressure": "hPa",
}
PRECEDING = {"shortwave_radiation": "W/m²"}  # mean of [T - 1 h, T)


@dataclass(frozen=True)
class WeatherRow:
    """One stored forecast value (``forecast_values`` row)."""

    id: int
    parameter: str
    value: float | None
    unit: str | None
    value_state: str
    valid_from: datetime
    valid_until: datetime


@dataclass(frozen=True)
class OpenMeteoData:
    current: bool  # DEC-04 freshness of the fetch used
    retrieved_at: datetime
    current_until: datetime | None
    rows: Sequence[WeatherRow]


@dataclass(frozen=True)
class LightningInput:
    state: str  # current | stale | missing | updating | unavailable (P-05)
    in_live_window: bool
    checked_at: datetime | None
    flash_count: int | None
    nearest_km: float | None
    last_error_code: str | None = None


@dataclass(frozen=True)
class Note:
    code: str
    message: str


@dataclass(frozen=True)
class Reference:
    source_id: str
    issuer: str
    title: str
    version: str
    section: str | None


@dataclass(frozen=True)
class LevelOut:
    id: str
    label: str
    action: str
    reference: Reference
    also_supported_by: tuple[Reference, ...] = ()


@dataclass
class Point:
    """WBGT for one forecast stamp."""

    at: datetime  # the time this point stands for
    stamp: datetime  # the Open-Meteo stamp used (instant values at it; radiation the hour before)
    wbgt: float | None = None
    globe: float | None = None
    natural_wet_bulb: float | None = None
    used_for_level: bool = False
    missing: list[str] = field(default_factory=list)
    spread: float = 0.0
    inputs: list[WeatherRow] = field(default_factory=list)


@dataclass
class Indicator:
    hazard: str  # heat | lightning | rainfall
    status: str  # available | limited | unavailable
    value: float | None = None
    unit: str | None = None
    level: LevelOut | None = None
    basis: str | None = None
    decided_by: str | None = None
    points: list[Point] = field(default_factory=list)
    hourly: list[Point] = field(default_factory=list)
    inputs: list[WeatherRow] = field(default_factory=list)
    notices: list[tuple[str, str, Reference]] = field(default_factory=list)  # id, text, source
    guidance: list[Reference] = field(default_factory=list)
    procedure: list[str] = field(default_factory=list)
    limitations: list[Note] = field(default_factory=list)


@dataclass
class Assessment:
    rule_version: str
    rules_approved: bool
    age_group: str
    indicators: list[Indicator]
    limitations: list[Note]


def rule_version(rules: RuleSet) -> str:
    return f"rules {rules.rule_set_version}; engine {ENGINE_VERSION}; wbgt {WBGT_METHOD_VERSION}"


def _ref(rules: RuleSet, source_id: str) -> Reference:
    s: Source = rules.sources[source_id]
    return Reference(source_id, s.issuer, s.title, s.version, s.section)


def _iso(t: datetime) -> str:
    return t.isoformat(timespec="minutes")


def _ceil_hour(t: datetime) -> datetime:
    floor = t.replace(minute=0, second=0, microsecond=0)
    return floor if floor == t else floor + HOUR


def _wbgt_point(at: datetime, rows: Sequence[WeatherRow], latitude: float, longitude: float):
    """WBGT for time ``at`` from the forecast stamped at the first whole hour at or after it:
    instant values at that stamp, radiation averaged over the hour before it (which contains
    ``at``). Nothing is interpolated or filled in."""
    stamp = _ceil_hour(at)
    point = Point(at=at, stamp=stamp)
    found: dict[str, WeatherRow] = {}
    for r in rows:
        if r.parameter in INSTANT and r.valid_from == stamp and r.unit == INSTANT[r.parameter]:
            found[r.parameter] = r
        elif (r.parameter in PRECEDING and r.valid_until == stamp
              and r.unit == PRECEDING[r.parameter]):  # fmt: skip
            found[r.parameter] = r
    for name in (*INSTANT, *PRECEDING):
        r = found.get(name)
        if r is None or r.value_state != "ok" or r.value is None:
            point.missing.append(name)
    if point.missing:
        return point
    point.inputs = [found[n] for n in (*INSTANT, *PRECEDING)]
    screened = wbgt_screening(
        at=stamp,
        averaging_minutes=AVERAGING_MINUTES,
        latitude=latitude,
        longitude=longitude,
        solar=found["shortwave_radiation"].value,
        pressure=found["surface_pressure"].value,
        air_temperature=found["temperature_2m"].value,
        relative_humidity=found["relative_humidity_2m"].value,
        wind_speed=found["wind_speed_10m"].value,
        wind_height=WIND_HEIGHT_M,
    )
    if screened is None:
        point.missing.append("no_convergence")
        return point
    r = screened.result
    point.wbgt, point.globe, point.natural_wet_bulb = r.wbgt, r.globe, r.natural_wet_bulb
    point.spread = screened.spread
    return point


def assess_heat(
    rules: RuleSet,
    age_group: str,
    kickoff_at: datetime,
    latitude: float,
    longitude: float,
    weather: OpenMeteoData | None,
    match_hours: float,
) -> Indicator:
    heat = rules.hazards.heat
    ind = Indicator("heat", "unavailable", unit=heat.unit, decided_by=heat.decided_by,
                    basis=heat.method)  # fmt: skip
    ind.limitations.append(Note("FORECAST_ESTIMATE", " ".join(heat.measurement_note.split())))
    if not WBGT_VALIDATION_COMPLETE:
        ind.limitations.append(Note(
            "VALIDATION_PENDING",
            "The WBGT calculation matches the original Liljegren program on one published "
            "reference case; validation against a fuller reference table is still pending.",
        ))  # fmt: skip
    if weather is None:
        ind.limitations.append(Note("MISSING_INPUT", "No Open-Meteo forecast covers this match."))
        return ind

    for minutes in heat.evaluate_at_minutes_before_kickoff:
        ind.points.append(_wbgt_point(kickoff_at - timedelta(minutes=minutes), weather.rows,
                                      latitude, longitude))  # fmt: skip
    stamp = _ceil_hour(kickoff_at)
    while stamp < kickoff_at + timedelta(hours=match_hours) + HOUR:
        ind.hourly.append(_wbgt_point(stamp, weather.rows, latitude, longitude))
        stamp += HOUR

    good = [p for p in ind.points if p.wbgt is not None]
    for p in ind.points:
        if p.wbgt is None:
            ind.limitations.append(Note(
                "MISSING_INPUT",
                f"WBGT for {p.at.isoformat(timespec='minutes')} is unavailable: missing "
                f"{', '.join(p.missing)} in the forecast stamped "
                f"{p.stamp.isoformat(timespec='minutes')}.",
            ))  # fmt: skip
    if not good:
        return ind

    top = max(good, key=lambda p: p.wbgt)
    top.used_for_level = True
    ind.value = top.wbgt
    seen: set[int] = set()
    for p in good:
        for row in p.inputs:
            if row.id not in seen:
                seen.add(row.id)
                ind.inputs.append(row)
    if max(p.spread for p in good) >= SCREENING_NOTE_MIN_SPREAD:
        ind.limitations.append(Note(
            "SCREENING_ASSUMPTION",
            "Urban/rural wind profile and night-time air stability are not in the forecast; "
            "both were computed and the higher WBGT is shown "
            f"(difference up to {max(p.spread for p in good):.1f} °C).",
        ))  # fmt: skip

    if not weather.current:
        ind.status = "limited"
        ind.limitations.append(Note(
            "STALE_INPUT",
            f"The Open-Meteo forecast (retrieved {_iso(weather.retrieved_at)}) is no longer "
            "current, so no level is given. Refresh the weather data.",
        ))  # fmt: skip
        return ind

    level_set = heat.level_set(age_group)
    level = level_set.level_for(top.wbgt)
    ind.level = LevelOut(
        level.id,
        level.label,
        level.action,
        _ref(rules, level.source),
        tuple(_ref(rules, s) for s in level.also_supported_by),
    )
    ind.basis = f"{heat.method}; level set {level_set.id} ({level_set.applies_to})"
    ind.status = "available" if len(good) == len(ind.points) else "limited"
    return ind


def heat_notices(rules: RuleSet, kickoff_at: datetime) -> list[tuple[str, str, Reference]]:
    """PFF-style notices whose local kickoff window contains the kickoff (ends inclusive)."""
    out = []
    for notice in rules.hazards.heat.notices:
        window = notice.applies_when
        local = kickoff_at.astimezone(ZoneInfo(window.timezone)).time().replace(tzinfo=None)
        start, end = window.local_kickoff_between
        if start <= local <= end:
            out.append((notice.id, " ".join(notice.text.split()), _ref(rules, notice.source)))
    return out


def assess_lightning(
    rules: RuleSet, lightning: LightningInput | None, thunderstorm_alert: bool
) -> Indicator:
    ind = Indicator("lightning", "unavailable", unit="km")
    guide = rules.hazards.lightning
    if not isinstance(guide, LightningGuidance):
        ind.limitations.append(Note("NO_APPROVED_RULE", guide.reason))
        return ind
    ind.basis = "Vaisala Xweather detection, past 5 minutes; AFC 30/30 procedure"
    ind.decided_by = "officials on site (AFC General Coordinator and/or Match Commissioner)"
    ind.limitations.append(Note("DETECTION_NOT_FORECAST", " ".join(guide.reason.split())))

    detected = False
    if lightning is None or not lightning.in_live_window:
        ind.limitations.append(Note(
            "OUTSIDE_LIVE_WINDOW",
            "Lightning is checked live only from shortly before kickoff to the end of the match.",
        ))  # fmt: skip
    elif lightning.state == "current" and lightning.flash_count is not None:
        ind.status = "available"
        ind.value = lightning.nearest_km
        detected = bool(lightning.flash_count)
        found = guide.level_for_distance(lightning.nearest_km) if detected else None
        if found is not None:
            ind.level = LevelOut(found.id, found.label, " ".join(found.action.split()),
                                 _ref(rules, found.source))  # fmt: skip
            ind.limitations.append(Note("PITCHY_CONVERSION", " ".join(found.basis.split())))
        elif detected:
            ind.limitations.append(Note(
                "NO_LEVEL_BEYOND_10_KM",
                "Lightning was detected but not within about 10 km. No level is not a statement "
                "that it is safe.",
            ))  # fmt: skip
        else:
            ind.limitations.append(Note(
                "NONE_DETECTED",
                "No lightning detected in the last 5 minutes. This is not a statement that it is "
                "safe; watch for thunder and official alerts.",
            ))  # fmt: skip
    else:
        state = lightning.state
        ind.status = "unavailable"
        code = "STALE_INPUT" if state == "stale" else "MISSING_INPUT"
        detail = f" ({lightning.last_error_code})" if lightning.last_error_code else ""
        ind.limitations.append(Note(code, f"No current lightning check: {state}{detail}."))

    if detected or thunderstorm_alert:
        ind.guidance.append(_ref(rules, guide.source))
        ind.procedure = list(guide.procedure)
    return ind


def assess_rainfall(rules: RuleSet) -> Indicator:
    rain = rules.hazards.rainfall
    ind = Indicator("rainfall", "unavailable", unit="mm/h")
    ind.limitations.append(Note("NO_APPROVED_RULE", f"{rain.reason} {rain.show_instead}"))
    return ind


def assess(
    rules: RuleSet,
    *,
    age_group: str,
    kickoff_at: datetime,
    latitude: float,
    longitude: float,
    weather: OpenMeteoData | None,
    lightning: LightningInput | None,
    thunderstorm_alert: bool,
    match_hours: float,
) -> Assessment:
    kickoff_at = kickoff_at.astimezone(UTC)
    heat = assess_heat(rules, age_group, kickoff_at, latitude, longitude, weather, match_hours)
    heat.notices = heat_notices(rules, kickoff_at)
    limitations = [Note(
        "OFFICIALS_DECIDE",
        "Pitchy shows what the approved rules say; the official decision stays with the match "
        "officials named in each rule.",
    )]  # fmt: skip
    if not rules.approved:
        limitations.append(Note("RULES_NOT_APPROVED", "The rule set is still a draft."))
    if heat.value is not None and not math.isfinite(heat.value):
        heat.value, heat.level, heat.status = None, None, "unavailable"
    return Assessment(
        rule_version=rule_version(rules),
        rules_approved=rules.approved,
        age_group=age_group,
        indicators=[
            heat,
            assess_lightning(rules, lightning, thunderstorm_alert),
            assess_rainfall(rules),
        ],  # fmt: skip
        limitations=limitations,
    )
