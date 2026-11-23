"""Live lightning checks for a venue (DEC-06). Shared by all users, on demand.

At most one Xweather call per venue per interval (default 5 minutes, matching the data's 5-minute
window), under the lock scope ``xweather_lightning:<venue>``; failed attempts count too.
Lightning detection is shown as measured data; it never becomes a Pitchy "stop play" decision.
"""

import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from services.weather_ingestion.jobs.runner import DEFAULT_LEASE
from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import SourceError
from services.weather_ingestion.sources.xweather.lightning import (
    LightningReading,
    XweatherLightning,
)
from shared.db.records import LightningCheckRecord, Location
from shared.db.repositories import IngestionJobRepository, PgLightningRepository
from shared.settings import Settings

logger = logging.getLogger("pitchy.ingestion")
SOURCE_ID = "xweather_lightning"

LightningFetcher = Callable[[float, float, float], LightningReading]  # lat, lon, radius_km


def lightning_scope(venue_scope_key: str) -> str:
    return f"xweather_lightning:{venue_scope_key}"


def xweather_fetcher(settings: Settings) -> LightningFetcher:
    def fetch(latitude: float, longitude: float, radius_km: float) -> LightningReading:
        cid, secret = settings.xweather_client_id, settings.xweather_client_secret
        adapter = XweatherLightning(
            AllowlistedClient(settings.http_user_agent),
            cid.get_secret_value() if cid else None,
            secret.get_secret_value() if secret else None,
        )
        try:
            return adapter.fetch(latitude, longitude, radius_km)
        finally:
            adapter.close()

    return fetch


@dataclass(frozen=True)
class LightningRefresh:
    status: str  # refreshed | failed | skipped_recent | in_progress
    error_code: str | None = None


def refresh_lightning(
    fetch: LightningFetcher,
    location: Location,
    jobs: IngestionJobRepository,
    repo: PgLightningRepository,
    interval: timedelta,
    radius_km: float,
    *,
    lease: timedelta = DEFAULT_LEASE,
    now: Callable[[], datetime] = lambda: datetime.now(UTC),
) -> LightningRefresh:
    def recent() -> bool:
        last = repo.last_check(location.id)
        return last is not None and now() - last.checked_at < interval

    if recent():
        return LightningRefresh("skipped_recent")
    lock = jobs.acquire(lightning_scope(location.scope_key), SOURCE_ID, location.id, lease)
    if not lock.acquired:
        return LightningRefresh("in_progress")
    job_id = lock.job.id
    if recent():
        jobs.finish(job_id, succeeded=False, failure_code="SKIPPED_RECENT",
                    failure_message="Lightning was checked moments ago.")  # fmt: skip
        return LightningRefresh("skipped_recent")
    try:
        reading = fetch(location.latitude, location.longitude, radius_km)
    except SourceError as error:
        repo.record_failed_check(location.id, job_id, error.code, error.message)
        jobs.finish(job_id, succeeded=False, failure_code=error.code,
                    failure_message=error.message)  # fmt: skip
        logger.warning("Lightning check failed for %s: %s", location.scope_key, error.code)
        return LightningRefresh("failed", error.code)
    except Exception:
        logger.exception("Lightning check crashed for %s", location.scope_key)
        repo.record_failed_check(location.id, job_id, "INTERNAL_ERROR", "Unexpected error.")
        jobs.finish(job_id, succeeded=False, failure_code="INTERNAL_ERROR",
                    failure_message="Unexpected error.")  # fmt: skip
        return LightningRefresh("failed", "INTERNAL_ERROR")
    repo.record_check(location.id, job_id, reading)
    jobs.finish(job_id, succeeded=True)
    return LightningRefresh("refreshed")


@dataclass(frozen=True)
class LightningState:
    state: str  # current | stale | missing | updating | unavailable
    reading: LightningCheckRecord | None  # last successful check
    current_until: datetime | None
    last_error_code: str | None


def lightning_state(
    location: Location,
    repo: PgLightningRepository,
    jobs: IngestionJobRepository,
    interval: timedelta,
    now: datetime,
) -> LightningState:
    last, success = repo.last_check(location.id), repo.last_successful_check(location.id)
    error = last.error_code if last is not None and last.status == "failed" else None
    until = success.checked_at + interval if success is not None else None
    if jobs.active_for_scopes([lightning_scope(location.scope_key)]):
        state = "updating"
    elif success is not None:
        state = "current" if now < until else "stale"
    else:
        state = "unavailable" if last is not None else "missing"
    return LightningState(state, success, until, error)
