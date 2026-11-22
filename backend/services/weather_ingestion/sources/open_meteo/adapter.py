"""Open-Meteo Forecast API adapter (DEC-01). See README.md in this folder.

One request per venue so each fetch row has exactly one venue's provenance.
"""

import json
from datetime import UTC, datetime, timedelta

from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import SourceFetch, Venue, require
from shared.db.records import NewForecastValue

SOURCE_ID = "open_meteo"
BASE_URL = "https://api.open-meteo.com/v1/forecast"

# Variable -> unit Open-Meteo must report. Any other unit means the response changed.
HOURLY_UNITS: dict[str, str] = {
    "temperature_2m": "°C",
    "relative_humidity_2m": "%",
    "dew_point_2m": "°C",
    "precipitation_probability": "%",
    "precipitation": "mm",
    "weather_code": "wmo code",
    "cloud_cover": "%",
    "wind_speed_10m": "m/s",
    "wind_gusts_10m": "m/s",
    "wind_direction_10m": "°",
    "wet_bulb_temperature_2m": "°C",
    "cape": "J/kg",
    "shortwave_radiation": "W/m²",
    "direct_normal_irradiance": "W/m²",
    "diffuse_radiation": "W/m²",
}
STEP = timedelta(hours=1)


def request_params(venue: Venue) -> dict[str, str]:
    return {
        "latitude": repr(venue.latitude),
        "longitude": repr(venue.longitude),
        "hourly": ",".join(HOURLY_UNITS),
        "wind_speed_unit": "ms",
        "timezone": "GMT",
        "timeformat": "iso8601",
    }


def parse(payload: dict, venue: Venue) -> SourceFetch:
    """Turn one venue's Open-Meteo JSON object into normalized hourly values (UTC)."""
    require(isinstance(payload, dict), "Open-Meteo response is not an object")
    require(payload.get("utc_offset_seconds") == 0, "Open-Meteo times are not UTC")
    units, hourly = payload.get("hourly_units"), payload.get("hourly")
    require(isinstance(units, dict) and isinstance(hourly, dict), "Missing hourly data")
    times = hourly.get("time")
    require(isinstance(times, list) and len(times) > 0, "Missing hourly time axis")
    require(units.get("time") == "iso8601", "Unexpected time format")

    starts = []
    for raw in times:
        try:
            starts.append(datetime.fromisoformat(raw).replace(tzinfo=UTC))
        except TypeError, ValueError:
            require(False, f"Unparseable time {raw!r}")

    values: list[NewForecastValue] = []
    for name, unit in HOURLY_UNITS.items():
        series = hourly.get(name)
        require(isinstance(series, list) and len(series) == len(starts), f"Missing series {name}")
        require(units.get(name) == unit, f"Unit for {name} changed to {units.get(name)!r}")
        for start, value in zip(starts, series, strict=True):
            ok = isinstance(value, int | float) and not isinstance(value, bool)
            values.append(
                NewForecastValue(
                    parameter=name,
                    value=float(value) if ok else None,
                    unit=unit,
                    value_state="ok" if ok else "missing",
                    forecast_valid_from=start,
                    forecast_valid_until=start + STEP,
                    expires_at=None,
                )
            )

    notes = [
        f"Open-Meteo grid point {payload.get('latitude')}, {payload.get('longitude')} "
        f"(elevation {payload.get('elevation')} m) for venue at "
        f"{venue.latitude}, {venue.longitude}."
    ]
    return SourceFetch(
        source_id=SOURCE_ID,
        venue=venue,
        values=values,
        raw_payload=json.dumps(payload, ensure_ascii=False),
        notes=notes,
    )


class OpenMeteoAdapter:
    source_ids = (SOURCE_ID,)

    def __init__(self, client: AllowlistedClient) -> None:
        self._client = client

    def fetch(self, venue: Venue) -> list[SourceFetch]:
        response = self._client.get(BASE_URL, params=request_params(venue))
        try:
            payload = response.json()
        except ValueError:
            require(False, "Open-Meteo did not return JSON")
        return [parse(payload, venue)]

    def close(self) -> None:
        self._client.close()
