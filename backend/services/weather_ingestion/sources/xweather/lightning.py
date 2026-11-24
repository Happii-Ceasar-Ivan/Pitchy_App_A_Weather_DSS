"""Vaisala Xweather lightning/flash adapter (DEC-06, 2026-11-23). See README.md in this folder.

Live detection of the past 5 minutes around a venue, not a forecast. Keys are sent as query
parameters, so request URLs must never be logged (the allowlisted client never does). The
response gives each flash's time and position; Pitchy computes the distance itself.
"""

import hashlib
import json
import math
import re
from dataclasses import dataclass, field
from datetime import UTC, datetime

from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import (
    SourceResponseChangedError,
    SourceUnavailableError,
    require,
)

FLASH_CLOSEST_URL = "https://data.api.xweather.com/lightning/flash/closest"
MAX_RADIUS_KM = 40.0  # Xweather's limit for lightning/flash
MAX_FLASHES = 1000  # per query
NO_DATA = "warn_no_data"  # valid request, nothing detected
ATTRIBUTION = {"text": "Powered by Vaisala Xweather", "url": "https://www.xweather.com/"}
EARTH_RADIUS_KM = 6371.0088
_SAFE_CODE = re.compile(r"[^A-Za-z0-9_]")


@dataclass(frozen=True)
class Flash:
    detected_at: datetime
    latitude: float
    longitude: float
    distance_km: float


@dataclass(frozen=True)
class LightningReading:
    radius_km: float
    flashes: list[Flash]
    raw_payload: str
    notes: list[str] = field(default_factory=list)

    @property
    def nearest_km(self) -> float | None:
        return min((f.distance_km for f in self.flashes), default=None)

    @property
    def latest_at(self) -> datetime | None:
        return max((f.detected_at for f in self.flashes), default=None)

    @property
    def raw_payload_sha256(self) -> str:
        return hashlib.sha256(self.raw_payload.encode("utf-8")).hexdigest()


def distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance (haversine)."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def parse(text: str, latitude: float, longitude: float, radius_km: float) -> LightningReading:
    try:
        payload = json.loads(text)
    except ValueError:
        raise SourceResponseChangedError("Xweather did not return JSON") from None
    require(isinstance(payload, dict) and "success" in payload, "Xweather response changed")
    error = payload.get("error")
    if not payload["success"]:
        code = str((error or {}).get("code") or "error")[:40]
        raise SourceUnavailableError(
            "Xweather refused the request.", "XWEATHER_" + _SAFE_CODE.sub("_", code).upper()
        )
    items = payload.get("response")
    require(isinstance(items, list), "Xweather response has no list")
    if error and error.get("code") != NO_DATA:
        require(not items, "Xweather warning with data")  # unknown warning: never guess
    flashes = []
    for item in items:
        require(isinstance(item, dict), "Xweather flash item changed")
        loc, ob = item.get("loc") or {}, item.get("ob") or {}
        lat, lon, ts = loc.get("lat"), loc.get("long"), ob.get("timestamp")
        require(all(isinstance(v, int | float) and not isinstance(v, bool)
                    for v in (lat, lon, ts)), "Xweather flash fields changed")  # fmt: skip
        flashes.append(
            Flash(
                detected_at=datetime.fromtimestamp(ts, UTC),
                latitude=float(lat),
                longitude=float(lon),
                distance_km=round(distance_km(latitude, longitude, lat, lon), 2),
            )
        )
    flashes.sort(key=lambda f: f.distance_km)
    notes = [] if len(items) < MAX_FLASHES else ["Result capped at 1000 flashes."]
    return LightningReading(radius_km, flashes, text, notes)


class XweatherLightning:
    """Fetch flashes within ``radius_km`` of a point. Raises ``SourceError`` on failure."""

    def __init__(self, client: AllowlistedClient, client_id: str | None, secret: str | None):
        self._client, self._id, self._secret = client, client_id, secret

    def fetch(self, latitude: float, longitude: float, radius_km: float) -> LightningReading:
        if not self._id or not self._secret:
            raise SourceUnavailableError("Xweather keys are not configured.", "NOT_CONFIGURED")
        radius = min(radius_km, MAX_RADIUS_KM)
        params = {
            "p": f"{latitude},{longitude}",
            "radius": f"{radius:g}km",
            "limit": str(MAX_FLASHES),
            "client_id": self._id,
            "client_secret": self._secret,
        }
        response = self._client.get(FLASH_CLOSEST_URL, params=params)
        return parse(response.text, latitude, longitude, radius)

    def close(self) -> None:
        self._client.close()
