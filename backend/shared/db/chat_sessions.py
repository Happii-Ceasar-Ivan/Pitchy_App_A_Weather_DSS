"""Storage for anonymous chat sessions (P-06). The sliding-window check is in
``services.chat_sessions.limiter``."""

from datetime import datetime

from shared.db.pool import ConnectionFactory


class PgChatSessionRepository:
    def __init__(self, connect: ConnectionFactory) -> None:
        self._connect = connect

    def create(self, token_hash: bytes) -> datetime:
        """Insert a session; returns its ``created_at`` from the database."""
        with self._connect() as conn:
            row = conn.execute(
                "insert into public.anonymous_sessions (token_hash) values (%s)"
                " returning created_at",
                (token_hash,),
            ).fetchone()
            return row[0]

    def exists(self, token_hash: bytes) -> bool:
        with self._connect() as conn:
            row = conn.execute(
                "select 1 from public.anonymous_sessions where token_hash = %s", (token_hash,)
            ).fetchone()
            return row is not None
