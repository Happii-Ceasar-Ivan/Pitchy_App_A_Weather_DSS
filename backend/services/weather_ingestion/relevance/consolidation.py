"""Consolidated weather view (P-09, option B). Pure functions; no averaging across sources.

For each quantity and hour slot:
- the chosen value comes from the highest-priority source whose data is **current**; if none
  is current, the highest-priority **stale** value is shown, marked stale (never as current);
- a substitution is labelled (e.g. "PAGASA ECMWF used; PAGASA ATMO stale");
- for comparable quantities, the range and count across current sources is shown. No
  agree/disagree label until the team sets tolerances;
- every source's own value is kept in ``by_source`` (FR-CLI-004).

Getting one hourly value from one source (a conversion within that source, never a blend):
- ``instant``: the value valid at the start of the hour;
- ``rate`` (e.g. mm/h): the time-weighted mean over the hour, only if the hour is fully covered;
- ``amount`` (e.g. mm): only a value whose window is exactly that hour (mm in 1 h = mm/h).
  PAGASA ECMWF's 3 h / 6 h rain steps are therefore not used until their meaning is confirmed.
Stored units must match exactly; nothing is converted silently.
"""

from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Literal

from services.weather_ingestion.relevance.freshness import covers

Kind = Literal["instant", "rate", "amount"]
HOUR = timedelta(hours=1)
HEIGHT_NOT_STATED = "Height not stated."


@dataclass(frozen=True)
class SourceParam:
    source_id: str
    parameter: str
    unit: str  # the unit stored for this parameter; anything else is not used
    kind: Kind = "instant"
    in_range: bool = True
    note: str | None = None


@dataclass(frozen=True)
class QuantitySpec:
    key: str
    label: str
    unit: str
    sources: tuple[SourceParam, ...]  # priority order (first available wins)
    circular: bool = False  # directions: the range is the smallest arc


def _om(parameter: str, unit: str, kind: Kind = "instant") -> SourceParam:
    return SourceParam("open_meteo", parameter, unit, kind)


def _ow(parameter: str, unit: str, kind: Kind = "instant", **kw) -> SourceParam:
    return SourceParam("openweather", parameter, unit, kind, **kw)


# OpenWeather's docs don't say which part of the hour `pop` and `rain.1h` describe, so those two
# are shown per source but kept out of the range until confirmed (no guessing).
OW_WINDOW_NOT_STATED = "Time window not stated by OpenWeather; kept out of the range."

# P-09 priority table (team decision 2026-11-22). OpenWeather (P-30, 2026-11-28) is added last:
# lowest priority, so it is chosen only when no other source has a value.
QUANTITIES: tuple[QuantitySpec, ...] = (
    QuantitySpec("air_temperature", "Air temperature", "°C", (
        _om("temperature_2m", "°C"),
        _ow("temp", "°C", note=HEIGHT_NOT_STATED),
    )),
    QuantitySpec("relative_humidity", "Relative humidity", "%", (
        _om("relative_humidity_2m", "%"),
        _ow("humidity", "%", note=HEIGHT_NOT_STATED),
    )),
    QuantitySpec("dew_point", "Dew point", "°C", (
        _om("dew_point_2m", "°C"),
        _ow("dew_point", "°C", note=HEIGHT_NOT_STATED),
    )),
    QuantitySpec("shortwave_radiation", "Solar radiation (GHI)", "W/m²",
                 (_om("shortwave_radiation", "W/m²", "rate"),)),
    QuantitySpec("direct_normal_irradiance", "Direct normal irradiance", "W/m²",
                 (_om("direct_normal_irradiance", "W/m²", "rate"),)),
    QuantitySpec("diffuse_radiation", "Diffuse radiation", "W/m²",
                 (_om("diffuse_radiation", "W/m²", "rate"),)),
    QuantitySpec("heat_index", "Heat index (PAGASA)", "°C", (
        SourceParam("pagasa_atmo", "heat_index", "°C"),
        SourceParam("pagasa_ecmwf", "heat_index", "°C"),
    )),
    QuantitySpec("rain", "Rain", "mm/h", (
        SourceParam("pagasa_atmo", "accumulated_rain_1h", "mm/h", "rate"),
        SourceParam("pagasa_ecmwf", "accumulated_rain_1h", "mm", "amount", in_range=False,
                    note="ECMWF rain step meaning still to confirm; only 1-hour steps used."),
        _om("precipitation", "mm", "amount"),
        _ow("rain_1h", "mm/h", "rate", in_range=False, note=OW_WINDOW_NOT_STATED),
    )),
    QuantitySpec("wind_speed", "Wind speed", "m/s", (
        _om("wind_speed_10m", "m/s"),
        SourceParam("pagasa_atmo", "wind_speed", "m/s", note=HEIGHT_NOT_STATED),
        SourceParam("pagasa_ecmwf", "wind_speed", "m/s", note=HEIGHT_NOT_STATED),
        _ow("wind_speed", "m/s", note=HEIGHT_NOT_STATED),
    )),
    QuantitySpec("wind_direction", "Wind direction", "°", (
        _om("wind_direction_10m", "°"),
        SourceParam("pagasa_atmo", "wind_direction", "°", note=HEIGHT_NOT_STATED),
        SourceParam("pagasa_ecmwf", "wind_direction", "°", note=HEIGHT_NOT_STATED),
        _ow("wind_deg", "°", note=HEIGHT_NOT_STATED),
    ), circular=True),
    QuantitySpec("rain_probability", "Rain probability", "%", (
        _om("precipitation_probability", "%"),
        _ow("pop", "%", in_range=False, note=OW_WINDOW_NOT_STATED),
    )),
    QuantitySpec("cloud_cover", "Cloud cover", "%", (
        _om("cloud_cover", "%"),
        _ow("clouds", "%"),
    )),
    QuantitySpec("cape", "CAPE", "J/kg", (_om("cape", "J/kg"),)),
    QuantitySpec("wind_gusts", "Wind gusts", "m/s", (
        _om("wind_gusts_10m", "m/s"),
        _ow("wind_gust", "m/s", note=HEIGHT_NOT_STATED),
    )),
)  # fmt: skip


