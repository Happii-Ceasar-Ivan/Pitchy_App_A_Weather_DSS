"""Per-source data state for one match (DEC-04 freshness, P-05 vocabulary). Pure functions.

Order of checks for each source:
1. ``updating`` if a job for its scope holds the lock now.
2. Coverage: the newest successful fetch whose usable values cover kickoff .. kickoff + N h
   without a gap. A recent fetch that does not cover the match does not count.
3. Freshness of that fetch, by the source's rule (retrieval time or model run time):
   ``current`` while younger than the limit, else ``stale`` (shown with its times, never current).
4. Nothing covers the match: ``unavailable`` if the latest attempt failed, else ``missing``.

These are data-quality rules, never safety decisions. A source without a configured rule is
never reported current.
"""

from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Literal

from shared.db.records import FetchAttempt, FetchCoverage, IngestionJobRecord
from shared.settings import Settings

Basis = Literal["retrieved", "issued"]
_OLDER = "The newest forecast does not cover the match; an older one does."
_NO_RUN_TIME = "Model run time not reported; retrieval time used."


@dataclass(frozen=True)
class FreshnessRule:
    max_age: timedelta
    basis: Basis  # "issued" = the model run time the source reports (source_issued_at)


def freshness_rules(settings: Settings) -> dict[str, FreshnessRule]:
    return {
        "open_meteo": FreshnessRule(timedelta(hours=settings.fresh_open_meteo_hours), "retrieved"),
        "openweather": FreshnessRule(
            timedelta(hours=settings.fresh_openweather_hours), "retrieved"
        ),
        "pagasa_atmo": FreshnessRule(timedelta(hours=settings.fresh_pagasa_atmo_hours), "issued"),
        "pagasa_ecmwf": FreshnessRule(timedelta(hours=settings.fresh_pagasa_ecmwf_hours), "issued"),
    }


@dataclass(frozen=True)
class Note:
    code: str
    message: str  # plain language only; technical codes go in detail_code
    detail_code: str | None = None


@dataclass(frozen=True)
class SourceState:
    source_id: str
    state: str  # current | stale | missing | updating | unavailable
    coverage: FetchCoverage | None  # the fetch whose data is used, if any
    current_until: datetime | None  # when that data stops being current
    active_job: IngestionJobRecord | None
    notes: list[Note] = field(default_factory=list)

    @property
    def needs_data(self) -> bool:
        """DEC-04 (option C, 2026-11-22): stale, missing or unavailable sources need data."""
        return self.state in ("stale", "missing", "unavailable")


def covers(windows: Sequence[tuple[datetime, datetime]], start: datetime, end: datetime) -> bool:
    """True when the windows, joined together, cover [start, end) with no gap."""
    reached = start
    for valid_from, valid_until in sorted(windows):
        if valid_from > reached:
            return False
        reached = max(reached, valid_until)
        if reached >= end:
            return True
    return reached >= end


def assess_source(
    source_id: str,
    rule: FreshnessRule | None,
    fetches: Sequence[FetchCoverage],
    latest: FetchAttempt | None,
    active_job: IngestionJobRecord | None,
    start: datetime,
    end: datetime,
    now: datetime,
) -> SourceState:
    notes: list[Note] = []
    covering = next((f for f in fetches if covers(f.windows, start, end)), None)

    current_until = None
    if covering is not None:
        if fetches and covering is not fetches[0]:
            notes.append(Note("OLDER_FORECAST_USED", _OLDER))
        if (
            latest is not None
            and latest.status == "failed"
            and (latest.requested_at > covering.retrieved_at)
        ):
            notes.append(Note("LAST_ATTEMPT_FAILED", "The latest request to this source failed.",
                              latest.error_code))  # fmt: skip
        if rule is None:
            notes.append(Note("NO_FRESHNESS_RULE", "No freshness rule is configured."))
        else:
            basis_time = covering.retrieved_at
            if rule.basis == "issued":
                if covering.source_issued_at is not None:
                    basis_time = covering.source_issued_at
                else:
                    notes.append(Note("RUN_TIME_UNKNOWN", _NO_RUN_TIME))
            current_until = basis_time + rule.max_age

    if active_job is not None:
        state = "updating"
    elif covering is not None:
        if current_until is None:
            state = "unavailable"
        else:
            state = "current" if now < current_until else "stale"
    elif latest is not None and latest.status == "failed":
        state = "unavailable"
        notes.append(Note("SOURCE_ERROR", "The latest request to this source failed.",
                          latest.error_code))  # fmt: skip
    else:
        state = "missing"
        notes.append(
            Note("NOT_COVERED", "Stored forecasts do not cover the match time.")
            if fetches
            else Note("NO_DATA", "No forecast has been stored for this venue yet.")
        )
    return SourceState(source_id, state, covering, current_until, active_job, notes)
