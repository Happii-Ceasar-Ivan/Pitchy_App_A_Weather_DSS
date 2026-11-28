"""OpenWeather One Call API 3.0 adapter (P-30). See README.md in this folder.

One request per venue: 48 hourly steps, metric units. The API key travels as the ``appid`` query
parameter, so the request URL is a secret: it is never logged, stored or put in an error.
Display and citation only; no safety rule reads this source (P-30 Q4, user decision 2026-11-28).
"""

import json
from datetime import UTC, datetime, timedelta

from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import (
    SourceFetch,
    SourceUnavailableError,
    Venue,
    require,
)
from shared.db.records import NewForecastValue

SOURCE_ID = "openweather"
BASE_URL = "https://api.openweathermap.org/data/3.0/onecall"
STEP = timedelta(hours=1)
MAX_GRID_OFFSET_DEG = 0.1  # the response echoes the point; anything farther is not our venue

# Stored code -> (field in each hourly item, unit with units=metric, scale, required).
# Units are from the One Call 3.0 docs (read 2026-11-28); the API reports no units itself, so
# `units=metric` in the request is what fixes them. Fields marked "(where available)" in the docs
# are optional: when absent they are stored as `missing`, never as zero.
FIELDS: dict[str, tuple[tuple[str, ...], str, float, bool]] = {
    "temp": (("temp",), "°C", 1, True),
    "humidity": (("humidity",), "%", 1, True),
    "dew_point": (("dew_point",), "°C", 1, True),
    "pressure_msl": (("pressure",), "hPa", 1, True),  # docs: "on the sea level"
    "clouds": (("clouds",), "%", 1, True),
    "uvi": (("uvi",), "UV index", 1, True),
    "wind_speed": (("wind_speed",), "m/s", 1, True),
    "wind_gust": (("wind_gust",), "m/s", 1, False),  # "(where available)"
    "wind_deg": (("wind_deg",), "°", 1, True),
    "pop": (("pop",), "%", 100, True),  # docs: 0..1; stored as percent
    "rain_1h": (("rain", "1h"), "mm/h", 1, False),  # "(where available)", docs unit mm/h
}


def request_params(venue: Venue, api_key: str) -> dict[str, str]:
    return {
        "lat": repr(venue.latitude),
        "lon": repr(venue.longitude),
        "units": "metric",
        "exclude": "current,minutely,daily,alerts",
        "appid": api_key,
    }


def _number(value: object) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool)


def _lookup(item: dict, path: tuple[str, ...]) -> tuple[bool, object]:
    """(present, value) for a nested field such as ``rain.1h``."""
    node: object = item
    for key in path:
        if not isinstance(node, dict) or key not in node:
            return False, None
        node = node[key]
    return True, node


def parse(payload: dict, venue: Venue) -> SourceFetch:
    """Turn one venue's One Call JSON object into normalized hourly values (UTC)."""
    require(isinstance(payload, dict), "OpenWeather response is not an object")
    lat, lon = payload.get("lat"), payload.get("lon")
    require(_number(lat) and _number(lon), "OpenWeather response has no point")
    require(
        abs(lat - venue.latitude) <= MAX_GRID_OFFSET_DEG
        and abs(lon - venue.longitude) <= MAX_GRID_OFFSET_DEG,
        "OpenWeather answered for a different point",
    )
    hourly = payload.get("hourly")
    require(isinstance(hourly, list) and len(hourly) > 0, "Missing hourly data")

    values: list[NewForecastValue] = []
    previous: datetime | None = None
    for item in hourly:
        require(isinstance(item, dict), "Hourly item is not an object")
        dt = item.get("dt")
        require(isinstance(dt, int) and not isinstance(dt, bool), f"Unparseable time {dt!r}")
        start = datetime.fromtimestamp(dt, UTC)  # docs: "Unix, UTC"
        require(start.minute == 0 and start.second == 0, f"Time {start} is not on the hour")
        require(previous is None or start - previous == STEP, "Hourly steps are not 1 hour apart")
        previous = start
        for code, (path, unit, scale, required) in FIELDS.items():
            present, raw = _lookup(item, path)
            require(present or not required, f"Missing field {'.'.join(path)}")
            ok = present and _number(raw)
            values.append(
                NewForecastValue(
                    parameter=code,
                    value=float(raw) * scale if ok else None,
                    unit=unit,
                    value_state="ok" if ok else "missing",
                    forecast_valid_from=start,
                    forecast_valid_until=start + STEP,
                    expires_at=None,
                )
            )

    notes = [
        f"OpenWeather point {lat}, {lon} for venue at {venue.latitude}, {venue.longitude}.",
        "Heights for temperature and wind are not stated by OpenWeather; pressure is sea level.",
    ]
    return SourceFetch(
        source_id=SOURCE_ID,
        venue=venue,
        values=values,
        raw_payload=json.dumps(payload, ensure_ascii=False),
        notes=notes,
    )


class OpenWeatherAdapter:
    source_ids = (SOURCE_ID,)

    def __init__(self, client: AllowlistedClient, api_key: str | None) -> None:
        self._client, self._key = client, api_key

    def fetch(self, venue: Venue) -> list[SourceFetch]:
        if not self._key:
            raise SourceUnavailableError("The OpenWeather key is not configured.", "NOT_CONFIGURED")
        # HTTP 401 (key) and 429 (daily cap) come back as HTTP_401 / HTTP_429 from the client;
        # the runner treats them as blocking (no retry before the group's minimum gap).
        response = self._client.get(BASE_URL, params=request_params(venue, self._key))
        try:
            payload = response.json()
        except ValueError:
            require(False, "OpenWeather did not return JSON")
        return [parse(payload, venue)]

    def close(self) -> None:
        self._client.close()
