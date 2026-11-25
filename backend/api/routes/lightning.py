"""Live lightning near a match's venue (DEC-06): Vaisala Xweather, checked on open, shared."""

from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from api.deps import get_connect, get_lightning_fetcher, get_settings_dep
from api.schemas.common import ERROR_RESPONSES, NOT_FOUND_RESPONSE
from api.schemas.lightning import (
    FlashOut,
    LightningLevel,
    LightningStatus,
    OfficialGuidance,
    VenueLightning,
)
from api.schemas.weather import Attribution, CoverageWindow
from services.match_contexts import load_match, thunderstorm_alert_active
from services.safety_engine.rules import get_rules
from services.weather_ingestion.jobs.lightning import lightning_state, refresh_lightning
from services.weather_ingestion.sources.xweather.lightning import ATTRIBUTION
from shared.db.pool import ConnectionFactory
from shared.db.repositories import (
    PgIngestionJobRepository,
    PgLightningRepository,
)
from shared.settings import Settings

router = APIRouter(prefix="/match-contexts", tags=["lightning"], responses=ERROR_RESPONSES)
DETECTION_MINUTES = 5
NOTE = (
    "Live lightning detection near the stadium from the last few minutes, not a forecast. "
    "Officials on site decide whether to stop play; Pitchy does not."
)


@router.get(
    "/{match_context_id}/lightning", response_model=VenueLightning, responses=NOT_FOUND_RESPONSE
)
def get_lightning(
    match_context_id: UUID,
    connect: Annotated[ConnectionFactory, Depends(get_connect)],
    settings: Annotated[Settings, Depends(get_settings_dep)],
    fetch=Depends(get_lightning_fetcher),  # noqa: B008
) -> VenueLightning:
    """Lightning detected within the radius in the last 5 minutes. Checked live only from
    shortly before kickoff to the end of the match, at most once per venue every few minutes
    for everyone. Shows the AFC 30/30 procedure when lightning is detected or a PAGASA
    thunderstorm alert covers the venue."""
    match, location = load_match(connect, match_context_id)
    now = datetime.now(UTC)
    start = match.kickoff_at - timedelta(minutes=settings.lightning_window_before_kickoff_minutes)
    end = match.kickoff_at + timedelta(hours=settings.match_coverage_hours)
    in_window = start <= now < end
    interval = timedelta(minutes=settings.lightning_check_minutes)
    repo, jobs = PgLightningRepository(connect), PgIngestionJobRepository(connect)
    if in_window:
        refresh_lightning(fetch, location, jobs, repo, interval, settings.lightning_radius_km)

    state = lightning_state(location, repo, jobs, interval, datetime.now(UTC))
    reading = state.reading
    reasons = []
    if reading is not None and state.state == "current" and reading.flash_count:
        reasons.append("LIGHTNING_DETECTED")
    if thunderstorm_alert_active(connect, location.scope_key, now):
        reasons.append("PAGASA_THUNDERSTORM_ALERT")
    guidance, level = None, None
    rules = get_rules()
    lightning_rules = rules.hazards.lightning
    if (
        reasons
        and reasons[0] == "LIGHTNING_DETECTED"
        and hasattr(lightning_rules, "level_for_distance")
    ):
        found = lightning_rules.level_for_distance(reading.nearest_km)
        if found is not None:
            level = LightningLevel(id=found.id, label=found.label, action=found.action,
                                   basis=found.basis, severity=found.severity)  # fmt: skip
    if reasons and getattr(lightning_rules, "status", None) == "guidance_only":
        src = rules.sources[lightning_rules.source]
        guidance = OfficialGuidance(
            source=f"{src.title}, {src.version}, {src.section.split(';')[0]}",
            procedure=lightning_rules.procedure,
            applies_note=lightning_rules.applies_note,
            shown_because=reasons,
        )
    return VenueLightning(
        venue=location.scope_key,
        live_window=CoverageWindow(start=start, end=end),
        in_live_window=in_window,
        status=LightningStatus(
            state=state.state,
            last_checked_at=reading.checked_at if reading else None,
            current_until=state.current_until,
            last_error_code=state.last_error_code,
        ),
        radius_km=reading.radius_km
        if reading and reading.radius_km
        else settings.lightning_radius_km,
        detection_minutes=DETECTION_MINUTES,
        flash_count=reading.flash_count if reading else None,
        nearest_km=reading.nearest_km if reading else None,
        latest_flash_at=reading.latest_flash_at if reading else None,
        flashes=[FlashOut(**f) for f in reading.flashes] if reading else [],
        level=level,
        guidance=guidance,
        attribution=Attribution(source_id="xweather_lightning", **ATTRIBUTION),
        note=NOTE,
    )
