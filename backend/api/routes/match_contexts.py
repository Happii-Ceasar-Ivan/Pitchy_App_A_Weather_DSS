"""Match context, weather status, ingestion request, assessment and conversation routes.

Match contexts, weather status and manual ingestion are implemented (Sprint B3). Assessment (B4)
and conversation (B5) still return 501. Conversation requires an anonymous session token and is
rate limited per session (P-06).
"""

import math
from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, status

from api.deps import (
    enforce_ip_limit,
    get_adapter_groups,
    get_connect,
    get_ingestion_executor,
    get_settings_dep,
)
from api.errors import ApiError
from api.schemas.common import (
    ERROR_RESPONSES,
    NOT_FOUND_RESPONSE,
    ErrorCode,
    ErrorDetail,
    ErrorEnvelope,
    Limitation,
)
from api.schemas.match import MatchContext, MatchContextCreate
from api.schemas.weather import (
    AlertsStatus,
    Attribution,
    ConsolidatedQuantity,
    ConsolidatedSlot,
    ConsolidatedWeather,
    CoverageWindow,
    IngestionJob,
    IngestionRequestResult,
    Provenance,
    SourceStatus,
    SourceValueOut,
    ValueRangeOut,
    WeatherStatus,
)
from services.ip_limits import INGESTION_REQUEST, MATCH_CREATE
from services.match_contexts import current_status, load_match
from services.weather_ingestion import registry
from services.weather_ingestion.jobs.alerts import alerts_state
from services.weather_ingestion.jobs.manual import (
    IngestionMustWaitError,
    IngestionNotNeededError,
    start_manual_ingestion,
)
from services.weather_ingestion.relevance.consolidation import (
    SourceData,
    StoredValue,
    consolidate,
)
from services.weather_ingestion.relevance.freshness import SourceState
from shared.db.pool import ConnectionFactory
from shared.db.repositories import (
    PgAlertRepository,
    PgForecastRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
    PgMatchContextRepository,
)
from shared.settings import Settings

Connect = Annotated[ConnectionFactory, Depends(get_connect)]
AppSettings = Annotated[Settings, Depends(get_settings_dep)]
Groups = Annotated[list, Depends(get_adapter_groups)]

router = APIRouter(prefix="/match-contexts", tags=["match contexts"], responses=ERROR_RESPONSES)


def _source_status(state: SourceState, name: str) -> SourceStatus:
    cov = state.coverage
    provenance = None
    if cov is not None:
        provenance = Provenance(
            source_id=state.source_id,
            source_name=name,
            retrieved_at=cov.retrieved_at,
            source_issued_at=cov.source_issued_at,
            forecast_valid_from=min(w[0] for w in cov.windows),
            forecast_valid_until=max(w[1] for w in cov.windows),
            expires_at=None,
        )
    return SourceStatus(
        source_id=state.source_id,
        source_name=name,
        state=state.state,
        covers_match_time=cov is not None,
        current_until=state.current_until,
        provenance=provenance,
        limitations=[
            Limitation(code=n.code, message=n.message, detail_code=n.detail_code)
            for n in state.notes
        ],
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=MatchContext)
def create_match_context(
    request: Request, body: MatchContextCreate, connect: Connect
) -> MatchContext:
    """Save the match date/time and the chosen venue (FR-MAT-001, P-07)."""
    enforce_ip_limit(request, connect, MATCH_CREATE)
    location = PgLocationRepository(connect).get_by_scope_key(body.venue)
    if location is None:
        raise ApiError(
            422,
            ErrorCode.VALIDATION_ERROR,
            "The request did not pass validation.",
            [ErrorDetail(field="body.venue", issue="Unknown venue. Use a key from GET /venues.")],
        )
    match = PgMatchContextRepository(connect).create(
        body.kickoff_at.astimezone(UTC),
        location.id,
        location.name,
        body.pitch_surface,
        body.age_group.value,
    )
    return MatchContext.from_records(match, location)


@router.get("/{match_context_id}", response_model=MatchContext, responses=NOT_FOUND_RESPONSE)
def get_match_context(match_context_id: UUID, connect: Connect) -> MatchContext:
    match, location = load_match(connect, match_context_id)
    return MatchContext.from_records(match, location)


@router.get(
    "/{match_context_id}/weather-status",
    response_model=WeatherStatus,
    responses=NOT_FOUND_RESPONSE,
)
def get_weather_status(
    match_context_id: UUID, connect: Connect, settings: AppSettings, groups: Groups
) -> WeatherStatus:
    """Per-source freshness and match-time coverage (DEC-04); tells the client if Ingest is
    needed. Reads the shared cache only: it never fetches from a source."""
    match, location = load_match(connect, match_context_id)
    result, names = current_status(connect, groups, settings, match, location)
    return WeatherStatus(
        match_context_id=match.id,
        venue=location.scope_key,
        checked_at=result.checked_at,
        coverage=CoverageWindow(start=result.coverage_start, end=result.coverage_end),
        sources=[_source_status(s, names.get(s.source_id, s.source_id)) for s in result.sources],
        ingestion_needed=result.ingestion_needed,
        active_job_ids=[j.id for j in result.active_jobs],
        next_ingestion_at=result.next_ingestion_at,
        alerts=_alerts_status(connect, settings, result.checked_at),
    )


