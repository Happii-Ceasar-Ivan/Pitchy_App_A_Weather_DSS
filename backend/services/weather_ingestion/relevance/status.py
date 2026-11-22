"""Weather status of one match: every enabled source's state plus what Ingest could do now.

Reads the shared cache only; never fetches. Used by ``GET /match-contexts/{id}/weather-status``
and before starting a manual ingestion (FR-WTH-003, FR-WTH-004).
"""

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta

from services.weather_ingestion.jobs.runner import AdapterGroup, lock_scope
from services.weather_ingestion.relevance.freshness import (
    SourceState,
    assess_source,
    freshness_rules,
)
from shared.db.records import IngestionJobRecord, Location
from shared.db.repositories import ForecastRepository, IngestionJobRepository
from shared.settings import Settings


@dataclass(frozen=True)
class GroupState:
    """One source group (one lock scope) for the venue."""

    group: AdapterGroup
    active_sources: tuple[str, ...]  # enabled source ids of this group
    active_job: IngestionJobRecord | None
    needs_data: bool  # a source is stale/missing/unavailable and no job is running
    next_allowed_at: datetime | None  # set while PAGASA's 4-hour gap or the failure cooldown
    #                                   blocks a new request

    @property
    def can_start_now(self) -> bool:
        return self.needs_data and self.next_allowed_at is None


@dataclass(frozen=True)
class VenueWeatherStatus:
    checked_at: datetime
    coverage_start: datetime
    coverage_end: datetime
    sources: list[SourceState]
    groups: list[GroupState]

    @property
    def ingestion_needed(self) -> bool:
        """DEC-04: any enabled source stale, missing or unavailable and not updating."""
        return any(s.needs_data for s in self.sources)

    @property
    def active_jobs(self) -> list[IngestionJobRecord]:
        return [g.active_job for g in self.groups if g.active_job is not None]

    @property
    def next_ingestion_at(self) -> datetime | None:
        """When a group that needs data may be requested again, if it must wait: PAGASA's
        4-hour gap (FR-WTH-008) or the cooldown after a failed attempt (DEC-04 option C)."""
        waits = [g.next_allowed_at for g in self.groups if g.needs_data and g.next_allowed_at]
        return min(waits) if waits else None


def venue_weather_status(
    groups: Sequence[AdapterGroup],
    enabled_sources: set[str],
    location: Location,
    kickoff_at: datetime,
    settings: Settings,
    forecasts: ForecastRepository,
    jobs: IngestionJobRepository,
    now: datetime,
) -> VenueWeatherStatus:
    start = kickoff_at
    end = kickoff_at + timedelta(hours=settings.match_coverage_hours)
    rules = freshness_rules(settings)
    active_groups = [(g, tuple(s for s in g.source_ids if s in enabled_sources)) for g in groups]
    active_groups = [(g, ids) for g, ids in active_groups if ids]
    running = {
        j.scope_key: j
        for j in jobs.active_for_scopes([lock_scope(g.name, location.scope_key)
                                         for g, _ in active_groups])
    }  # fmt: skip

    sources: list[SourceState] = []
    group_states: list[GroupState] = []
    for group, ids in active_groups:
        job = running.get(lock_scope(group.name, location.scope_key))
        latest = {sid: forecasts.latest_attempt(sid, location.id) for sid in ids}
        states = [
            assess_source(
                source_id,
                rules.get(source_id),
                forecasts.recent_coverage(source_id, location.id, start, end),
                latest[source_id],
                job,
                start,
                end,
                now,
            )
            for source_id in ids
        ]
        sources += states
        needs = any(s.needs_data for s in states)
        waits = []
        if needs and group.min_interval is not None:
            last = forecasts.last_requested_at(ids, location.id)
            if last is not None and now - last < group.min_interval:
                waits.append(last + group.min_interval)
        if needs:
            cooldown = timedelta(minutes=settings.retry_after_failure_minutes)
            for s in states:
                attempt = latest[s.source_id]
                if s.needs_data and attempt is not None and attempt.status == "failed":
                    if now - attempt.requested_at < cooldown:
                        waits.append(attempt.requested_at + cooldown)
        next_allowed = max(waits) if waits else None
        group_states.append(GroupState(group, ids, job, needs, next_allowed))
    return VenueWeatherStatus(now, start, end, sources, group_states)
