"""PAGASA official alerts (CAP) and cyclone track (FR-SAF-007). See README.md in this folder.

Alerts are shown as official information with issuer and times; they are never turned into a
system classification. Alert text is untrusted (one observed headline contained a ``<script>``
tag), so everything is reduced to plain text here and must never be rendered as HTML.
"""

import html
import re
from dataclasses import dataclass
from datetime import UTC, datetime

from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import SourceResponseChangedError, require
from services.weather_ingestion.sources.pagasa.forecast import PHT
from services.weather_ingestion.sources.pagasa.session import PagasaSession

CAP_ALERTS_URL = "https://www.panahon.gov.ph/api/v1/cap-alerts"
CYCLONE_TRACK_URL = "https://www.panahon.gov.ph/api/v1/cyclone-track"
IGNORED_EVENTS = {"NOTE"}  # site-wide notices; the site itself skips them
_TAG = re.compile(r"<[^>]*>")
_SPACE = re.compile(r"\s+")


def plain_text(raw: object, limit: int = 2000) -> str:
    """Strip tags/scripts, decode entities, collapse whitespace."""
    text = re.sub(r"<script\b.*?</script>", " ", str(raw or ""), flags=re.I | re.S)
    text = html.unescape(_TAG.sub(" ", text))
    return _SPACE.sub(" ", text).strip()[:limit]


def normalize_code(raw: object) -> str:
    """PSGC codes as 9 digits. PAGASA sometimes drops the leading zero ('97219000')."""
    digits = str(raw or "").strip()
    return digits.zfill(9) if digits.isdigit() and len(digits) <= 9 else ""


@dataclass(frozen=True)
class AlertArea:
    """An affected area: a municipality (``psgc_code``) or a whole province (``geocode``)."""

    municipality: str
    province: str
    code: str  # normalized 9-digit PSGC code, "" if missing
    level: str  # "municipality" | "province"
    relation: str  # PAGASA's own "type": affecting | expecting | watch | ...


@dataclass(frozen=True)
class OfficialAlert:
    identifier: str
    event: str
    subtype: str
    headline: str
    message: str
    issuer: str
    issued_at: datetime | None
    valid_until: datetime | None
    areas: tuple[AlertArea, ...]

    def matching_areas(self, venue_codes: set[str]) -> list[AlertArea]:
        """Areas covering a venue, given its municipality and province codes."""
        codes = {normalize_code(c) for c in venue_codes} - {""}
        return [a for a in self.areas if a.code in codes]

    def covers(self, venue_codes: set[str]) -> bool:
        return bool(self.matching_areas(venue_codes))


def _time(raw: object) -> datetime | None:
    if not raw:
        return None
    try:
        local = datetime.strptime(str(raw), "%Y-%m-%d %H:%M:%S").replace(tzinfo=PHT)
    except ValueError:
        raise SourceResponseChangedError(f"Unparseable alert time {raw!r}") from None
    return local.astimezone(UTC)


def parse_alerts(payload: dict) -> list[OfficialAlert]:
    require(isinstance(payload, dict) and payload.get("success") is True, "cap-alerts failed")
    data = payload.get("data")
    items = data.get("alert_data") if isinstance(data, dict) else None
    require(isinstance(items, list), "cap-alerts has no alert_data list")
    alerts = []
    for item in items:
        require(isinstance(item, dict) and "event" in item, "cap-alerts item changed")
        if item["event"] in IGNORED_EVENTS:
            continue
        # Shapes are not used: observed coordinates mix lat/lon order and projections.
        areas = tuple(
            AlertArea(
                municipality=plain_text(p.get("municipality"), 200),
                province=plain_text(p.get("province"), 200),
                code=normalize_code(p.get("psgc_code") or p.get("geocode")),
                level="municipality" if p.get("psgc_code") else "province",
                relation=plain_text(p.get("type"), 50),
            )
            for p in item.get("provinces") or []
            if isinstance(p, dict)
        )
        alerts.append(
            OfficialAlert(
                identifier=plain_text(item.get("identifier"), 200),
                event=plain_text(item.get("event"), 100),
                subtype=plain_text(item.get("subtype"), 100),
                headline=plain_text(item.get("headline"), 300),
                message=plain_text(item.get("message")),
                issuer=plain_text(item.get("published_by"), 100),
                issued_at=_time(item.get("issued_date")),
                valid_until=_time(item.get("valid_date")),
                areas=areas,
            )
        )
    return alerts


def parse_cyclone_track(payload: object) -> int:
    """Number of active tropical cyclone tracks. Only "none active" (``[]``) has been seen so
    far; the structure of an active track is captured at the first real cyclone."""
    require(isinstance(payload, list | dict), "cyclone-track response changed")
    return len(payload)


def fetch_alerts(client: AllowlistedClient, session: PagasaSession) -> list[OfficialAlert]:
    try:
        payload = client.get(CAP_ALERTS_URL, params={"token": session.token}).json()
    except ValueError:
        raise SourceResponseChangedError("cap-alerts did not return JSON") from None
    return parse_alerts(payload)


def fetch_active_cyclones(client: AllowlistedClient, session: PagasaSession) -> int:
    try:
        payload = client.get(CYCLONE_TRACK_URL, params={"token": session.token}).json()
    except ValueError:
        raise SourceResponseChangedError("cyclone-track did not return JSON") from None
    return parse_cyclone_track(payload)
