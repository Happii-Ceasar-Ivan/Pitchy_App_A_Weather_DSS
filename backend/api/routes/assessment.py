"""Deterministic safety assessment for a match (B4). Works without any AI provider.

Reads the shared cache (Open-Meteo forecast, the latest lightning check, stored PAGASA alerts)
and the approved rules; it never fetches forecasts itself. Within the lightning live window it
refreshes lightning the same shared way as GET .../lightning (at most once per venue every few
minutes for everyone). A new assessment is saved only when its result changes (DEC-14).
"""

import hashlib
import json
from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from api.deps import get_adapter_groups, get_connect, get_lightning_fetcher, get_settings_dep
from api.routes.lightning import _thunderstorm_alert
from api.routes.match_contexts import _match_response, current_status, load_match
from api.schemas.assessment import (
    AssessmentLevel,
    HazardIndicator,
    IndicatorPoint,
    InputValue,
    OfficialNotice,
    RuleNotice,
    SafetyAssessment,
)
from api.schemas.common import (
    ERROR_RESPONSES,
    NOT_FOUND_RESPONSE,
    GuidanceReference,
    Limitation,
)
from api.schemas.weather import Provenance
from services.safety_engine import engine
from services.safety_engine.rules import get_rules
from services.weather_ingestion.jobs.lightning import lightning_state, refresh_lightning
from shared.db.pool import ConnectionFactory
from shared.db.repositories import (
    PgAlertRepository,
    PgAssessmentRepository,
    PgForecastRepository,
    PgIngestionJobRepository,
    PgLightningRepository,
)
from shared.settings import Settings

router = APIRouter(prefix="/match-contexts", tags=["assessment"], responses=ERROR_RESPONSES)
OPEN_METEO = "open_meteo"


def _guidance(ref: engine.Reference) -> GuidanceReference:
    return GuidanceReference(document_id=ref.source_id, title=ref.title, authority=ref.issuer,
                             version=ref.version, section=ref.section)  # fmt: skip


def _point(p: engine.Point) -> IndicatorPoint:
    return IndicatorPoint(at=p.at, forecast_stamp=p.stamp, value=p.wbgt,
                          used_for_level=p.used_for_level, missing=p.missing)  # fmt: skip


def _indicator(ind: engine.Indicator, source_name: str, retrieved_at) -> HazardIndicator:
    level = None
    if ind.level is not None:
        level = AssessmentLevel(
            id=ind.level.id,
            label=ind.level.label,
            action=" ".join(ind.level.action.split()),
            source=_guidance(ind.level.reference),
            also_supported_by=[_guidance(r) for r in ind.level.also_supported_by],
        )
    return HazardIndicator(
        hazard=ind.hazard,
        status=ind.status,
        indicator_value=round(ind.value, 2) if ind.value is not None else None,
        indicator_unit=ind.unit,
        classification=ind.level.id if ind.level else None,
        level=level,
        basis=ind.basis,
        decided_by=ind.decided_by,
        points=[_point(p) for p in ind.points],
        hourly=[_point(p) for p in ind.hourly],
        notices=[RuleNotice(id=i, text=t, source=_guidance(r)) for i, t, r in ind.notices],
        procedure=ind.procedure,
        inputs=[
            InputValue(
                parameter=r.parameter,
                value=r.value,
                unit=r.unit,
                provenance=Provenance(
                    source_id=OPEN_METEO,
                    source_name=source_name,
                    retrieved_at=retrieved_at,
                    forecast_valid_from=r.valid_from,
                    forecast_valid_until=r.valid_until,
                    expires_at=None,
                ),
            )
            for r in ind.inputs
        ],
        limitations=[Limitation(code=n.code, message=n.message) for n in ind.limitations],
        guidance=[_guidance(r) for r in ind.guidance],
    )


def _official_notices(connect: ConnectionFactory, scope_key: str, now: datetime):
    repo = PgAlertRepository(connect)
    check = repo.last_successful_check()
    if check is None:
        return []
    return [
        OfficialNotice(
            kind="severe_weather_alert",
            issuer=a.issuer,
            title=a.headline or f"{a.event} {a.subtype}".strip(),
            issued_at=a.issued_at,
            valid_until=a.valid_until,
            provenance=Provenance(
                source_id="pagasa",
                source_name="PAGASA alerts (panahon.gov.ph)",
                retrieved_at=check.checked_at,
                forecast_valid_from=a.issued_at,
                forecast_valid_until=a.valid_until,
                expires_at=None,
            ),
        )
        for a in repo.alerts_of_check(check.id)
        if scope_key in a.matched_venues and (a.valid_until is None or a.valid_until > now)
    ]


