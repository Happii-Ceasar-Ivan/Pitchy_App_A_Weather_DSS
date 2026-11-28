import httpx
import pytest

from services.weather_ingestion.sources.allowlist.hosts import (
    AllowlistedClient,
    HostNotAllowedError,
    check_url,
)
from services.weather_ingestion.sources.base import SourceUnavailableError, Venue
from services.weather_ingestion.sources.dost_asti.adapter import DostAstiAdapter


def client_returning(status: int, headers: dict | None = None) -> AllowlistedClient:
    transport = httpx.MockTransport(lambda request: httpx.Response(status, headers=headers))
    return AllowlistedClient("test", httpx.Client(transport=transport, follow_redirects=False))


@pytest.mark.parametrize(
    "url",
    [
        "https://example.com/api",
        "http://api.open-meteo.com/v1/forecast",  # not HTTPS
        "https://api.open-meteo.com.evil.example/v1",
        "https://169.254.169.254/latest/meta-data",
        "file:///etc/passwd",
    ],
)
def test_only_approved_https_hosts(url: str) -> None:
    with pytest.raises(HostNotAllowedError):
        check_url(url)


def test_approved_hosts_pass() -> None:
    check_url("https://api.open-meteo.com/v1/forecast")
    check_url("https://www.panahon.gov.ph/")
    check_url("https://api.openweathermap.org/data/3.0/onecall")


@pytest.mark.parametrize(
    "url",
    [
        "http://api.openweathermap.org/data/3.0/onecall",  # not HTTPS
        "https://openweathermap.org/api",  # only the API host is approved
        "https://api.openweathermap.org.evil.example/data/3.0/onecall",
    ],
)
def test_openweather_only_its_api_host_over_https(url: str) -> None:
    with pytest.raises(HostNotAllowedError):
        check_url(url)


def test_redirects_are_not_followed() -> None:
    client = client_returning(302, {"Location": "https://example.com/"})
    with pytest.raises(SourceUnavailableError) as err:
        client.get("https://api.open-meteo.com/v1/forecast")
    assert err.value.code == "HTTP_302"


def test_http_errors_have_safe_codes_without_urls() -> None:
    with pytest.raises(SourceUnavailableError) as err:
        client_returning(419).get("https://www.panahon.gov.ph/api/v1/x", params={"token": "s3cr3t"})
    assert err.value.code == "HTTP_419"
    assert "s3cr3t" not in str(err.value) and "panahon" not in str(err.value)


def test_dost_asti_reports_not_configured() -> None:
    venue = Venue("loc", "rizal_memorial", "Rizal", 14.5, 121.0)
    (outcome,) = DostAstiAdapter().fetch(venue)
    assert outcome.error.code == "NOT_CONFIGURED"
