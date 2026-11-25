"""Anonymous session tokens (P-06): ``v1.<body>.<tag>``, signed with HMAC-SHA256.

The tag lets the backend reject forged or mangled tokens without a database lookup. The database
row is found by a second, domain-separated HMAC of the whole token. Nothing here logs.
"""

import base64
import hashlib
import hmac
import re
import secrets

from api.schemas.session import SESSION_TOKEN_MAX_CHARS

VERSION = "v1"
_TAG_PREFIX = b"pitchy-session-tag:"
_LOOKUP_PREFIX = b"pitchy-session-lookup:"
_IP_PREFIX = b"pitchy-ip:"
# 32 bytes in unpadded base64url is 43 characters, for both the body and the tag.
_SHAPE = re.compile(r"v1\.[A-Za-z0-9_-]{43}\.[A-Za-z0-9_-]{43}")


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _tag(secret: bytes, body: str) -> str:
    message = _TAG_PREFIX + f"{VERSION}.{body}".encode("ascii")
    return _b64(hmac.new(secret, message, hashlib.sha256).digest())


def issue_token(secret: bytes) -> str:
    body = _b64(secrets.token_bytes(32))
    return f"{VERSION}.{body}.{_tag(secret, body)}"


def verify_token(token: str | None, secret: bytes | None) -> bool:
    """True only for a well-formed token with a valid tag. Fails closed without a secret."""
    if not secret or not token or len(token) > SESSION_TOKEN_MAX_CHARS:
        return False
    if _SHAPE.fullmatch(token) is None:
        return False
    _, body, tag = token.split(".")
    return hmac.compare_digest(tag.encode("ascii"), _tag(secret, body).encode("ascii"))


def token_hash(token: str, secret: bytes) -> bytes:
    """The database key (32 bytes). Only call it for a token that passed ``verify_token``."""
    return hmac.new(secret, _LOOKUP_PREFIX + token.encode("ascii"), hashlib.sha256).digest()


def ip_key(ip: str, secret: bytes) -> bytes:
    """Keyed hash of a client IP for the per-IP limits; the raw IP is never kept."""
    return hmac.new(secret, _IP_PREFIX + ip.encode("utf-8", "replace"), hashlib.sha256).digest()
