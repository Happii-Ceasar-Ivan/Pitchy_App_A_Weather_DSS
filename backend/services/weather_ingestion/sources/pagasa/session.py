"""panahon.gov.ph session: one homepage visit gives the current token and forecast runs (P-10).

- ``token`` is the site's Laravel CSRF/session token from ``<meta name="csrf-token">``. It only
  works with the cookies of the same visit, which the ``AllowlistedClient`` keeps for this run.
- ``nwp-runs`` (``<meta name="nwp-runs">``) is JSON with the latest run per model, e.g.
  ``{"atmo": "2026-11-21T18:00:00Z", "ecmwf": "2026-11-21T12:00:00Z"}``.

A fresh visit starts every run, so rotating tokens and new runs are picked up automatically.
The token is never stored, logged or returned to clients.
"""

import json
from dataclasses import dataclass, field
from datetime import datetime
from html.parser import HTMLParser

from services.weather_ingestion.sources.allowlist.hosts import AllowlistedClient
from services.weather_ingestion.sources.base import SourceResponseChangedError

HOMEPAGE = "https://www.panahon.gov.ph/"


class _MetaReader(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.meta: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "meta":
            a = dict(attrs)
            if a.get("name") and a.get("content") is not None:
                self.meta[a["name"]] = a["content"]


class PagasaLayoutChangedError(SourceResponseChangedError):
    code = "PAGASA_LAYOUT_CHANGED"


@dataclass(frozen=True)
class PagasaSession:
    token: str = field(repr=False)
    runs: dict[str, datetime]

    def __repr__(self) -> str:
        return f"PagasaSession(token=<hidden>, runs={self.runs})"


def parse_homepage(html: str) -> PagasaSession:
    reader = _MetaReader()
    reader.feed(html)
    token = reader.meta.get("csrf-token", "")
    if not (20 <= len(token) <= 200 and token.isascii() and token.isalnum()):
        raise PagasaLayoutChangedError("panahon.gov.ph no longer exposes a usable csrf-token")
    try:
        raw_runs = json.loads(reader.meta.get("nwp-runs", ""))
        runs = {
            str(model): datetime.fromisoformat(str(value).replace("Z", "+00:00"))
            for model, value in raw_runs.items()
        }
    except (ValueError, AttributeError, TypeError) as exc:
        raise PagasaLayoutChangedError("panahon.gov.ph nwp-runs metadata is missing") from exc
    if not runs or any(run.tzinfo is None for run in runs.values()):
        raise PagasaLayoutChangedError("panahon.gov.ph nwp-runs metadata is malformed")
    return PagasaSession(token=token, runs=runs)


def open_session(client: AllowlistedClient) -> PagasaSession:
    return parse_homepage(client.get(HOMEPAGE).text)
