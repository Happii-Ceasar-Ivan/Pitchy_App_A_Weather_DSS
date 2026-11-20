"""Anonymous chatbot session contract (P-06).

Not an account and not authentication of a person: the token only lets the backend apply
per-session chatbot limits. The client stores it in secure platform storage and sends it as
the ``X-Session-Token`` header. The backend stores only an HMAC hash of it.
"""

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel

SESSION_TOKEN_HEADER = "X-Session-Token"  # noqa: S105 - a header name, not a secret
SESSION_TOKEN_MAX_CHARS = 512


class SessionCreated(ContractModel):
    token: str = Field(description="Opaque, server-signed. Never log or display it.")
    created_at: AwareDatetime
