"""Manual ingestion for one match's venue (P-02, FR-WTH-004; decisions 2026-11-22 in
``docs/decisions/ingestion-trigger.md``).

One request -> one job per source group that needs data. Each lock is taken inside the request,
so the caller gets the job ids immediately; fetching runs on a background thread. A group whose
job is already running (another user, or the schedule) is returned as reused, never started twice.
"""

import logging
from collections.abc import Callable, Sequence
from concurrent.futures import Executor
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from services.weather_ingestion.jobs.runner import (
    DEFAULT_LEASE,
    LazyAdapter,
    acquire_group,
    execute_group,
)
from services.weather_ingestion.relevance.status import GroupState, VenueWeatherStatus
from services.weather_ingestion.sources.base import Venue
from shared.db.records import IngestionJobRecord
from shared.db.repositories import ForecastRepository, IngestionJobRepository

logger = logging.getLogger("pitchy.ingestion")


@dataclass(frozen=True)
class GroupJob:
    job: IngestionJobRecord
    source_ids: tuple[str, ...]
    reused: bool  # True: another request or the schedule started it


class IngestionNotNeededError(Exception):
    """Every enabled source is current and nothing is running (409)."""


class IngestionMustWaitError(Exception):
    """Only sources inside PAGASA's 4-hour gap need data (429 with retry_at)."""

    def __init__(self, retry_at: datetime) -> None:
        super().__init__(retry_at.isoformat())
        self.retry_at = retry_at


def start_manual_ingestion(
    status: VenueWeatherStatus,
    venue: Venue,
    jobs: IngestionJobRepository,
    forecasts: ForecastRepository,
    executor: Executor,
    *,
    lease: timedelta = DEFAULT_LEASE,
    now: Callable[[], datetime] = lambda: datetime.now(UTC),
) -> list[GroupJob]:
    result: list[GroupJob] = []
    for group_state in status.groups:
        job = _start_group(group_state, venue, jobs, forecasts, executor, lease, now)
        if job is not None:
            result.append(job)
    if result:
        return result
    if status.next_ingestion_at is not None:
        raise IngestionMustWaitError(status.next_ingestion_at)
    raise IngestionNotNeededError


def _start_group(
    state: GroupState,
    venue: Venue,
    jobs: IngestionJobRepository,
    forecasts: ForecastRepository,
    executor: Executor,
    lease: timedelta,
    now: Callable[[], datetime],
) -> GroupJob | None:
    if state.active_job is not None:
        return GroupJob(state.active_job, state.active_sources, reused=True)
    if not state.can_start_now:
        return None
    lock = acquire_group(state.group, venue, state.active_sources, jobs, forecasts, lease, now)
    if isinstance(lock, list):  # the 4-hour gap started since the status was read
        return None
    if lock.acquired:
        executor.submit(_run, state, venue, lock.job, jobs, forecasts, now)
    return GroupJob(lock.job, state.active_sources, reused=not lock.acquired)


def _run(
    state: GroupState,
    venue: Venue,
    job: IngestionJobRecord,
    jobs: IngestionJobRepository,
    forecasts: ForecastRepository,
    now: Callable[[], datetime],
) -> None:
    adapter = LazyAdapter(state.group.make_adapter)
    try:
        results = execute_group(
            state.group, adapter, venue, state.active_sources, job.id, jobs, forecasts, now
        )
        for r in results:
            logger.info("manual %s %s: %s", r.source_id, r.venue, r.status)
    except Exception:  # the lease expires and releases the lock; never crash the worker
        logger.exception("Manual ingestion job %s crashed", job.id)
    finally:
        adapter.close()


def source_ids_for_job(job: IngestionJobRecord, groups: Sequence, enabled: set[str]) -> list[str]:
    """Source ids a job covers, from its scope (``<group>:<venue>``)."""
    group_name = job.scope_key.split(":", 1)[0]
    for group in groups:
        if group.name == group_name:
            ids = [s for s in group.source_ids if s in enabled]
            return ids or [job.source_id]
    return [job.source_id]
