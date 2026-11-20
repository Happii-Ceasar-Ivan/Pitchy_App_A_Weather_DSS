"""Anonymous session issuance (P-06). Contract draft: returns 501 until Sprint B6.

Issuance is rate limited per client IP, which is the main defence against repeated session
creation. Raw IP addresses are not stored.
"""

from fastapi import APIRouter, status

from api.errors import not_implemented
from api.schemas.common import ERROR_RESPONSES
from api.schemas.session import SessionCreated

router = APIRouter(prefix="/sessions", tags=["sessions"], responses=ERROR_RESPONSES)


@router.post("", status_code=status.HTTP_201_CREATED, response_model=SessionCreated)
async def create_session() -> SessionCreated:
    """Issue an anonymous chatbot session token. Call once per install."""
    raise not_implemented("Sprint B6")
