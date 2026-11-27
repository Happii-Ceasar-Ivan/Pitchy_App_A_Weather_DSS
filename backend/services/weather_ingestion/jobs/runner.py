"""Ingestion runner: adapters + shared lock + PAGASA 4-hour rule + provenance storage.

Used by the 6-hour schedule and by manual ingestion (P-02); both go through the same lock, so the
same (source group, venue) can never be fetched twice at once (FR-WTH-004).

Not decided here (later sprints): whether cached data is fresh enough (DEC-04, B3) and anything
about safety (B4). This only fetches, normalizes and stores, recording failures honestly.
"""

import logging
import threading
from collections.abc import Callable, Sequence
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from uuid import UUID

from services.weather_ingestion.sources.base import (
    FetchFailure,
    SourceError,
    SourceFetch,
    SourceUnchanged,
    Venue,
)
from shared.db.records import LockResult
from shared.db.repositories import ForecastRepository, IngestionJobRepository

logger = logging.getLogger("pitchy.ingestion")

DEFAULT_LEASE = timedelta(minutes=5)


@dataclass(frozen=True)
class AdapterGroup:
    """One adapter and its rules. ``name`` is the lock scope prefix, e.g. ``pagasa``."""

    name: str
    source_ids: tuple[str, ...]
    make_adapter: Callable[[], object]  # fresh adapter per run (PAGASA: fresh session)
    min_interval: timedelta | None = None  # PAGASA: 4 h per venue (FR-WTH-008)
    # After an ordinary failure, wait this long before calling again, checked under the lock too
    # (P-27 A1). None: only the status check applies (DEC-04 cooldown).
    failure_cooldown: timedelta | None = None
    # Compare the source's listed model run with the stored one first and skip the download when
    # it is not newer (P-27 A2). The adapter's fetch then takes ``known_runs``.
    run_check: bool = False


# The source answered in a way that means "stop asking" (P-27 A1, DEC-02): such a failure starts
# the full minimum gap, like a success. Every other failure only gets the failure cooldown.
BLOCKING_ERROR_CODES = ("HTTP_401", "HTTP_403", "HTTP_429")

WaitReason = str  # "min_interval" | "source_refused" | "failure_cooldown"


@dataclass(frozen=True)
class GroupWait:
    until: datetime
    reason: WaitReason


def group_wait(
    group: AdapterGroup,
    active: Sequence[str],
    location_id: UUID,
    forecasts: ForecastRepository,
    now: datetime,
) -> GroupWait | None:
    """When this group may next be requested for a venue, if it must wait now; the later
    wait wins. Shared by the status view and the runner, so both always agree."""
    waits: list[GroupWait] = []
    if group.min_interval is not None:
        last = forecasts.last_gap_attempt(active, location_id, BLOCKING_ERROR_CODES)
        if last is not None and now - last.requested_at < group.min_interval:
            refused = last.status == "failed"  # only blocking failures are returned
            reason = "source_refused" if refused else "min_interval"
            waits.append(GroupWait(last.requested_at + group.min_interval, reason))
    if group.failure_cooldown is not None:
        for source_id in active:
            attempt = forecasts.latest_attempt(source_id, location_id)
            if (
                attempt is not None
                and attempt.status == "failed"
                and now - attempt.requested_at < group.failure_cooldown
            ):
                waits.append(
                    GroupWait(attempt.requested_at + group.failure_cooldown, "failure_cooldown")
                )
    return max(waits, key=lambda w: w.until) if waits else None


@dataclass
class SourceResult:
    source_id: str
    venue: str
    status: str  # stored | unchanged | failed | skipped_recent | in_progress | disabled
    values_stored: int = 0
    error_code: str | None = None
    message: str | None = None
    job_id: str | None = None


@dataclass
class IngestionReport:
    trigger: str
    started_at: datetime
    finished_at: datetime | None = None
    results: list[SourceResult] = field(default_factory=list)


class LazyAdapter:
    """Creates a group's adapter on first use, once, even when venues run in parallel."""

    def __init__(self, make: Callable[[], object]) -> None:
        self._make, self._adapter, self._lock = make, None, threading.Lock()

    def get(self):
        with self._lock:
            if self._adapter is None:
                self._adapter = self._make()
            return self._adapter

    def close(self) -> None:
        close = getattr(self._adapter, "close", None)
        if callable(close):
            close()


def lock_scope(group_name: str, venue_scope_key: str) -> str:
    """The lock / job scope for one source group at one venue, e.g. ``pagasa:rizal_memorial``."""
    return f"{group_name}:{venue_scope_key}"


def _skipped_recent(group, venue, active, forecasts, now) -> list[SourceResult] | None:
    """PAGASA's minimum gap (FR-WTH-008, P-27) or a failure cooldown: results to report if
    the group must wait."""
    wait = group_wait(group, active, venue.location_id, forecasts, now())
    if wait is None:
        return None
    next_allowed = wait.until.isoformat(timespec="minutes")
    return [
        SourceResult(s, venue.scope_key, "skipped_recent",
                     message=f"Must wait ({wait.reason}); next allowed {next_allowed}.")
        for s in active
    ]  # fmt: skip


def acquire_group(
    group: AdapterGroup,
    venue: Venue,
    active: tuple[str, ...],
    jobs: IngestionJobRepository,
    forecasts: ForecastRepository,
    lease: timedelta,
    now: Callable[[], datetime],
) -> LockResult | list[SourceResult]:
    """Check the wait rules, then take the group's lock. Returns the lock, or skip results."""
    skipped = _skipped_recent(group, venue, active, forecasts, now)
    if skipped is not None:
        return skipped
    return jobs.acquire(lock_scope(group.name, venue.scope_key), active[0], venue.location_id,
                        lease)  # fmt: skip


