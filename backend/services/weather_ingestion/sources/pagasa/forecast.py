"""PAGASA point forecast for ATMO and ECMWF (DEC-02). See README.md in this folder.

Response (observed 2026-11-22)::

    {"success": true, "model": "atmo", "rain_unit": "mm/h",
     "data": {"heat_index": [{"forecast_at": "2026-11-22 02:00:00", "value": 34.8}, ...], ...}}

Times are Philippine Time (UTC+8) without an offset. Steps are uneven (15 min / 1 h / 3 h / 6 h),
so each value is valid until the next step.
"""

import json
import threading
from collections.abc import Mapping
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta, timezone

from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import (
    FetchFailure,
    FetchOutcome,
    SourceError,
    SourceFetch,
    SourceResponseChangedError,
    SourceUnchanged,
    Venue,
    require,
)
from services.weather_ingestion.sources.pagasa.session import PagasaSession, open_session
from shared.db.records import NewForecastValue

FORECAST_URL = "https://www.panahon.gov.ph/api/v1/tiles/point/forecast"
MODELS = ("atmo", "ecmwf")
PHT = timezone(timedelta(hours=8), "PHT")

# Numeric variables stored as values. Units for heat index and wind speed are not stated in the
# response; they follow the site's own legend ("°C", "m/s") and are recorded as such.
NUMERIC_UNITS = {"heat_index": "°C", "wind_speed": "m/s", "wind_direction": "°"}
RAIN = "accumulated_rain_1h"
RAIN_UNITS = {"mm", "mm/h"}
TEXT_FIELDS = {"icon"}  # weather description; kept in the raw payload only


def source_id(model: str) -> str:
    return f"pagasa_{model}"


def _pht(raw: object) -> datetime:
    try:
        return datetime.strptime(str(raw), "%Y-%m-%d %H:%M:%S").replace(tzinfo=PHT)
    except ValueError:
        raise SourceResponseChangedError(f"Unparseable PAGASA time {raw!r}") from None


def parse(payload: dict, venue: Venue, model: str, init: datetime) -> SourceFetch:
    require(isinstance(payload, dict) and payload.get("success") is True, "PAGASA success != true")
    require(payload.get("model") == model, f"PAGASA returned model {payload.get('model')!r}")
    rain_unit = payload.get("rain_unit")
    require(rain_unit in RAIN_UNITS, f"Unexpected PAGASA rain unit {rain_unit!r}")
    data = payload.get("data")
    expected = set(NUMERIC_UNITS) | {RAIN}
    require(isinstance(data, dict) and expected <= set(data), "PAGASA forecast variables changed")

    axis = [_pht(item.get("forecast_at")) for item in data["heat_index"]]
    require(len(axis) >= 2, "PAGASA forecast has fewer than two steps")
    require(all(a < b for a, b in zip(axis, axis[1:], strict=False)), "PAGASA times not ordered")
    first = axis[0].astimezone(UTC)
    # Time-zone guard: the first step is the model run itself (observed). If PAGASA ever
    # switched to UTC strings, `first` would land 8 h before `init` and fail here.
    require(init <= first < init + timedelta(hours=24), "PAGASA times no longer match its run")
    ends = axis[1:] + [axis[-1] + (axis[-1] - axis[-2])]

    units = dict(NUMERIC_UNITS, **{RAIN: rain_unit})
    values: list[NewForecastValue] = []
    for name, unit in units.items():
        series = data[name]
        require(
            isinstance(series, list) and [_pht(i.get("forecast_at")) for i in series] == axis,
            f"PAGASA {name} time axis differs",
        )
        for item, start, end in zip(series, axis, ends, strict=True):
            raw = item.get("value")
            ok = isinstance(raw, int | float) and not isinstance(raw, bool)
            values.append(
                NewForecastValue(
                    parameter=name,
                    value=float(raw) if ok else None,
                    unit=unit,
                    value_state="ok" if ok else "missing",
                    forecast_valid_from=start.astimezone(UTC),
                    forecast_valid_until=end.astimezone(UTC),
                    expires_at=None,
                )
            )

    return SourceFetch(
        source_id=source_id(model),
        venue=venue,
        values=values,
        raw_payload=json.dumps(payload, ensure_ascii=False),
        source_issued_at=init,
        notes=[f"PAGASA {model.upper()} run {init.isoformat()}; times converted from PHT."],
    )


class PagasaForecastAdapter:
    """One instance per ingestion run: the homepage is visited once, on first use."""

    source_ids = tuple(source_id(m) for m in MODELS)

    def __init__(self, client: AllowlistedClient) -> None:
        self._client = client
        self._session: PagasaSession | None = None
        self._lock = threading.Lock()

    def session(self) -> PagasaSession:
        """One homepage visit per run, even when venues are fetched in parallel."""
        with self._lock:
            if self._session is None:
                self._session = open_session(self._client)
            return self._session

    def _fetch_model(self, session: PagasaSession, venue: Venue, model: str) -> FetchOutcome:
        init = session.runs.get(model)
        try:
            require(init is not None, f"panahon.gov.ph lists no current {model} run")
            response = self._client.get(
                FORECAST_URL,
                params={
                    "lat": repr(venue.latitude),
                    "lon": repr(venue.longitude),
                    "model": model,
                    "init": init.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "token": session.token,
                },
            )
            try:
                payload = response.json()
            except ValueError:
                raise SourceResponseChangedError("PAGASA did not return JSON") from None
            return parse(payload, venue, model, init)
        except SourceError as error:
            return FetchFailure(source_id(model), venue, error)

    def fetch(
        self, venue: Venue, known_runs: Mapping[str, datetime | None] | None = None
    ) -> list[FetchOutcome]:
        """Both models for one venue. ``known_runs`` (source id -> run of the newest stored
        fetch) enables the run check (P-27 A2): a model whose listed run is not newer than the
        stored one is not downloaded; it comes back as ``SourceUnchanged``."""
        session = self.session()  # SourceError here means no model can be fetched
        known = known_runs or {}
        outcomes: dict[str, FetchOutcome] = {}
        to_fetch = []
        for model in MODELS:
            listed, stored = session.runs.get(model), known.get(source_id(model))
            if listed is not None and stored is not None and listed <= stored:
                outcomes[model] = SourceUnchanged(source_id(model), venue, listed)
            else:
                to_fetch.append(model)
        if to_fetch:
            with ThreadPoolExecutor(max_workers=len(to_fetch)) as pool:
                fetched = pool.map(lambda m: self._fetch_model(session, venue, m), to_fetch)
                outcomes.update(zip(to_fetch, fetched, strict=True))
        return [outcomes[m] for m in MODELS]

    def close(self) -> None:
        """Ends the run: cookies and token are discarded with the client."""
        self._session = None
        self._client.close()
