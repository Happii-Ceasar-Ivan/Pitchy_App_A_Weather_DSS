"""Run weather ingestion now, for every venue and every enabled source.

Run from ``backend/``::

    uv run python scripts/ingest.py                       # manual ingestion
    uv run python scripts/ingest.py --trigger scheduled   # what the 6-hour schedule will call
    uv run python scripts/ingest.py --record DIR          # also save raw responses (test samples)

Uses the least-privilege ``PITCHY_APP_DB_URL``. Respects the shared lock and PAGASA's 4-hour
rule, then checks PAGASA's official alerts (at most hourly) into the database, then rotates
weather data older than the retention period (DEC-11).
``--record`` never saves the PAGASA homepage or any token: only JSON API responses, named
after what was asked (source, venue, model).
"""

import argparse
import json
import os
import sys
from datetime import timedelta
from pathlib import Path
from urllib.parse import urlsplit

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from services.weather_ingestion import registry  # noqa: E402
from services.weather_ingestion.jobs.alerts import (  # noqa: E402
    pagasa_alert_fetcher,
    refresh_alerts,
)
from services.weather_ingestion.jobs.runner import run_ingestion  # noqa: E402
from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient  # noqa: E402
from shared.db.conversation_events import PgConversationEventRepository  # noqa: E402
from shared.db.pool import DatabaseNotConfiguredError, create_pool  # noqa: E402
from shared.db.repositories import (  # noqa: E402
    PgAlertRepository,
    PgForecastRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
    PgRetentionRepository,
    PgWeatherSourceRepository,
)
from shared.settings import Settings  # noqa: E402


class RecordingClient(AllowlistedClient):
    """Saves JSON API responses to ``directory``. Skips HTML pages (they carry the token)."""

    def __init__(self, user_agent: str, directory: Path) -> None:
        super().__init__(user_agent)
        self._dir = directory
        self._dir.mkdir(parents=True, exist_ok=True)

    def get(self, url, params=None):
        response = super().get(url, params=params)
        if "json" not in response.headers.get("content-type", ""):
            return response
        params = params or {}
        path = urlsplit(url).path.strip("/").replace("/", "_")
        parts = [urlsplit(url).hostname.split(".")[-3], path]
        parts += [str(params[k]) for k in ("latitude", "lat", "model") if k in params]
        name = "__".join(p.replace(".", "_") for p in parts if p) + ".json"
        (self._dir / name).write_text(
            json.dumps(response.json(), ensure_ascii=False, indent=1), encoding="utf-8"
        )
        return response


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    # PITCHY_INGEST_TRIGGER lets schedulers set the trigger without passing "--" arguments.
    parser.add_argument(
        "--trigger",
        default=os.environ.get("PITCHY_INGEST_TRIGGER", "manual"),
        choices=["manual", "scheduled"],
    )
    parser.add_argument("--record", type=Path, help="save raw JSON responses to this folder")
    args = parser.parse_args()

    settings = Settings()
    try:
        pool = create_pool(settings, min_size=2, max_size=8)
    except DatabaseNotConfiguredError as exc:
        print(exc, file=sys.stderr)
        return 2
    pool.open(wait=True, timeout=30)
    try:
        return _run(args, settings, pool.connection)
    finally:
        pool.close()


def _run(args, settings: Settings, connect) -> int:
    groups = registry.adapter_groups(settings)
    if args.record:
        from dataclasses import replace

        from services.weather_ingestion.sources.open_meteo.adapter import OpenMeteoAdapter
        from services.weather_ingestion.sources.pagasa.forecast import PagasaForecastAdapter

        def rec() -> RecordingClient:
            return RecordingClient(settings.http_user_agent, args.record)

        makers = {"open_meteo": lambda: OpenMeteoAdapter(rec()),
                  "pagasa": lambda: PagasaForecastAdapter(rec())}  # fmt: skip
        groups = [replace(g, make_adapter=makers.get(g.name, g.make_adapter)) for g in groups]

    locations = PgLocationRepository(connect).list_all()
    venues = [registry.venue_from_location(loc) for loc in locations]
    enabled = {s.id for s in PgWeatherSourceRepository(connect).list_enabled()}
    report = run_ingestion(
        groups,
        venues,
        enabled,
        PgIngestionJobRepository(connect),
        PgForecastRepository(connect),
        trigger=args.trigger,
    )
    seconds = (report.finished_at - report.started_at).total_seconds()
    print(f"Ingestion ({report.trigger}) {report.started_at:%Y-%m-%d %H:%M:%S}Z, {seconds:.1f}s")
    for r in report.results:
        detail = f"{r.values_stored} values" if r.status == "stored" else (r.error_code or "")
        print(f"  {r.source_id:13} {r.venue:15} {r.status:15} {detail}  {r.message or ''}")

    # Official alerts: one nationwide check, at most hourly (DEC-02), same lock table.
    alerts = refresh_alerts(
        pagasa_alert_fetcher(settings.http_user_agent),
        locations,
        PgIngestionJobRepository(connect),
        PgAlertRepository(connect),
        timedelta(minutes=settings.fresh_alerts_minutes),
    )
    print(f"  {'pagasa alerts':13} {'nationwide':15} {alerts.status:15} {alerts.error_code or ''}")

    # Retention (DEC-11): rotate old weather data. A failure here never fails the ingest run.
    try:
        deleted = PgRetentionRepository(connect).purge(
            timedelta(days=settings.retention_forecast_days),
            timedelta(days=settings.retention_job_days),
        )
        print("  retention     " + ", ".join(f"{k.removesuffix('_deleted')}={v}"
                                             for k, v in deleted.items()))  # fmt: skip
    except Exception as exc:  # noqa: BLE001 - reported, then the run still succeeds
        print(f"  retention     failed ({type(exc).__name__})", file=sys.stderr)

    # Retention (P-06, DEC-14): conversation rows and idle anonymous sessions after 30 days.
    try:
        deleted = PgConversationEventRepository(connect).purge(
            timedelta(days=settings.retention_conversation_days)
        )
        print("  chat cleanup  " + ", ".join(f"{k.removesuffix('_deleted')}={v}"
                                             for k, v in deleted.items()))  # fmt: skip
    except Exception as exc:  # noqa: BLE001 - reported, then the run still succeeds
        print(f"  chat cleanup  failed ({type(exc).__name__})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
