"""FastAPI application factory.

Run locally from ``backend/``::

    uv run uvicorn api.app:app --reload
"""

import logging

from fastapi import FastAPI

from api.errors import register_error_handlers
from api.middleware.request_id import RequestIdMiddleware
from api.routes import health, ingestions, match_contexts, sessions
from shared.settings import Settings, get_settings

API_V1_PREFIX = "/api/v1"


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(level=settings.log_level)
    # httpx logs full request URLs at INFO; source URLs can carry tokens (PAGASA). Never log them.
    for noisy in ("httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    docs = settings.expose_api_docs
    app = FastAPI(
        title="Pitchy API",
        version="0.1.0",
        docs_url=f"{API_V1_PREFIX}/docs" if docs else None,
        redoc_url=None,
        openapi_url=f"{API_V1_PREFIX}/openapi.json" if docs else None,
    )

    register_error_handlers(app)
    for module in (health, sessions, match_contexts, ingestions):
        app.include_router(module.router, prefix=API_V1_PREFIX)

    if settings.env == "development" and settings.enable_dev_routes:
        from api.routes import dev  # local demo routes; never in test/production or the contract

        app.include_router(dev.router, prefix=API_V1_PREFIX)

    # Outermost, so request IDs cover every response, including last-resort 500s.
    app.add_middleware(RequestIdMiddleware)
    return app


app = create_app()
