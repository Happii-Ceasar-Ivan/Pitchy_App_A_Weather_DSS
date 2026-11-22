# Pitchy backend image (Cloud Run). One image, two uses:
#   service: default CMD below (the API)
#   job:     python scripts/ingest.py --trigger scheduled   (every 6 h via Cloud Scheduler)
# No secrets are baked in: they come from Secret Manager as environment variables at runtime.

FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PITCHY_ENV=production

RUN pip install --no-cache-dir uv==0.11.17

WORKDIR /app

# Dependencies first (cached layer), exactly as locked, without dev tools.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project

COPY api ./api
COPY services ./services
COPY shared ./shared
COPY scripts ./scripts

RUN useradd --create-home --uid 10001 pitchy && chown -R pitchy /app
USER pitchy

ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8080
CMD ["sh", "-c", "exec uvicorn api.app:app --host 0.0.0.0 --port ${PORT:-8080}"]
