"""Refresh PAGASA official alerts into the database (FR-SAF-007, DEC-02, DEC-04).

Called by every scheduled run and "on open" (when someone looks at a match's alerts). One
nationwide request at most once per interval (1 h), counting failed attempts too, under the lock
scope ``pagasa_alerts``. Alerts are stored as issued (plain text); they never become a Pitchy
classification.
"""

import logging
from collections.abc import Callable, Sequence
from dataclasses import asdict, dataclass
from datetime import UTC, datetime, timedelta

from services.weather_ingestion.jobs.runner import DEFAULT_LEASE
from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import SourceError
from services.weather_ingestion.sources.pagasa.alerts import (
    OfficialAlert,
    fetch_active_cyclones,
    fetch_alerts,
)
from services.weather_ingestion.sources.pagasa.session import open_session
from shared.db.records import Location
from shared.db.repositories import IngestionJobRepository, PgAlertRepository

logger = logging.getLogger("pitchy.ingestion")

ALERTS_SCOPE = "pagasa_alerts"
ALERTS_SOURCE_ID = "pagasa"

AlertFetcher = Callable[[], tuple[list[OfficialAlert], int]]  # (alerts, active cyclones)


def pagasa_alert_fetcher(user_agent: str) -> AlertFetcher:
    """The real fetcher: one PAGASA session, the alerts list and the cyclone track."""

    def fetch() -> tuple[list[OfficialAlert], int]:
        with AllowlistedClient(user_agent) as client:
            session = open_session(client)
            return fetch_alerts(client, session), fetch_active_cyclones(client, session)

    return fetch


@dataclass(frozen=True)
class AlertRefresh:
    status: str  # refreshed | failed | skipped_recent | in_progress
    error_code: str | None = None


def alert_row(alert: OfficialAlert, locations: Sequence[Location]) -> dict:
    return {
        "identifier": alert.identifier,
        "issuer": alert.issuer,
        "event": alert.event,
        "subtype": alert.subtype,
        "headline": alert.headline,
        "message": alert.message,
        "issued_at": alert.issued_at,
        "valid_until": alert.valid_until,
        "areas": [asdict(a) for a in alert.areas],
        "matched_venues": [v.scope_key for v in locations if alert.covers(v.alert_codes)],
    }


def refresh_alerts(
    fetch: AlertFetcher,
    locations: Sequence[Location],
    jobs: IngestionJobRepository,
    alerts: PgAlertRepository,
    min_interval: timedelta,
    *,
    lease: timedelta = DEFAULT_LEASE,
    now: Callable[[], datetime] = lambda: datetime.now(UTC),
) -> AlertRefresh:
    def recent() -> bool:
        last = alerts.last_check()
        return last is not None and now() - last.checked_at < min_interval

    if recent():
        return AlertRefresh("skipped_recent")
    lock = jobs.acquire(ALERTS_SCOPE, ALERTS_SOURCE_ID, None, lease)
    if not lock.acquired:
        return AlertRefresh("in_progress")
    job_id = lock.job.id
    if recent():  # another run finished between the first check and the lock
        jobs.finish(job_id, succeeded=False, failure_code="SKIPPED_RECENT",
                    failure_message="Alerts were checked less than an hour ago.")  # fmt: skip
        return AlertRefresh("skipped_recent")
    try:
        found, cyclones = fetch()
    except SourceError as error:
        alerts.record_failed_check(job_id, error.code, error.message)
        jobs.finish(job_id, succeeded=False, failure_code=error.code,
                    failure_message=error.message)  # fmt: skip
        logger.warning("PAGASA alerts failed: %s", error.code)
        return AlertRefresh("failed", error.code)
    except Exception:
        logger.exception("PAGASA alerts crashed")
        alerts.record_failed_check(job_id, "INTERNAL_ERROR", "Unexpected alerts error.")
        jobs.finish(job_id, succeeded=False, failure_code="INTERNAL_ERROR",
                    failure_message="Unexpected alerts error.")  # fmt: skip
        return AlertRefresh("failed", "INTERNAL_ERROR")
    alerts.record_check(job_id, [alert_row(a, locations) for a in found], cyclones)
    jobs.finish(job_id, succeeded=True)
    return AlertRefresh("refreshed")


@dataclass(frozen=True)
class AlertsState:
    state: str  # current | stale | missing | updating | unavailable
    last_success_at: datetime | None
    current_until: datetime | None
    last_error_code: str | None


def alerts_state(
    alerts: PgAlertRepository,
    jobs: IngestionJobRepository,
    min_interval: timedelta,
    now: datetime,
) -> AlertsState:
    last, success = alerts.last_check(), alerts.last_successful_check()
    error = last.error_code if last is not None and last.status == "failed" else None
    until = success.checked_at + min_interval if success is not None else None
    if jobs.active_for_scopes([ALERTS_SCOPE]):
        state = "updating"
    elif success is not None:
        state = "current" if now < until else "stale"
    else:
        state = "unavailable" if last is not None else "missing"
    return AlertsState(state, success.checked_at if success else None, until, error)
