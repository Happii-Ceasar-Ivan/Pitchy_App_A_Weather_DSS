"""Which adapters exist and their rules. One place to see every source at a glance."""

from datetime import timedelta

from services.weather_ingestion.jobs.runner import AdapterGroup
from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import Venue
from services.weather_ingestion.sources.dost_asti.adapter import DostAstiAdapter
from services.weather_ingestion.sources.open_meteo.adapter import OpenMeteoAdapter
from services.weather_ingestion.sources.pagasa.forecast import PagasaForecastAdapter
from shared.db.records import Location
from shared.settings import Settings


def adapter_groups(settings: Settings) -> list[AdapterGroup]:
    def client() -> AllowlistedClient:
        return AllowlistedClient(settings.http_user_agent)

    return [
        AdapterGroup("open_meteo", ("open_meteo",), lambda: OpenMeteoAdapter(client())),
        AdapterGroup(
            "pagasa",
            PagasaForecastAdapter.source_ids,
            lambda: PagasaForecastAdapter(client()),
            # FR-WTH-008 gap, a setting since P-27 A3 (default 4 h).
            min_interval=timedelta(minutes=settings.pagasa_min_interval_minutes),
            failure_cooldown=timedelta(minutes=settings.retry_after_failure_minutes),
            run_check=True,
        ),
        AdapterGroup("dost_asti", ("dost_asti",), DostAstiAdapter),
    ]


def venue_from_location(location: Location) -> Venue:
    return Venue(
        location_id=location.id,
        scope_key=location.scope_key,
        name=location.name or location.scope_key,
        latitude=location.latitude,
        longitude=location.longitude,
    )