def execute_group(
    group: AdapterGroup,
    adapter: LazyAdapter,
    venue: Venue,
    active: tuple[str, ...],
    job_id: UUID,
    jobs: IngestionJobRepository,
    forecasts: ForecastRepository,
    now: Callable[[], datetime],
) -> list[SourceResult]:
    """Fetch, store and release a lock this worker holds. Always finishes the job."""
    # Re-check under the lock: another run may have called the source since the first check.
    skipped = _skipped_recent(group, venue, active, forecasts, now)
    if skipped is not None:
        jobs.finish(job_id, succeeded=False, failure_code="SKIPPED_RECENT",
                    failure_message="Requested less than the minimum interval ago; the shared"
                                    " cache is reused.")  # fmt: skip
        return skipped

    results = []
    answered, first_error = False, None  # answered: stored values or confirmed "no newer run"
    try:
        if group.run_check:
            known = {s: forecasts.latest_issued_at(s, venue.location_id) for s in active}
            outcomes = adapter.get().fetch(venue, known_runs=known)
        else:
            outcomes = adapter.get().fetch(venue)
    except SourceError as error:
        outcomes = [FetchFailure(s, venue, error) for s in active]
    except Exception:  # a bug, not a source problem: record safely and carry on
        logger.exception("Adapter %s crashed for %s", group.name, venue.scope_key)
        crash = SourceError("Unexpected adapter error.", "INTERNAL_ERROR")
        outcomes = [FetchFailure(s, venue, crash) for s in active]

    for outcome in outcomes:
        if outcome.source_id not in active:
            continue
        if isinstance(outcome, SourceFetch):
            forecasts.record_fetch(
                outcome.source_id,
                venue.location_id,
                job_id,
                outcome.values,
                source_issued_at=outcome.source_issued_at,
                raw_content_type=outcome.raw_content_type,
                raw_payload=outcome.raw_payload,
                raw_payload_sha256=outcome.raw_payload_sha256,
            )
            answered = True
            results.append(
                SourceResult(outcome.source_id, venue.scope_key, "stored",
                             values_stored=len(outcome.values), job_id=str(job_id),
                             message=" ".join(outcome.notes) or None)
            )  # fmt: skip
        elif isinstance(outcome, SourceUnchanged):
            forecasts.record_unchanged_fetch(
                outcome.source_id, venue.location_id, job_id, outcome.source_issued_at
            )
            answered = True
            run = outcome.source_issued_at.isoformat(timespec="minutes")
            results.append(
                SourceResult(outcome.source_id, venue.scope_key, "unchanged", job_id=str(job_id),
                             message=f"No newer run than {run}; cached values kept.")
            )  # fmt: skip
        else:
            error = outcome.error
            first_error = first_error or error
            forecasts.record_failed_fetch(
                outcome.source_id, venue.location_id, job_id, error.code, error.message
            )
            logger.warning("%s failed for %s: %s", outcome.source_id, venue.scope_key, error.code)
            results.append(
                SourceResult(outcome.source_id, venue.scope_key, "failed",
                             error_code=error.code, message=error.message, job_id=str(job_id))
            )  # fmt: skip

    finished = jobs.finish(
        job_id,
        succeeded=answered,
        failure_code=None if answered else (first_error.code if first_error else "NO_DATA"),
        failure_message=None if answered else (
            first_error.message if first_error else "The source returned nothing to store."
        ),
    )  # fmt: skip
    if not finished:
        logger.warning("Job %s lost its lease before finishing", job_id)
    return results


def _ingest_one(
    group: AdapterGroup,
    adapter: LazyAdapter,
    venue: Venue,
    active: tuple[str, ...],
    jobs: IngestionJobRepository,
    forecasts: ForecastRepository,
    lease: timedelta,
    now: Callable[[], datetime],
) -> list[SourceResult]:
    """One source group for one venue: 4-hour rule, lock, fetch, store, release."""
    lock = acquire_group(group, venue, active, jobs, forecasts, lease, now)
    if isinstance(lock, list):
        return lock
    if not lock.acquired:
        return [
            SourceResult(s, venue.scope_key, "in_progress", job_id=str(lock.job.id)) for s in active
        ]
    return execute_group(group, adapter, venue, active, lock.job.id, jobs, forecasts, now)


def run_ingestion(
    groups: Sequence[AdapterGroup],
    venues: Sequence[Venue],
    enabled_sources: set[str],
    jobs: IngestionJobRepository,
    forecasts: ForecastRepository,
    *,
    trigger: str = "manual",
    lease: timedelta = DEFAULT_LEASE,
    now: Callable[[], datetime] = lambda: datetime.now(UTC),
    max_workers: int = 8,
) -> IngestionReport:
    """Every (source group, venue) runs in parallel; the report keeps group/venue order."""
    report = IngestionReport(trigger=trigger, started_at=datetime.now(UTC))
    slots: list[list[SourceResult] | Future] = []
    adapters: list[LazyAdapter] = []
    with ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="ingest") as pool:
        for group in groups:
            active = tuple(s for s in group.source_ids if s in enabled_sources)
            if not active:
                slots.append([SourceResult(s, v.scope_key, "disabled")
                              for s in group.source_ids for v in venues])  # fmt: skip
                continue
            adapter = LazyAdapter(group.make_adapter)
            adapters.append(adapter)
            for venue in venues:
                slots.append(
                    pool.submit(_ingest_one, group, adapter, venue, active, jobs, forecasts,
                                lease, now)
                )  # fmt: skip
        for slot in slots:
            report.results += slot.result() if isinstance(slot, Future) else slot
    for adapter in adapters:
        adapter.close()
    report.finished_at = datetime.now(UTC)
    return report
