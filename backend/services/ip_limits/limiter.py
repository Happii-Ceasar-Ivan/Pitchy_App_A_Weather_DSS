"""Per-IP sliding-window limits kept in the database, so every replica shares one count (B6).

Each check runs in one transaction: the row for (scope, hashed IP) is locked, times outside the
window are dropped, and the request is counted only if it is under the limit. The time comes
from the database clock after the lock is held, so replicas with skewed clocks still agree.
The raw IP is never stored; callers pass an HMAC key (``tokens.ip_key``).
"""

from dataclasses import dataclass
from datetime import datetime, timedelta

from fastapi import Request

from shared.db.pool import ConnectionFactory
from shared.settings import Settings

# Scope names are stored in the table (check: ^[a-z_]{1,40}$).
SESSION_CREATE = "session_create"
ASSESSMENT_READ = "assessment_read"
MATCH_CREATE = "match_create"
INGESTION_REQUEST = "ingestion_request"


@dataclass(frozen=True)
class IpLimitRule:
    scope: str
    max_requests: int
    window: timedelta


def rules_from_settings(settings: Settings) -> dict[str, IpLimitRule]:
    """The approved limits (user, 2026-11-25), adjustable by environment variable."""
    hour = timedelta(hours=1)
    return {
        SESSION_CREATE: IpLimitRule(SESSION_CREATE, settings.chat_sessions_per_ip_per_hour, hour),
        ASSESSMENT_READ: IpLimitRule(
            ASSESSMENT_READ,
            settings.ip_limit_assessment_requests,
            timedelta(minutes=settings.ip_limit_assessment_window_minutes),
        ),
        MATCH_CREATE: IpLimitRule(MATCH_CREATE, settings.ip_limit_match_creates_per_hour, hour),
        INGESTION_REQUEST: IpLimitRule(
            INGESTION_REQUEST, settings.ip_limit_ingestion_requests_per_hour, hour
        ),
    }


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


class IpRateLimiter:
    def __init__(self, connect: ConnectionFactory) -> None:
        self._connect = connect

    def hit(self, rule: IpLimitRule, ip_key: bytes) -> datetime | None:
        """Count one request. Returns None when allowed, else the time the caller may retry."""
        with self._connect() as conn:
            conn.execute(
                "insert into public.ip_rate_limits (scope, ip_key) values (%s, %s)"
                " on conflict do nothing",
                (rule.scope, ip_key),
            )
            times = conn.execute(
                "select hit_times from public.ip_rate_limits"
                " where scope = %s and ip_key = %s for update",
                (rule.scope, ip_key),
            ).fetchone()[0]
            # After the lock is held, so waiting requests see the earlier ones.
            now = conn.execute("select clock_timestamp()").fetchone()[0]
            recent = [t for t in times if t > now - rule.window]
            allowed = len(recent) < rule.max_requests
            if allowed:
                recent.append(now)
            conn.execute(
                "update public.ip_rate_limits set hit_times = %s, updated_at = %s"
                " where scope = %s and ip_key = %s",
                (recent, now, rule.scope, ip_key),
            )
        if allowed:
            return None
        return recent[0] + rule.window + timedelta(milliseconds=1)

    def purge(self) -> int:
        """Delete rows idle for more than a day (the only delete the app can do here)."""
        with self._connect() as conn:
            return conn.execute("select public.purge_old_ip_rate_limits()").fetchone()[0]
