"""The chat limit step (P-06, B5 plan 4.2): one transaction, row lock, database clock only."""

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Literal

from shared.db.pool import ConnectionFactory
from shared.settings import Settings

# Asia/Manila is a fixed UTC+8 (no daylight saving). An interval offset avoids depending on the
# server's time zone database.
_NOW_AND_DAY = (
    "select t, (t at time zone interval '8 hours')::date from (select clock_timestamp() as t) s"
)
# The first question of a day starts the counter from that day's provider calls already
# recorded (so the day this table appears is counted too). Racing seeders: one inserts, the
# others wait on the key and do nothing.
_SEED_DAY = (
    "insert into public.chat_daily_ai_usage (day, reserved, updated_at)"
    " select %(day)s, (select count(*) from public.conversation_events"
    "   where provider_called"
    "   and occurred_at >= %(day)s::timestamp at time zone interval '8 hours'), %(now)s"
    " where not exists (select 1 from public.chat_daily_ai_usage where day = %(day)s)"
    " on conflict (day) do nothing"
)
# The row lock makes every replica's reservation wait for the others: never above the cap.
_RESERVE = (
    "update public.chat_daily_ai_usage set reserved = reserved + 1, updated_at = %(now)s"
    " where day = %(day)s and reserved < %(cap)s returning reserved"
)
_RELEASE = (
    "update public.chat_daily_ai_usage set reserved = reserved - 1, updated_at = clock_timestamp()"
    " where day = %s and reserved > 0"
)


@dataclass(frozen=True)
class Counted:
    """The question was counted and holds one daily AI slot; the caller may call the providers.

    If no provider ends up being called, the caller gives the slot back with ``release``.
    """

    ai_day: date | None = field(default=None, compare=False)


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
            now, day = conn.execute(_NOW_AND_DAY).fetchone()

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
            params = {"day": day, "now": now, "cap": self._daily_cap}
            conn.execute(_SEED_DAY, params)
            if conn.execute(_RESERVE, params).fetchone() is None:
                self._save(conn, session_id, recent, cooldown_until, now)
                return NotCounted("DAILY_LIMIT_REACHED")

            self._save(conn, session_id, [*recent, now], cooldown_until, now)
            return Counted(ai_day=day)

    def release(self, decision: Counted) -> None:
        """Give back the daily slot of a counted question that called no provider."""
        if decision.ai_day is None:
            return
        with self._connect() as conn:
            conn.execute(_RELEASE, (decision.ai_day,))

    @staticmethod
    def _save(conn, session_id, times, cooldown_until, now) -> None:
        conn.execute(
            "update public.anonymous_sessions set counted_prompt_times = %s::timestamptz[],"
            " cooldown_until = %s, last_request_at = %s where id = %s",
            (times, cooldown_until, now, session_id),
        )