@router.get(
    "/{match_context_id}/assessment",
    response_model=SafetyAssessment,
    responses=NOT_FOUND_RESPONSE,
)
def get_assessment(
    match_context_id: UUID,
    connect: Annotated[ConnectionFactory, Depends(get_connect)],
    settings: Annotated[Settings, Depends(get_settings_dep)],
    groups: Annotated[list, Depends(get_adapter_groups)],
    fetch_lightning=Depends(get_lightning_fetcher),  # noqa: B008
) -> SafetyAssessment:
    """Deterministic assessment with inputs, limitations and rule version (FR-SAF-001..005).

    Heat: WBGT estimate (Liljegren) at 90 and 60 minutes before kickoff; the level comes from the
    approved rules for the match's age group, only from current forecast data. Lightning: the
    latest shared Xweather check and the AFC 10 km level. Rain: no approved rule. Official PAGASA
    alerts are listed as issued. Pitchy never makes the official decision."""
    rules = get_rules()
    match, location = load_match(connect, match_context_id)
    status, names = current_status(connect, groups, settings, match, location)
    now = status.checked_at

    weather = None
    om = next((s for s in status.sources if s.source_id == OPEN_METEO), None)
    if om is not None and om.coverage is not None and om.current_until is not None:
        span_before = max(rules.hazards.heat.evaluate_at_minutes_before_kickoff)
        start = match.kickoff_at - timedelta(minutes=span_before) - timedelta(hours=2)
        end = match.kickoff_at + timedelta(hours=settings.match_coverage_hours + 2)
        rows = PgForecastRepository(connect).values_of_fetch(om.coverage.fetch_id, start, end)
        weather = engine.OpenMeteoData(
            current=now < om.current_until,
            retrieved_at=om.coverage.retrieved_at,
            current_until=om.current_until,
            rows=[engine.WeatherRow(r.id, r.parameter, r.value, r.unit, r.value_state,
                                    r.forecast_valid_from, r.forecast_valid_until)
                  for r in rows],
        )  # fmt: skip

    window_start = match.kickoff_at - timedelta(
        minutes=settings.lightning_window_before_kickoff_minutes
    )
    window_end = match.kickoff_at + timedelta(hours=settings.match_coverage_hours)
    in_window = window_start <= now < window_end
    interval = timedelta(minutes=settings.lightning_check_minutes)
    lrepo, jobs = PgLightningRepository(connect), PgIngestionJobRepository(connect)
    if in_window:
        refresh_lightning(fetch_lightning, location, jobs, lrepo, interval,
                          settings.lightning_radius_km)  # fmt: skip
    lstate = lightning_state(location, lrepo, jobs, interval, datetime.now(UTC))
    reading = lstate.reading
    lightning = engine.LightningInput(
        state=lstate.state,
        in_live_window=in_window,
        checked_at=reading.checked_at if reading else None,
        flash_count=reading.flash_count if reading else None,
        nearest_km=reading.nearest_km if reading else None,
        last_error_code=lstate.last_error_code,
    )

    result = engine.assess(
        rules,
        age_group=match.age_group,
        kickoff_at=match.kickoff_at,
        latitude=location.latitude,
        longitude=location.longitude,
        weather=weather,
        lightning=lightning,
        thunderstorm_alert=_thunderstorm_alert(connect, location.scope_key, now),
        match_hours=settings.match_coverage_hours,
    )
    om_name = names.get(OPEN_METEO, "Open-Meteo")
    retrieved = weather.retrieved_at if weather else None
    indicators = [_indicator(i, om_name, retrieved) for i in result.indicators]
    notices = _official_notices(connect, location.scope_key, now)
    limitations = [Limitation(code=n.code, message=n.message) for n in result.limitations]

    # Save on change (DEC-14): the fingerprint covers everything except the times of this check.
    body = {
        "match_context_id": str(match.id),
        "age_group": result.age_group,
        "rules_approved": result.rules_approved,
        "rule_version": result.rule_version,
        "indicators": [i.model_dump(mode="json") for i in indicators],
        "official_notices": [n.model_dump(mode="json") for n in notices],
        "limitations": [lim.model_dump(mode="json") for lim in limitations],
    }
    fingerprint = hashlib.sha256(
        json.dumps(body, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    repo = PgAssessmentRepository(connect)
    latest = repo.latest(match.id)
    if latest is not None and latest["fingerprint"] == fingerprint:
        saved = latest
    else:
        used = [(r.id, i.hazard) for i in result.indicators for r in i.inputs]
        saved = repo.save(match.id, result.rule_version, {**body, "input_fingerprint": fingerprint},
                          body["limitations"], used)  # fmt: skip

    return SafetyAssessment(
        id=saved["id"],
        match_context=_match_response(match, location),
        assessed_at=saved["assessed_at"],
        checked_at=now,
        age_group=result.age_group,
        rules_approved=result.rules_approved,
        rule_version=result.rule_version,
        indicators=indicators,
        official_notices=notices,
        limitations=limitations,
    )
