"""P-27 A2: PagasaForecastAdapter skips the download when PAGASA lists no newer run (no network)."""

from datetime import UTC, datetime

from services.weather_ingestion.sources.base import SourceFetch, SourceUnchanged
from tests.sources.pagasa.test_pagasa_adapter_parallel import VENUES, FakePanahon, adapter_for

FORECAST = "/api/v1/tiles/point/forecast"
ATMO_RUN = datetime(2026, 11, 21, 18, tzinfo=UTC)  # what the fake homepage lists
ECMWF_RUN = datetime(2026, 11, 21, 12, tzinfo=UTC)


def test_both_runs_known_means_one_request_and_no_download() -> None:
    fake = FakePanahon()
    atmo, ecmwf = adapter_for(fake).fetch(
        VENUES[0], known_runs={"pagasa_atmo": ATMO_RUN, "pagasa_ecmwf": ECMWF_RUN}
    )
    assert fake.hits == {"/": 1}  # the homepage only
    assert atmo == SourceUnchanged("pagasa_atmo", VENUES[0], ATMO_RUN)
    assert ecmwf == SourceUnchanged("pagasa_ecmwf", VENUES[0], ECMWF_RUN)


def test_only_the_model_with_a_newer_run_is_downloaded() -> None:
    fake = FakePanahon()
    older_atmo = datetime(2026, 11, 21, 12, tzinfo=UTC)
    atmo, ecmwf = adapter_for(fake).fetch(
        VENUES[0], known_runs={"pagasa_atmo": older_atmo, "pagasa_ecmwf": ECMWF_RUN}
    )
    assert fake.hits == {"/": 1, FORECAST: 1}
    assert isinstance(atmo, SourceFetch) and atmo.source_issued_at == ATMO_RUN
    assert isinstance(ecmwf, SourceUnchanged)


def test_nothing_stored_downloads_both() -> None:
    fake = FakePanahon()
    outcomes = adapter_for(fake).fetch(
        VENUES[0], known_runs={"pagasa_atmo": None, "pagasa_ecmwf": None}
    )
    assert fake.hits == {"/": 1, FORECAST: 2}
    assert all(isinstance(o, SourceFetch) for o in outcomes)


def test_without_known_runs_it_behaves_as_before() -> None:
    fake = FakePanahon()
    outcomes = adapter_for(fake).fetch(VENUES[0])
    assert fake.hits == {"/": 1, FORECAST: 2}
    assert all(isinstance(o, SourceFetch) for o in outcomes)


def test_listed_run_older_than_stored_is_never_downloaded() -> None:
    """A homepage listing an older run must not replace newer stored data."""
    fake = FakePanahon()
    newer = datetime(2026, 11, 22, 0, tzinfo=UTC)
    atmo, ecmwf = adapter_for(fake).fetch(
        VENUES[0], known_runs={"pagasa_atmo": newer, "pagasa_ecmwf": newer}
    )
    assert fake.hits == {"/": 1}
    assert atmo == SourceUnchanged("pagasa_atmo", VENUES[0], ATMO_RUN)  # the run PAGASA listed
    assert isinstance(ecmwf, SourceUnchanged)
