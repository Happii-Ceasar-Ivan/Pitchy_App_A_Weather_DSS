"""Approved weather-source hosts and the only HTTP client adapters may use (SSRF prevention).

No URL from a user or a response is ever fetched unless its host is listed here. Redirects are
not followed, so a source cannot bounce the backend to another host.
"""

import logging
from urllib.parse import urlsplit

import httpx

from services.weather_ingestion.sources.base import SourceError, SourceUnavailableError

# httpx logs every request URL at INFO, and PAGASA URLs carry the session token. Never log them.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)

APPROVED_HOSTS: dict[str, str] = {
    "api.open-meteo.com": "Open-Meteo Forecast API (DEC-01, 2026-11-22)",
    "www.panahon.gov.ph": "PAGASA panahon.gov.ph, interim fallback (DEC-02, 2026-11-21)",
    "data.api.xweather.com": "Vaisala Xweather Weather API, lightning (DEC-06, 2026-11-23)",
    "api.openweathermap.org": "OpenWeather One Call API 3.0, forecast (P-30, 2026-11-28)",
}

DEFAULT_TIMEOUT = httpx.Timeout(20.0, connect=10.0)


class HostNotAllowedError(SourceError):
    code = "HOST_NOT_ALLOWED"


def check_url(url: str) -> str:
    parts = urlsplit(url)
    if parts.scheme != "https" or parts.hostname not in APPROVED_HOSTS:
        raise HostNotAllowedError(f"Host not on the source allowlist: {parts.hostname!r}")
    return url


class AllowlistedClient:
    """Thin wrapper over ``httpx.Client`` that refuses non-approved hosts.

    Errors are converted to ``SourceUnavailableError`` with a safe message: no URLs (which may
    contain tokens), headers or response bodies end up in errors or logs.
    """

    def __init__(self, user_agent: str, client: httpx.Client | None = None) -> None:
        self._client = client or httpx.Client(
            timeout=DEFAULT_TIMEOUT,
            follow_redirects=False,
            headers={"User-Agent": user_agent, "Accept": "application/json, text/html"},
        )

    def get(self, url: str, params: dict | None = None) -> httpx.Response:
        check_url(url)
        try:
            response = self._client.get(url, params=params)
        except httpx.TimeoutException as exc:
            raise SourceUnavailableError("The source did not answer in time.", "TIMEOUT") from exc
        except httpx.HTTPError as exc:
            raise SourceUnavailableError(
                f"Could not reach the source ({type(exc).__name__}).", "NETWORK_ERROR"
            ) from exc
        if response.status_code != 200:
            raise SourceUnavailableError(
                f"The source answered HTTP {response.status_code}.", f"HTTP_{response.status_code}"
            )
        return response

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> AllowlistedClient:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()
