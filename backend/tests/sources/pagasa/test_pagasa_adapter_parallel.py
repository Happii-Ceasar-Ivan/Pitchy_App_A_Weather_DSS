"""PagasaForecastAdapter against a fake panahon.gov.ph (no network)."""

import json
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx

from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import FetchFailure, SourceFetch, Venue
from services.weather_ingestion.sources.pagasa.forecast import PagasaForecastAdapter

FIXTURES = Path(__file__).parent / "fixtures"
TOKEN = "B" * 40
HOMEPAGE = f"""<meta name="csrf-token" content="{TOKEN}">
<meta name="nwp-runs" content='{{"atmo":"2026-11-21T18:00:00Z","ecmwf":"2026-11-21T12:00:00Z"}}'>"""
VENUES = [
    Venue("a", "rizal_memorial", "Rizal", 14.563405271502504, 120.99193149681405),
    Venue("b", "new_clark_city", "Clark", 15.34571628739377, 120.53364718440237),
]


class FakePanahon:
    def __init__(self, broken_model: str | None = None) -> None:
        self.hits: dict[str, int] = {}
        self.broken_model = broken_model
        self._lock = threading.Lock()
        self.forecasts = {
            m: json.loads((FIXTURES / name).read_text(encoding="utf-8"))
            for m, name in [("atmo", "forecast_rizal_atmo_2026-11-21T18Z.json"),
                            ("ecmwf", "forecast_rizal_ecmwf_2026-11-21T12Z.json")]
        }  # fmt: skip

    def __call__(self, request: httpx.Request) -> httpx.Response:
        with self._lock:
            self.hits[request.url.path] = self.hits.get(request.url.path, 0) + 1
        if request.url.path == "/":
            return httpx.Response(200, text=HOMEPAGE, headers={"content-type": "text/html"})
        assert request.url.params["token"] == TOKEN
        model = request.url.params["model"]
        if model == self.broken_model:
            return httpx.Response(500)
        return httpx.Response(200, json=self.forecasts[model])


def adapter_for(fake: FakePanahon) -> PagasaForecastAdapter:
    client = httpx.Client(transport=httpx.MockTransport(fake), follow_redirects=False)
    return PagasaForecastAdapter(AllowlistedClient("test", client))


def test_one_homepage_visit_for_parallel_venues() -> None:
    fake = FakePanahon()
    adapter = adapter_for(fake)
    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = [o for result in pool.map(adapter.fetch, VENUES) for o in result]
    assert fake.hits["/"] == 1
    assert fake.hits["/api/v1/tiles/point/forecast"] == 4  # 2 venues x 2 models
    assert all(isinstance(o, SourceFetch) for o in outcomes)
    assert sorted(o.source_id for o in outcomes) == ["pagasa_atmo"] * 2 + ["pagasa_ecmwf"] * 2


def test_one_model_down_keeps_the_other() -> None:
    adapter = adapter_for(FakePanahon(broken_model="ecmwf"))
    atmo, ecmwf = adapter.fetch(VENUES[0])
    assert isinstance(atmo, SourceFetch) and atmo.source_id == "pagasa_atmo"
    assert isinstance(ecmwf, FetchFailure) and ecmwf.error.code == "HTTP_500"


def test_close_discards_the_session() -> None:
    fake = FakePanahon()
    adapter = adapter_for(fake)
    adapter.fetch(VENUES[0])
    adapter.close()
    assert adapter._session is None
