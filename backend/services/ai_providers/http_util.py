"""Shared HTTP helper for the AI provider adapters.

Maps every failure to a :class:`ProviderError` code. Nothing from httpx (which carries the request
URL), the request (key, prompt) or the response body is ever kept in an exception or a log.
"""

import logging
from typing import Any

import httpx

from services.ai_providers.base import ProviderError

# httpx logs every request URL at INFO. Keep it quiet, as the weather adapters do.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)


def post_json(
    url: str,
    *,
    headers: dict[str, str],
    body: dict[str, Any],
    timeout_s: float,
    transport: httpx.BaseTransport | None = None,
) -> Any:
    """POST a JSON body and return the parsed JSON reply, or raise ProviderError(code)."""
    try:
        with httpx.Client(
            timeout=httpx.Timeout(timeout_s),
            follow_redirects=False,
            transport=transport,
        ) as client:
            response = client.post(url, headers=headers, json=body)
    except httpx.TimeoutException:
        raise ProviderError("TIMEOUT") from None
    except httpx.HTTPError:
        raise ProviderError("NETWORK") from None
    status = response.status_code
    if status == 429:
        raise ProviderError("RATE_LIMITED")
    if not 200 <= status < 300:
        raise ProviderError(f"HTTP_{status}")
    try:
        return response.json()
    except ValueError:
        raise ProviderError("BAD_RESPONSE") from None
