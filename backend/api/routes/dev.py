"""Development-only routes to see ingestion working from the interactive API docs.

Mounted only when PITCHY_ENV=development and PITCHY_ENABLE_DEV_ROUTES=true, and every request
must come from this computer (127.0.0.1 / ::1). Not part of the published API contract.
These read and write the real database through the least-privilege login.
"""

import threading
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Query, Request

from api.errors import ApiError
from api.schemas.common import ErrorCode
from services.weather_ingestion import registry
from services.weather_ingestion.jobs.runner import run_ingestion
from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import SourceError
from services.weather_ingestion.sources.pagasa.alerts import fetch_active_cyclones, fetch_alerts
from services.weather_ingestion.sources.pagasa.session import open_session
from shared.db.pool import DatabaseNotConfiguredError, create_pool
from shared.db.repositories import (
    PgForecastRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
    PgWeatherSourceRepository,
)
from shared.settings import get_settings

LOCAL_HOSTS = {"127.0.0.1", "::1", "localhost", "testclient"}
ALERT_MIN_INTERVAL = timedelta(hours=1)  # DEC-02: alerts at most hourly


def local_only(request: Request) -> None:
    if request.client is None or request.client.host not in LOCAL_HOSTS:
        raise ApiError(404, ErrorCode.NOT_FOUND, "Not Found")


router = APIRouter(prefix="/dev", tags=["dev (local only)"], dependencies=[Depends(local_only)])


_pool = None
_pool_lock = threading.Lock()


def _connect():
    """A pooled connection (reused across requests) via the least-privilege login."""
    global _pool
    with _pool_lock:
        if _pool is None:
            try:
                _pool = create_pool(get_settings(), max_size=4)
            except DatabaseNotConfiguredError as exc:
                raise ApiError(503, ErrorCode.INTERNAL_ERROR, str(exc)) from None
            _pool.open(wait=True, timeout=30)
    return _pool.connection()


def _venue(scope_key: str):
    for loc in PgLocationRepository(_connect).list_all():
        if loc.scope_key == scope_key:
            return loc
    raise ApiError(404, ErrorCode.NOT_FOUND, f"Unknown venue {scope_key!r}.")


@router.get("/venues", summary="1. List the venues")
def venues() -> list[dict]:
    return [
        {"scope_key": v.scope_key, "name": v.name, "latitude": v.latitude,
         "longitude": v.longitude, "psgc_code": v.psgc_code,
         "province_psgc_code": v.province_psgc_code}
        for v in PgLocationRepository(_connect).list_all()
    ]  # fmt: skip


@router.post("/ingest", summary="2. Run ingestion now (manual trigger)")
def ingest() -> dict:
    """Same path as the 6-hour schedule: shared lock, PAGASA 4-hour rule, provenance stored.
    Running it again within 4 hours shows PAGASA as `skipped_recent` on purpose."""
    settings = get_settings()
    report = run_ingestion(
        registry.adapter_groups(settings),
        [registry.venue_from_location(v) for v in PgLocationRepository(_connect).list_all()],
        {s.id for s in PgWeatherSourceRepository(_connect).list_enabled()},
        PgIngestionJobRepository(_connect),
        PgForecastRepository(_connect),
        trigger="manual",
    )
    return {
        "trigger": report.trigger,
        "started_at": report.started_at,
        "finished_at": report.finished_at,
        "results": [r.__dict__ for r in report.results],
    }


@router.get("/fetches", summary="3. See the latest source calls (provenance)")
def fetches(limit: int = Query(20, ge=1, le=100)) -> list[dict]:
    return PgForecastRepository(_connect).recent_fetches(limit)


@router.get("/venues/{scope_key}/forecast", summary="4. See stored forecast values")
def forecast(
    scope_key: str,
    source: str = Query("open_meteo", pattern="^(open_meteo|pagasa_atmo|pagasa_ecmwf)$"),
    hours: int = Query(6, ge=1, le=48),
) -> dict:
    """Values from the latest successful fetch of `source`, for the next `hours` hours.
    Times are UTC (Philippine Time = UTC+8)."""
    venue = _venue(scope_key)
    now = datetime.now(UTC).replace(minute=0, second=0, microsecond=0)
    rows = PgForecastRepository(_connect).values_between(
        venue.id, now, now + timedelta(hours=hours), source
    )
    by_parameter: dict[str, dict] = {}
    for r in rows:
        entry = by_parameter.setdefault(r.parameter, {"unit": r.unit, "values": []})
        entry["values"].append({"from": r.forecast_valid_from, "until": r.forecast_valid_until,
                                "value": r.value, "state": r.value_state})  # fmt: skip
    return {
        "venue": venue.name,
        "source": source,
        "retrieved_at": rows[0].retrieved_at if rows else None,
        "note": None if rows else "No stored data for this window: run 2. ingest first.",
        "parameters": by_parameter,
    }


_alert_cache: dict = {"checked_at": None, "alerts": [], "cyclones": None, "error": None}
_alert_lock = threading.Lock()


@router.get("/venues/{scope_key}/alerts", summary="5. Official PAGASA alerts for a venue")
def alerts(scope_key: str) -> dict:
    """Refreshes from PAGASA only if the last check was over an hour ago (the "on open" rule);
    otherwise answers from the last check. Alerts are official information, shown as issued."""
    venue = _venue(scope_key)
    codes = {c for c in (venue.psgc_code, venue.province_psgc_code) if c}
    with _alert_lock:
        last = _alert_cache["checked_at"]
        if last is None or datetime.now(UTC) - last >= ALERT_MIN_INTERVAL:
            try:
                with AllowlistedClient(get_settings().http_user_agent) as client:
                    session = open_session(client)
                    _alert_cache.update(
                        alerts=fetch_alerts(client, session),
                        cyclones=fetch_active_cyclones(client, session),
                        error=None,
                    )
            except SourceError as exc:
                _alert_cache["error"] = {"code": exc.code, "message": exc.message}
            _alert_cache["checked_at"] = datetime.now(UTC)
        cache = dict(_alert_cache)
    matching = [a for a in cache["alerts"] if a.covers(codes)]
    return {
        "venue": venue.name,
        "last_checked_at": cache["checked_at"],
        "refresh_error": cache["error"],
        "active_tropical_cyclones": cache["cyclones"],
        "alerts_nationwide": len(cache["alerts"]),
        "alerts_for_this_venue": [
            {
                "issuer": a.issuer,
                "event": a.event,
                "subtype": a.subtype,
                "headline": a.headline,
                "issued_at": a.issued_at,
                "valid_until": a.valid_until,
                "matched_areas": [
                    f"{m.municipality or m.province} ({m.level}, {m.relation})"
                    for m in a.matching_areas(codes)
                ],
                "message": a.message,
            }
            for a in matching
        ],  # fmt: skip
        "label": "Official PAGASA information, shown as issued. Not a Pitchy classification.",
    }
