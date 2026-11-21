"""Database connections for the backend at runtime.

The app connects with the least-privilege login in ``PITCHY_APP_DB_URL``; the admin
``SUPABASE_DB_URL`` is only for migrations. There is deliberately no fallback to the admin URL.
``prepare_threshold=None`` keeps queries working through Supabase's transaction pooler too.
"""

from collections.abc import Callable
from contextlib import AbstractContextManager

import psycopg
from psycopg_pool import ConnectionPool

from shared.settings import Settings

ConnectionFactory = Callable[[], AbstractContextManager[psycopg.Connection]]


class DatabaseNotConfiguredError(RuntimeError):
    pass


def create_pool(settings: Settings, *, min_size: int = 1, max_size: int = 5) -> ConnectionPool:
    if settings.app_db_url is None:
        raise DatabaseNotConfiguredError(
            "PITCHY_APP_DB_URL is not set: run scripts/create_db_login.py after migrating."
        )
    return ConnectionPool(
        settings.app_db_url.get_secret_value(),
        min_size=min_size,
        max_size=max_size,
        kwargs={"prepare_threshold": None, "connect_timeout": 15},
        open=False,
        name="pitchy-app",
    )
