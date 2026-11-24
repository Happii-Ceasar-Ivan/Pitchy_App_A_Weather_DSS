"""Per-IP limit on session creation (in memory) and client IP resolution."""

import threading
import time
from collections import deque
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

from fastapi import Request

WINDOW_SECONDS = 3600
MAX_KEYS = 10_000


def client_ip(request: Request, hops: int) -> str:
    """Peer address, or the ``hops``-th entry from the right of X-Forwarded-For.

    The right side is written by our own proxies; the left side is client-controlled and is never
    used. A missing or too short header falls back to the direct peer.
    """
    peer = request.client.host if request.client else "unknown"
    if hops <= 0:
        return peer
    header = request.headers.get("x-forwarded-for")
    if not header:
        return peer
    entries = [part.strip() for part in header.split(",")]
    if len(entries) < hops or not entries[-hops]:
        return peer
    return entries[-hops]


class SessionIpLimiter:
    """Sliding one-hour window per hashed IP. Thread-safe; memory bounded by ``max_keys``."""

    def __init__(
        self,
        max_per_hour: int,
        *,
        max_keys: int = MAX_KEYS,
        clock: Callable[[], float] = time.time,
    ) -> None:
        self._max = max_per_hour
        self._max_keys = max_keys
        self._clock = clock
        self._lock = threading.Lock()
        self._hits: dict[bytes, deque[float]] = {}

    def hit(self, key: bytes) -> datetime | None:
        """Record a request. Returns None when allowed, else when the caller may retry."""
        now = self._clock()
        with self._lock:
            times = self._hits.get(key)
            if times is None:
                self._make_room(now)
                times = self._hits[key] = deque()
            while times and times[0] <= now - WINDOW_SECONDS:
                times.popleft()
            if len(times) >= self._max:
                return datetime.fromtimestamp(times[0] + WINDOW_SECONDS, UTC) + timedelta(
                    milliseconds=1
                )
            times.append(now)
            return None

    def _make_room(self, now: float) -> None:
        if len(self._hits) < self._max_keys:
            return
        for key in [k for k, t in self._hits.items() if not t or t[-1] <= now - WINDOW_SECONDS]:
            del self._hits[key]
        while len(self._hits) >= self._max_keys:
            del self._hits[next(iter(self._hits))]  # oldest inserted