@dataclass(frozen=True)
class StoredValue:
    parameter: str
    value: float | None
    unit: str | None
    value_state: str
    valid_from: datetime
    valid_until: datetime


@dataclass(frozen=True)
class SourceData:
    """One source's usable fetch for the venue and whether it is current right now."""

    source_id: str
    name: str
    state: str  # "current" | "stale" (sources with no usable fetch are left out)
    values: Sequence[StoredValue]


@dataclass(frozen=True)
class SourceValue:
    source_id: str
    value: float
    state: str
    note: str | None


@dataclass(frozen=True)
class ValueRange:
    min: float
    max: float
    count: int
    source_ids: tuple[str, ...]


@dataclass
class Slot:
    valid_from: datetime
    valid_until: datetime
    value: float | None = None
    source_id: str | None = None
    state: str | None = None
    label: str | None = None
    notes: list[str] = field(default_factory=list)
    range: ValueRange | None = None
    by_source: list[SourceValue] = field(default_factory=list)


@dataclass
class QuantityView:
    spec: QuantitySpec
    slots: list[Slot]


def hourly_value(rows: Iterable[StoredValue], param: SourceParam, start: datetime):
    """One source's value for the hour starting at ``start``, or None."""
    end = start + HOUR
    rows = [r for r in rows if r.valid_until > start and r.valid_from < end]
    if any(r.unit != param.unit for r in rows):
        return None
    if param.kind == "instant":
        row = next((r for r in rows if r.valid_from <= start < r.valid_until), None)
        return row.value if row is not None and row.value_state == "ok" else None
    if param.kind == "amount":
        row = next((r for r in rows if r.valid_from == start and r.valid_until == end), None)
        return row.value if row is not None and row.value_state == "ok" else None
    # rate: time-weighted mean over the hour, every part covered by an ok value
    if not rows or any(r.value_state != "ok" for r in rows):
        return None
    if not covers([(r.valid_from, r.valid_until) for r in rows], start, end):
        return None
    total = sum(
        r.value * (min(r.valid_until, end) - max(r.valid_from, start)).total_seconds() for r in rows
    )
    return total / HOUR.total_seconds()


def _arc(angles: Sequence[float]) -> tuple[float, float]:
    """Smallest arc containing all directions, as (from, to) clockwise in degrees."""
    a = sorted(x % 360 for x in angles)
    gaps = [((a[(i + 1) % len(a)] - a[i]) % 360 or (360 if len(a) == 1 else 0), i)
            for i in range(len(a))]  # fmt: skip
    _, i = max(gaps)
    return a[(i + 1) % len(a)], a[i]


def consolidate(
    sources: dict[str, SourceData], start: datetime, end: datetime
) -> list[QuantityView]:
    by_param = {
        (sid, p): [v for v in data.values if v.parameter == p]
        for sid, data in sources.items()
        for p in {v.parameter for v in data.values}
    }
    hours = []
    t = start
    while t < end:
        hours.append(t)
        t += HOUR
    views = []
    for spec in QUANTITIES:
        slots = []
        for hour in hours:
            slot = Slot(hour, hour + HOUR)
            for param in spec.sources:
                data = sources.get(param.source_id)
                if data is None:
                    continue
                value = hourly_value(by_param.get((param.source_id, param.parameter), []),
                                     param, hour)  # fmt: skip
                if value is not None:
                    slot.by_source.append(SourceValue(param.source_id, value, data.state,
                                                      param.note))  # fmt: skip
            _choose(spec, slot, sources)
            slots.append(slot)
        views.append(QuantityView(spec, slots))
    return views


def _choose(spec: QuantitySpec, slot: Slot, sources: dict[str, SourceData]) -> None:
    params = {p.source_id: p for p in spec.sources}
    found = {v.source_id: v for v in slot.by_source}
    chosen = next(
        (
            found[p.source_id]
            for p in spec.sources
            if p.source_id in found and found[p.source_id].state == "current"
        ),
        None,
    )
    chosen = chosen or next((found[p.source_id] for p in spec.sources if p.source_id in found),
                            None)  # fmt: skip
    if chosen is None:
        return
    slot.value, slot.source_id, slot.state = chosen.value, chosen.source_id, chosen.state
    if chosen.note:
        slot.notes.append(chosen.note)
    skipped = []
    for p in spec.sources:
        if p.source_id == chosen.source_id:
            break
        data = sources.get(p.source_id)
        reason = "stale" if p.source_id in found else (
            "no value for this hour" if data is not None else "unavailable"
        )  # fmt: skip
        name = data.name if data is not None else p.source_id
        skipped.append(f"{name} {reason}")
    if skipped:
        used = sources[chosen.source_id].name
        slot.label = f"{spec.label}: {used}; " + ", ".join(skipped)
    comparable = [v for v in slot.by_source
                  if v.state == "current" and params[v.source_id].in_range]  # fmt: skip
    if len(comparable) >= 2:
        values = [v.value for v in comparable]
        low, high = _arc(values) if spec.circular else (min(values), max(values))
        slot.range = ValueRange(low, high, len(comparable),
                                tuple(v.source_id for v in comparable))  # fmt: skip
