from datetime import UTC, datetime

import pytest

from services.weather_ingestion.sources.pagasa.session import (
    PagasaLayoutChangedError,
    parse_homepage,
)

FAKE_TOKEN = "A" * 40  # synthetic; real pages are never saved as fixtures
PAGE = f"""<html><head>
<meta name="csrf-token" content="{FAKE_TOKEN}">
<meta name="nwp-runs" content='{{"atmo":"2026-11-21T18:00:00Z","ecmwf":"2026-11-21T12:00:00Z"}}'>
</head><body></body></html>"""


def test_reads_token_and_runs() -> None:
    session = parse_homepage(PAGE)
    assert session.token == FAKE_TOKEN
    assert session.runs == {
        "atmo": datetime(2026, 11, 21, 18, tzinfo=UTC),
        "ecmwf": datetime(2026, 11, 21, 12, tzinfo=UTC),
    }


def test_token_never_appears_in_repr() -> None:
    assert FAKE_TOKEN not in repr(parse_homepage(PAGE))


@pytest.mark.parametrize(
    "page",
    [
        PAGE.replace('name="csrf-token"', 'name="other"'),
        PAGE.replace(FAKE_TOKEN, "short"),
        PAGE.replace(FAKE_TOKEN, "A" * 30 + "<script>"),
        PAGE.replace('name="nwp-runs"', 'name="other"'),
        PAGE.replace("2026-11-21T18:00:00Z", "not a time"),
        PAGE.replace("2026-11-21T18:00:00Z", "2026-11-21T18:00:00"),  # no time zone
        "<html>Maintenance</html>",
    ],
    ids=["no-token", "short-token", "odd-token", "no-runs", "bad-run", "naive-run", "maintenance"],
)
def test_layout_changes_are_detected(page: str) -> None:
    with pytest.raises(PagasaLayoutChangedError):
        parse_homepage(page)
