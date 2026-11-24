"""Anonymous session issuance (P-06).

Issuance is rate limited per client IP, which is the main defence against repeated session
creation. Raw IP addresses are not stored: the in-memory limiter keys on a keyed hash.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, Request, status

from api.deps import get_connect, get_session_ip_limiter, get_settings_dep, session_secret
from api.errors import rate_limited
from api.schemas.common import ERROR_RESPONSES
from api.schemas.session import SessionCreated
from services.chat_sessions import tokens
from services.chat_sessions.ip_limit import SessionIpLimiter, client_ip
from shared.db.chat_sessions import PgChatSessionRepository
from shared.db.pool import ConnectionFactory
from shared.settings import Settings

router = APIRouter(prefix="/sessions", tags=["sessions"], responses=ERROR_RESPONSES)


@router.post("", status_code=status.HTTP_201_CREATED, response_model=SessionCreated)
def create_session(
    request: Request,
    settings: Annotated[Settings, Depends(get_settings_dep)],
    connect: Annotated[ConnectionFactory, Depends(get_connect)],
    ip_limiter: Annotated[SessionIpLimiter, Depends(get_session_ip_limiter)],
) -> SessionCreated:
    """Issue an anonymous chatbot session token. Call once per install."""
    secret = session_secret(settings)
    retry_at = ip_limiter.hit(tokens.ip_key(client_ip(request, settings.forwarded_hops), secret))
    if retry_at is not None:
        raise rate_limited(retry_at)
    token = tokens.issue_token(secret)
    created_at = PgChatSessionRepository(connect).create(tokens.token_hash(token, secret))
    return SessionCreated(token=token, created_at=created_at)
