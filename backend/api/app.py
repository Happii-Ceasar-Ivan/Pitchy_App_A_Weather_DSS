"""FastAPI application factory.

Run locally from ``backend/``::

    uv run uvicorn api.app:app --reload
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from api.deps import close_pool
from api.errors import register_error_handlers
from api.middleware.request_id import RequestIdMiddleware
from api.routes import (
    alerts,
    assessment,
    conversation,
    health,
    ingestions,
    lightning,
    match_contexts,
    sessions,
    venues,
)
from shared.settings import Settings, get_settings

API_V1_PREFIX = "/api/v1"


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(level=settings.log_level)
    # httpx logs full request URLs at INFO; source URLs can carry tokens (PAGASA). Never log them.
    for noisy in ("httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield
        shutdown = getattr(app.state, "on_shutdown", None)
        if shutdown is not None:
            shutdown()
        close_pool(app.state)

    docs = settings.expose_api_docs
    app = FastAPI(
        lifespan=lifespan,
        title="Pitchy API",
        version="0.1.0",
        docs_url=f"{API_V1_PREFIX}/docs" if docs else None,
        redoc_url=None,
        openapi_url=f"{API_V1_PREFIX}/openapi.json" if docs else None,
    )

    app.state.settings = settings
    register_error_handlers(app)
    for module in (
        health,
        venues,
        sessions,
        conversation,
        match_contexts,
        assessment,
        alerts,
        lightning,
        ingestions,
    ):
        app.include_router(module.router, prefix=API_V1_PREFIX)
    app.include_router(conversation.general_router, prefix=API_V1_PREFIX)  # no match (B6)

    if settings.env == "development" and settings.enable_dev_routes:
        from api.routes import dev  # local demo routes; never in test/production or the contract

        app.include_router(dev.router, prefix=API_V1_PREFIX)

    # Outermost, so request IDs cover every response, including last-resort 500s.
    app.add_middleware(RequestIdMiddleware)
    return app


app = create_app()
