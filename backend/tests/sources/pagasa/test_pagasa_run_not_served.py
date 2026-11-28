"""PAGASA lists a model run but serves no data for it (observed for ATMO from 2026-11-26).

The point forecast then answers HTTP 200 with an empty JSON list. That is PAGASA having no data,
not a format change, so it gets its own non-blocking code and a summary naming the run.
"""

from datetime import UTC, datetime

import pytest

from services.weather_ingestion.jobs.runner import BLOCKING_ERROR_CODES
from services.weather_ingestion.sources.base import (
    FetchFailure,
    SourceFetch,
    SourceResponseChangedError,
)
from services.weather_ingestion.sources.pagasa.forecast import PagasaRunNotServedError, parse
from tests.sources.pagasa.test_pagasa_adapter_parallel import (
    TOKEN,
    VENUES,
    FakePanahon,
    adapter_for,
)

ATMO_RUN = datetime(2026, 11, 21, 18, tzinfo=UTC)  # what the fake homepage lists


def test_empty_list_means_the_listed_run_is_not_served() -> None:
    with pytest.raises(PagasaRunNotServedError) as caught:
        parse([], VENUES[0], "atmo", ATMO_RUN)
    assert caught.value.code == "PAGASA_RUN_NOT_SERVED"
    assert caught.value.message == (
        "PAGASA lists ATMO run 2026-11-21T18:00Z but serves no data for it."
    )
    assert not isinstance(caught.value, SourceResponseChangedError)


@pytest.mark.parametrize(
    ("payload", "shape"),
    [
        ({"success": False}, "an object without success = true"),
        (["unexpected"], "a list"),
        ("text", "a str"),
    ],
    ids=["success-false", "non-empty-list", "string"],
)
def test_other_replies_name_the_run_and_the_shape(payload, shape) -> None:
    with pytest.raises(SourceResponseChangedError) as caught:
        parse(payload, VENUES[0], "atmo", ATMO_RUN)
    assert caught.value.code == "SOURCE_RESPONSE_CHANGED"
    assert caught.value.message == (
        f"PAGASA ATMO run 2026-11-21T18:00Z: expected a forecast object, got {shape}."
    )


def test_not_served_is_not_a_blocking_code() -> None:
    """PAGASA is not refusing us; the gap and cool-down rules stay as for any failure."""
    assert "PAGASA_RUN_NOT_SERVED" not in BLOCKING_ERROR_CODES


def test_adapter_reports_atmo_not_served_and_keeps_ecmwf() -> None:
    fake = FakePanahon()
    fake.forecasts["atmo"] = []
    atmo, ecmwf = adapter_for(fake).fetch(VENUES[0])
    assert isinstance(atmo, FetchFailure) and atmo.source_id == "pagasa_atmo"
    assert atmo.error.code == "PAGASA_RUN_NOT_SERVED"
    assert TOKEN not in atmo.error.message
    assert isinstance(ecmwf, SourceFetch) and ecmwf.source_id == "pagasa_ecmwf"
    assert fake.hits == {"/": 1, "/api/v1/tiles/point/forecast": 2}  # no retry, no fallback
