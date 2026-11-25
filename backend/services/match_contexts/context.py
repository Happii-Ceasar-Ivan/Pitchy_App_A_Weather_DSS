"""Loading a match context and its venue's current weather and alert state.

Moved out of the route modules (B6 item 5) so services never import from ``api.routes``.
Behaviour is unchanged: an unknown match raises ``MatchNotFoundError``, which the API turns
into the same 404 ``NOT_FOUND`` envelope as before.
"""

from datetime import UTC, datetime
from uuid import UUID

from services.weather_ingestion.relevance.status import VenueWeatherStatus, venue_weather_status
from shared.db.pool import ConnectionFactory
from shared.db.records import Location, MatchContextRecord
from shared.db.repositories import (
    PgAlertRepository,
    PgForecastRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
    PgMatchContextRepository,
    PgWeatherSourceRepository,
)
from shared.settings import Settings


class MatchNotFoundError(LookupError):
    """No match context has this id."""


def load_match(
    connect: ConnectionFactory, match_context_id: UUID
) -> tuple[MatchContextRecord, Location]:
    match = PgMatchContextRepository(connect).get(match_context_id)
    if match is None:
        raise MatchNotFoundError(str(match_context_id))
    location = PgLocationRepository(connect).get(match.location_id)
    return match, location


def current_status(
    connect: ConnectionFactory, groups: list, settings: Settings, match, location
) -> tuple[VenueWeatherStatus, dict[str, str]]:
    """Per-source freshness and coverage for the match (reads the shared cache only)."""
    names = {s.id: s.name for s in PgWeatherSourceRepository(connect).list_enabled()}
    result = venue_weather_status(
        groups,
        set(names),
        location,
        match.kickoff_at,
        settings,
        PgForecastRepository(connect),
        PgIngestionJobRepository(connect),
        datetime.now(UTC),
    )
    return result, names


def thunderstorm_alert_active(connect: ConnectionFactory, scope_key: str, now: datetime) -> bool:
    """Whether the last successful PAGASA alert check has a thunderstorm alert for the venue."""
    repo = PgAlertRepository(connect)
    check = repo.last_successful_check()
    if check is None:
        return False
    return any(
        scope_key in a.matched_venues
        and "THUNDERSTORM" in a.event.upper()
        and (a.valid_until is None or a.valid_until > now)
        for a in repo.alerts_of_check(check.id)
    )
