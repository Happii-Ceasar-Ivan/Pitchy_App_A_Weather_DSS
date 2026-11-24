"""The chat limit step (P-06, B5 plan 4.2): one transaction, row lock, database clock only."""

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Literal

from shared.db.pool import ConnectionFactory
from shared.settings import Settings

# Asia/Manila is a fixed UTC+8 (no daylight saving). An interval offset avoids depending on the
# server's time zone database.
_USED_TODAY = (
    "select count(*) from public.conversation_events where provider_called and occurred_at >="
    " date_trunc('day', %(now)s at time zone interval '8 hours') at time zone interval '8 hours'"
)


@dataclass(frozen=True)
class Counted:
    """The question was counted; the caller may call the providers."""


@dataclass(frozen=True)
class RateLimited:
    retry_at: datetime


@dataclass(frozen=True)
class NotCounted:
    reason: Literal["DAILY_LIMIT_REACHED", "AI_UNAVAILABLE"]


@dataclass(frozen=True)
class SessionUnknown:
    pass


LimitDecision = Counted | RateLimited | NotCounted | SessionUnknown


class ChatLimiter:
    def __init__(self, connect: ConnectionFactory, settings: Settings) -> None:
        self._connect = connect
        self._max = settings.chat_max_prompts
        self._window = timedelta(minutes=settings.chat_window_minutes)
        self._cooldown = timedelta(minutes=settings.chat_cooldown_minutes)
        self._daily_cap = settings.chat_daily_ai_cap

    def check_and_count(self, token_hash: bytes, *, providers_configured: bool) -> LimitDecision:
        with self._connect() as conn:
            row = conn.execute(
                "select id, counted_prompt_times, cooldown_until"
                " from public.anonymous_sessions where token_hash = %s for update",
                (token_hash,),
            ).fetchone()
            if row is None:
                return SessionUnknown()
            session_id, times, cooldown_until = row
            # After the lock is held, so waiting requests see the earlier ones.
            now = conn.execute("select clock_timestamp()").fetchone()[0]

            if cooldown_until is not None and cooldown_until > now:
                self._save(conn, session_id, times, cooldown_until, now)
                return RateLimited(cooldown_until)

            recent = [t for t in times if t > now - self._window]
            if len(recent) >= self._max:
                until = now + self._cooldown
                self._save(conn, session_id, [], until, now)
                return RateLimited(until)

            if not providers_configured:
                self._save(conn, session_id, recent, cooldown_until, now)
                return NotCounted("AI_UNAVAILABLE")
            used_today = conn.execute(_USED_TODAY, {"now": now}).fetchone()[0]
            if used_today >= self._daily_cap:
                self._save(conn, session_id, recent, cooldown_until, now)
                return NotCounted("DAILY_LIMIT_REACHED")

            self._save(conn, session_id, [*recent, now], cooldown_until, now)
            return Counted()

    @staticmethod
    def _save(conn, session_id, times, cooldown_until, now) -> None:
        conn.execute(
            "update public.anonymous_sessions set counted_prompt_times = %s::timestamptz[],"
            " cooldown_until = %s, last_request_at = %s where id = %s",
            (times, cooldown_until, now, session_id),
        )
