"""ChatLimiter: window, cooldown, daily cap, concurrency (database clock only)."""

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

from services.chat_sessions.limiter import (
    ChatLimiter,
    Counted,
    NotCounted,
    RateLimited,
    SessionUnknown,
)
from shared.db.chat_sessions import PgChatSessionRepository
from shared.settings import Settings
from tests.conftest import requires_db

pytestmark = requires_db
H = bytes(range(32))


def setup(connect, settings=None):
    PgChatSessionRepository(connect).create(H)
    return ChatLimiter(connect, settings or Settings(env="test"))


def go(limiter, **kw):
    return limiter.check_and_count(H, providers_configured=kw.get("providers", True))


def row(conn):
    return conn.execute(
        "select counted_prompt_times, cooldown_until, last_request_at"
        " from public.anonymous_sessions where token_hash = %s", (H,)
    ).fetchone()  # fmt: skip


def add_events(conn, n, provider_called=True, ago=timedelta(0)):
    loc = conn.execute("select id from public.locations limit 1").fetchone()[0]
    mc = conn.execute(
        "insert into public.match_contexts (kickoff_at, location_id) values (now(), %s)"
        " returning id", (loc,)
    ).fetchone()[0]  # fmt: skip
    for _ in range(n):
        conn.execute(
            "insert into public.conversation_events (occurred_at, match_context_id, role,"
            " generation, outcome_code, provider_called, provider)"
            " values (now() - %s, %s, 'coach', %s, 'OK', %s, %s)",
            (ago, mc, "generated" if provider_called else "unavailable", provider_called,
             "gemini" if provider_called else None),
        )  # fmt: skip


def test_unknown_session(connect, conn):
    lim = ChatLimiter(connect, Settings(env="test"))
    assert lim.check_and_count(H, providers_configured=True) == SessionUnknown()


def test_ten_counted_then_cooldown_starts(connect, conn):
    lim = setup(connect)
    assert all(go(lim) == Counted() for _ in range(10))
    times, cooldown, last = row(conn)
    assert len(times) == 10 and cooldown is None and last is not None
    res = go(lim)
    assert isinstance(res, RateLimited)
    times, cooldown, _ = row(conn)
    assert times == [] and cooldown == res.retry_at
    delta = cooldown - conn.execute("select now()").fetchone()[0]
    assert timedelta(minutes=19) < delta <= timedelta(minutes=20)


def test_cooldown_not_extended_and_resets_after(connect, conn):
    lim = setup(connect)
    for _ in range(10):
        go(lim)
    first = go(lim)
    second = go(lim)
    assert isinstance(second, RateLimited) and second.retry_at == first.retry_at
    assert row(conn)[1] == first.retry_at
    conn.execute("update public.anonymous_sessions set cooldown_until = now() - interval '1 s'")
    assert go(lim) == Counted()
    assert len(row(conn)[0]) == 1


def test_old_times_dropped(connect, conn):
    lim = setup(connect)
    conn.execute(
        "update public.anonymous_sessions set counted_prompt_times ="
        " array_fill(now() - interval '11 minutes', array[10])"
    )
    assert go(lim) == Counted()
    assert len(row(conn)[0]) == 1


def test_full_window_back_dated_but_inside_still_limits(connect, conn):
    lim = setup(connect)
    conn.execute(
        "update public.anonymous_sessions set counted_prompt_times ="
        " array_fill(now() - interval '9 minutes', array[10])"
    )
    assert isinstance(go(lim), RateLimited)


def test_daily_cap_not_counted(connect, conn):
    lim = setup(connect, Settings(env="test", chat_daily_ai_cap=3))
    add_events(conn, 3)
    assert go(lim) == NotCounted("DAILY_LIMIT_REACHED")
    assert row(conn)[0] == []


def test_cap_ignores_non_provider_and_yesterday(connect, conn):
    lim = setup(connect, Settings(env="test", chat_daily_ai_cap=2))
    add_events(conn, 5, provider_called=False)
    add_events(conn, 5, ago=timedelta(days=2))
    assert go(lim) == Counted()
    add_events(conn, 1)
    assert go(lim) == Counted()  # 1 today + cap 2
    add_events(conn, 1)
    assert go(lim) == NotCounted("DAILY_LIMIT_REACHED")
    assert len(row(conn)[0]) == 2


def test_no_provider_not_counted(connect, conn):
    lim = setup(connect)
    assert go(lim, providers=False) == NotCounted("AI_UNAVAILABLE")
    times, _, last = row(conn)
    assert times == [] and last is not None


def test_eleven_parallel_requests_exactly_ten_counted(connect, conn):
    lim = setup(connect)
    with ThreadPoolExecutor(11) as pool:
        results = list(pool.map(lambda _: go(lim), range(11)))
    assert sum(r == Counted() for r in results) == 10
    assert sum(isinstance(r, RateLimited) for r in results) == 1
