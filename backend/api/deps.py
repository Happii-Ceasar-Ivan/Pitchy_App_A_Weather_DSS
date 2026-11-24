"""Request dependencies shared by the public routes: database connections and app services.

The connection pool is created on first use (so the app starts, and /health answers, even
without a database) and closed when the app shuts down. Tests override ``get_connect``.
"""

import threading
from concurrent.futures import Executor, ThreadPoolExecutor
from typing import Annotated

from fastapi import Depends, Header, Request

from api.errors import ApiError
from api.schemas.common import ErrorCode
from api.schemas.session import SESSION_TOKEN_HEADER
from shared.db.pool import ConnectionFactory, DatabaseNotConfiguredError, create_pool
from shared.settings import Settings

_pool_lock = threading.Lock()


def get_settings_dep(request: Request) -> Settings:
    return request.app.state.settings


def get_connect(request: Request) -> ConnectionFactory:
    state = request.app.state
    if state.settings.env == "test":
        # Tests inject their own local database (dependency override); never the real one.
        raise ApiError(503, ErrorCode.SERVICE_UNAVAILABLE, "No database in the test environment.")
    with _pool_lock:
        if getattr(state, "pool", None) is None:
            try:
                pool = create_pool(state.settings, min_size=1, max_size=8)
            except DatabaseNotConfiguredError:
                raise ApiError(
                    503, ErrorCode.SERVICE_UNAVAILABLE, "The database is not configured."
                ) from None
            pool.open(wait=False)
            state.pool = pool
    return state.pool.connection


def close_pool(state) -> None:
    pool = getattr(state, "pool", None)
    if pool is not None:
        pool.close()
        state.pool = None


def get_adapter_groups(request: Request) -> list:
    """Source groups and their rules (services/weather_ingestion/registry.py)."""
    state = request.app.state
    if getattr(state, "adapter_groups", None) is None:
        from services.weather_ingestion import registry

        state.adapter_groups = registry.adapter_groups(state.settings)
    return state.adapter_groups


def get_ingestion_executor(request: Request) -> Executor:
    """Background threads for manual ingestion jobs; shut down with the app."""
    state = request.app.state
    with _pool_lock:
        if getattr(state, "ingestion_executor", None) is None:
            executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="manual-ingest")
            state.ingestion_executor = executor
            state.on_shutdown = lambda: executor.shutdown(wait=True, cancel_futures=True)
    return state.ingestion_executor


def get_alert_fetcher(request: Request):
    """The PAGASA alerts fetcher (allowlisted client). Tests override this."""
    from services.weather_ingestion.jobs.alerts import pagasa_alert_fetcher

    return pagasa_alert_fetcher(request.app.state.settings.http_user_agent)


def get_lightning_fetcher(request: Request):
    """The Xweather lightning fetcher (allowlisted client, keys from settings). Tests override."""
    from services.weather_ingestion.jobs.lightning import xweather_fetcher

    return xweather_fetcher(request.app.state.settings)


def session_secret(settings: Settings) -> bytes:
    """The token secret; without it session features are unavailable (fail closed)."""
    secret = settings.session_token_secret
    if secret is None or not secret.get_secret_value():
        raise ApiError(503, ErrorCode.SERVICE_UNAVAILABLE, "Chat sessions are not available.")
    return secret.get_secret_value().encode("utf-8")


def get_session_ip_limiter(request: Request):
    """The in-memory per-IP limiter for session creation (one per app)."""
    from services.chat_sessions.ip_limit import SessionIpLimiter

    state = request.app.state
    with _pool_lock:
        if getattr(state, "session_ip_limiter", None) is None:
            state.session_ip_limiter = SessionIpLimiter(
                state.settings.chat_sessions_per_ip_per_hour
            )
    return state.session_ip_limiter


def require_session(
    settings: Annotated[Settings, Depends(get_settings_dep)],
    connect: Annotated[ConnectionFactory, Depends(get_connect)],
    x_session_token: Annotated[str | None, Header(alias=SESSION_TOKEN_HEADER)] = None,
) -> bytes:
    """Check the ``X-Session-Token`` header; returns the session's token hash (its row key).

    A missing, forged or unknown token is 401 INVALID_SESSION. A forged token never reaches the
    database. The token is never logged.
    """
    from services.chat_sessions import tokens
    from shared.db.chat_sessions import PgChatSessionRepository

    secret = session_secret(settings)
    invalid = ApiError(401, ErrorCode.INVALID_SESSION, "Missing or invalid session token.")
    if not tokens.verify_token(x_session_token, secret):
        raise invalid
    key = tokens.token_hash(x_session_token, secret)
    if not PgChatSessionRepository(connect).exists(key):
        raise invalid
    return key
