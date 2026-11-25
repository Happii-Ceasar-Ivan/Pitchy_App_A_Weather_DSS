"""Anonymous session issuance (P-06).

Issuance is rate limited per client IP, which is the main defence against repeated session
creation. The count is shared in the database (B6). Raw IP addresses are not stored: the limit
keys on a keyed hash.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, Request, status

from api.deps import enforce_ip_limit, get_connect, get_settings_dep, session_secret
from api.schemas.common import ERROR_RESPONSES
from api.schemas.session import SessionCreated
from services.chat_sessions import tokens
from services.ip_limits import SESSION_CREATE
from shared.db.chat_sessions import PgChatSessionRepository
from shared.db.pool import ConnectionFactory
from shared.settings import Settings

router = APIRouter(prefix="/sessions", tags=["sessions"], responses=ERROR_RESPONSES)


@router.post("", status_code=status.HTTP_201_CREATED, response_model=SessionCreated)
def create_session(
    request: Request,
    settings: Annotated[Settings, Depends(get_settings_dep)],
    connect: Annotated[ConnectionFactory, Depends(get_connect)],
) -> SessionCreated:
    """Issue an anonymous chatbot session token. Call once per install."""
    secret = session_secret(settings)
    enforce_ip_limit(request, connect, SESSION_CREATE)
    token = tokens.issue_token(secret)
    created_at = PgChatSessionRepository(connect).create(tokens.token_hash(token, secret))
    return SessionCreated(token=token, created_at=created_at)