def _alerts_status(connect: ConnectionFactory, settings: Settings, now: datetime):
    state = alerts_state(
        PgAlertRepository(connect),
        PgIngestionJobRepository(connect),
        timedelta(minutes=settings.fresh_alerts_minutes),
        now,
    )
    return AlertsStatus(
        state=state.state,
        last_checked_at=state.last_success_at,
        current_until=state.current_until,
        last_error_code=state.last_error_code,
    )


ATTRIBUTIONS = {
    "open_meteo": Attribution(
        source_id="open_meteo", text="Weather data by Open-Meteo.com", url="https://open-meteo.com/"
    ),
}


@router.get(
    "/{match_context_id}/weather",
    response_model=ConsolidatedWeather,
    responses=NOT_FOUND_RESPONSE,
)
def get_consolidated_weather(
    match_context_id: UUID,
    connect: Connect,
    settings: AppSettings,
    groups: Groups,
    hours: Annotated[
        int | None,
        Query(ge=1, le=24, description="Hours from kickoff. Default: the coverage window."),
    ] = None,
) -> ConsolidatedWeather:
    """Consolidated hourly values (P-09): best current source per value, labelled fallback,
    range across comparable sources. Uses each source's cached fetch; never fetches."""
    match, location = load_match(connect, match_context_id)
    result, names = current_status(connect, groups, settings, match, location)
    start = match.kickoff_at.astimezone(UTC).replace(minute=0, second=0, microsecond=0)
    span = timedelta(hours=hours) if hours else result.coverage_end - result.coverage_start
    end = start + timedelta(hours=math.ceil((match.kickoff_at + span - start) / timedelta(hours=1)))
    forecasts = PgForecastRepository(connect)
    data = {}
    for s in result.sources:
        if s.coverage is None or s.current_until is None:
            continue
        rows = forecasts.values_of_fetch(s.coverage.fetch_id, start, end)
        data[s.source_id] = SourceData(
            s.source_id,
            names.get(s.source_id, s.source_id),
            "current" if result.checked_at < s.current_until else "stale",
            [StoredValue(r.parameter, r.value, r.unit, r.value_state, r.forecast_valid_from,
                         r.forecast_valid_until) for r in rows],
        )  # fmt: skip
    views = consolidate(data, start, end)
    return ConsolidatedWeather(
        match_context_id=match.id,
        venue=location.scope_key,
        checked_at=result.checked_at,
        window=CoverageWindow(start=start, end=end),
        sources=[_source_status(s, names.get(s.source_id, s.source_id)) for s in result.sources],
        quantities=[
            ConsolidatedQuantity(
                quantity=v.spec.key,
                label=v.spec.label,
                unit=v.spec.unit,
                priority=[p.source_id for p in v.spec.sources],
                slots=[
                    ConsolidatedSlot(
                        valid_from=slot.valid_from,
                        valid_until=slot.valid_until,
                        value=slot.value,
                        source_id=slot.source_id,
                        state=slot.state,
                        fallback_label=slot.label,
                        notes=slot.notes,
                        range=ValueRangeOut(**vars(slot.range)) if slot.range else None,
                        by_source=[SourceValueOut(**vars(b)) for b in slot.by_source],
                    )
                    for slot in v.slots
                ],
            )
            for v in views
        ],
        attributions=[ATTRIBUTIONS[s] for s in data if s in ATTRIBUTIONS],
    )


@router.post(
    "/{match_context_id}/ingestions",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=IngestionRequestResult,
    responses={
        **NOT_FOUND_RESPONSE,
        409: {
            "model": ErrorEnvelope,
            "description": "INGESTION_NOT_NEEDED: current shared data already covers this match.",
        },
    },
)
def request_ingestion(
    request: Request,
    match_context_id: UUID,
    connect: Connect,
    settings: AppSettings,
    groups: Groups,
    executor=Depends(get_ingestion_executor),  # noqa: B008
) -> IngestionRequestResult:
    """Start ingestion for the match's venue: one job per source group that needs data.

    A group already being ingested (by anyone, or the schedule) is returned with
    ``reused_existing_job: true`` instead of starting again. Poll each job with
    GET /ingestions/{id}, or poll weather-status. 429 with ``retry_at`` when the only sources
    needing data must wait: PAGASA's 4-hour gap (FR-WTH-008) or the cooldown after a failed
    attempt (DEC-04). A separate per-IP limit (B6) also answers 429.
    """
    enforce_ip_limit(request, connect, INGESTION_REQUEST)
    match, location = load_match(connect, match_context_id)
    result, _ = current_status(connect, groups, settings, match, location)
    try:
        started = start_manual_ingestion(
            result,
            registry.venue_from_location(location),
            PgIngestionJobRepository(connect),
            PgForecastRepository(connect),
            executor,
        )
    except IngestionNotNeededError:
        raise ApiError(
            409, ErrorCode.INGESTION_NOT_NEEDED, "Current shared data already covers this match."
        ) from None
    except IngestionMustWaitError as wait:
        raise ApiError(
            429,
            ErrorCode.RATE_LIMITED,
            "The sources needing data were requested too recently (PAGASA: 4 hours,"
            " FR-WTH-008; after a failure: a short cooldown). Try again after retry_at.",
            retry_at=wait.retry_at,
        ) from None
    return IngestionRequestResult(
        match_context_id=match.id,
        jobs=[
            IngestionJob(
                id=g.job.id,
                state=g.job.state,
                venue=location.scope_key,
                source_ids=list(g.source_ids),
                created_at=g.job.requested_at,
                started_at=g.job.started_at,
                finished_at=g.job.finished_at,
                failures=[],
                reused_existing_job=g.reused,
            )
            for g in started
        ],
    )
