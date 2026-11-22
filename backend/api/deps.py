"""Request dependencies shared by the public routes: database connections and app services.

The connection pool is created on first use (so the app starts, and /health answers, even
without a database) and closed when the app shuts down. Tests override ``get_connect``.
"""

import threading
from concurrent.futures import Executor, ThreadPoolExecutor

from fastapi import Request

from api.errors import ApiError
from api.schemas.common import ErrorCode
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
