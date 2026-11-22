"""Ingestion runner: adapters + shared lock + PAGASA 4-hour rule + provenance storage.

Used by the 6-hour schedule and by manual ingestion (P-02); both go through the same lock, so the
same (source group, venue) can never be fetched twice at once (FR-WTH-004).

Not decided here (later sprints): whether cached data is fresh enough (DEC-04, B3) and anything
about safety (B4). This only fetches, normalizes and stores, recording failures honestly.
"""

import logging
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

from services.weather_ingestion.sources.base import (
    FetchFailure,
    SourceError,
    SourceFetch,
    Venue,
)
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


@dataclass
class SourceResult:
    source_id: str
    venue: str
    status: str  # stored | failed | skipped_recent | in_progress | disabled
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
) -> IngestionReport:
    report = IngestionReport(trigger=trigger, started_at=now())
    for group in groups:
        active = tuple(s for s in group.source_ids if s in enabled_sources)
        if not active:
            report.results += [
                SourceResult(s, v.scope_key, "disabled") for s in group.source_ids for v in venues
            ]
            continue
        adapter = None
        for venue in venues:
            if group.min_interval is not None:
                last = forecasts.last_requested_at(active, venue.location_id)
                if last is not None and now() - last < group.min_interval:
                    next_allowed = (last + group.min_interval).isoformat(timespec="minutes")
                    report.results += [
                        SourceResult(s, venue.scope_key, "skipped_recent",
                                     message=f"Requested at {last.isoformat(timespec='minutes')}"
                                             f"; next allowed {next_allowed}.")
                        for s in active
                    ]  # fmt: skip
                    continue

            lock = jobs.acquire(
                f"{group.name}:{venue.scope_key}", active[0], venue.location_id, lease
            )
            if not lock.acquired:
                report.results += [
                    SourceResult(s, venue.scope_key, "in_progress", job_id=str(lock.job.id))
                    for s in active
                ]
                continue

            job_id = lock.job.id
            stored_any, first_error = False, None
            try:
                adapter = adapter or group.make_adapter()
                outcomes = adapter.fetch(venue)
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
                    stored_any = True
                    report.results.append(
                        SourceResult(outcome.source_id, venue.scope_key, "stored",
                                     values_stored=len(outcome.values), job_id=str(job_id),
                                     message=" ".join(outcome.notes) or None)
                    )  # fmt: skip
                else:
                    error = outcome.error
                    first_error = first_error or error
                    forecasts.record_failed_fetch(
                        outcome.source_id, venue.location_id, job_id, error.code, error.message
                    )
                    logger.warning(
                        "%s failed for %s: %s", outcome.source_id, venue.scope_key, error.code
                    )
                    report.results.append(
                        SourceResult(outcome.source_id, venue.scope_key, "failed",
                                     error_code=error.code, message=error.message,
                                     job_id=str(job_id))
                    )  # fmt: skip

            finish_job = jobs.finish(
                job_id,
                succeeded=stored_any,
                failure_code=None if stored_any else (first_error.code if first_error else None),
                failure_message=None if stored_any or not first_error else first_error.message,
            )
            if not finish_job:
                logger.warning("Job %s lost its lease before finishing", job_id)
        close = getattr(adapter, "close", None)
        if callable(close):
            close()
    report.finished_at = now()
    return report
