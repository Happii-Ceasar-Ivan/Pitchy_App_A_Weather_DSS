"""Metadata-only conversation rows (DEC-14) and their retention (P-06).

Never stored: question or answer text, session id or token, IP address.
"""

from dataclasses import dataclass, field
from datetime import timedelta
from uuid import UUID

from psycopg.rows import dict_row

from shared.db.pool import ConnectionFactory


@dataclass(frozen=True)
class ConversationEvent:
    match_context_id: UUID | None  # None: a general question asked without a match
    assessment_id: UUID | None
    role: str
    generation: str  # generated | unavailable
    outcome_code: str  # GENERATED, AI_UNAVAILABLE, DAILY_LIMIT_REACHED, ANSWER_CHECK_FAILED, ...
    provider_called: bool
    provider: str | None
    reference_keys: list[str] = field(default_factory=list)
    retrieval_mode: str | None = None
    duration_ms: int | None = None


class PgConversationEventRepository:
    def __init__(self, connect: ConnectionFactory) -> None:
        self._connect = connect

    def record(self, event: ConversationEvent) -> None:
        with self._connect() as conn:
            conn.execute(
                "insert into public.conversation_events (match_context_id, assessment_id, role,"
                " generation, outcome_code, provider_called, provider, reference_keys,"
                " retrieval_mode, duration_ms) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    event.match_context_id, event.assessment_id, event.role, event.generation,
                    event.outcome_code, event.provider_called, event.provider,
                    event.reference_keys, event.retrieval_mode, event.duration_ms,
                ),
            )  # fmt: skip

    def purge(self, keep: timedelta) -> dict[str, int]:
        """Deletes rows and idle sessions older than ``keep`` (the only delete the app can do)."""
        with self._connect() as conn:
            cur = conn.cursor(row_factory=dict_row)
            return cur.execute(
                "select * from public.purge_old_conversation_data(%s)", (keep,)
            ).fetchone()
