"""Official alerts for a match's venue (FR-SAF-007). Refreshed "on open" at most hourly."""

from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from api.deps import get_alert_fetcher, get_connect, get_settings_dep
from api.schemas.alerts import AlertArea, OfficialAlertOut, VenueAlerts
from api.schemas.common import ERROR_RESPONSES, NOT_FOUND_RESPONSE
from api.schemas.weather import AlertsStatus
from services.match_contexts import load_match
from services.weather_ingestion.jobs.alerts import alerts_state, refresh_alerts
from shared.db.pool import ConnectionFactory
from shared.db.repositories import (
    PgAlertRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
)
from shared.settings import Settings

router = APIRouter(prefix="/match-contexts", tags=["alerts"], responses=ERROR_RESPONSES)


@router.get("/{match_context_id}/alerts", response_model=VenueAlerts, responses=NOT_FOUND_RESPONSE)
def get_alerts(
    match_context_id: UUID,
    connect: Annotated[ConnectionFactory, Depends(get_connect)],
    settings: Annotated[Settings, Depends(get_settings_dep)],
    fetch=Depends(get_alert_fetcher),  # noqa: B008
) -> VenueAlerts:
    """PAGASA alerts covering the match's venue, as issued. If the last nationwide check is over
    an hour old, PAGASA is checked first (at most hourly, one shared lock)."""
    _, location = load_match(connect, match_context_id)
    interval = timedelta(minutes=settings.fresh_alerts_minutes)
    repo, jobs = PgAlertRepository(connect), PgIngestionJobRepository(connect)
    refresh_alerts(fetch, PgLocationRepository(connect).list_all(), jobs, repo, interval)

    now = datetime.now(UTC)
    state = alerts_state(repo, jobs, interval, now)
    success = repo.last_successful_check()
    stored = repo.alerts_of_check(success.id) if success is not None else []
    codes = location.alert_codes
    matching = [
        a for a in stored
        if location.scope_key in a.matched_venues
        and (a.valid_until is None or a.valid_until > now)
    ]  # fmt: skip
    return VenueAlerts(
        venue=location.scope_key,
        status=AlertsStatus(
            state=state.state,
            last_checked_at=state.last_success_at,
            current_until=state.current_until,
            last_error_code=state.last_error_code,
        ),
        active_tropical_cyclones=success.active_cyclones if success is not None else None,
        alerts=[
            OfficialAlertOut(
                issuer=a.issuer,
                event=a.event,
                subtype=a.subtype,
                headline=a.headline,
                message=a.message,
                issued_at=a.issued_at,
                valid_until=a.valid_until,
                matched_areas=[
                    AlertArea(
                        name=area["municipality"] or area["province"],
                        code=area["code"],
                        level=area["level"],
                        relation=area["relation"],
                    )
                    for area in a.areas
                    if area["code"] in codes
                ],  # fmt: skip
            )
            for a in matching
        ],
    )
