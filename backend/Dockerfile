# Pitchy backend image (Cloud Run). One image, two uses:
#   service: default CMD below (the API)
#   job:     python scripts/ingest.py --trigger scheduled   (every 6 h via Cloud Scheduler)
# No secrets are baked in: they come from Secret Manager as environment variables at runtime.

FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_CACHE=1 \
    PITCHY_ENV=production

RUN pip install --no-cache-dir uv==0.11.17

# Create the user first and install as that user, so files are owned when written. (A later
# `chown -R` copies the whole .venv into a second layer and roughly doubles the image, which
# slows the image pull on every cold start.) UV_NO_CACHE keeps uv's download cache out too.
RUN useradd --create-home --uid 10001 pitchy && mkdir /app && chown pitchy /app
WORKDIR /app
USER pitchy

# Dependencies first (cached layer), exactly as locked, without dev tools.
COPY --chown=pitchy pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project

COPY --chown=pitchy api ./api
COPY --chown=pitchy services ./services
COPY --chown=pitchy shared ./shared
COPY --chown=pitchy scripts ./scripts

ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8080
CMD ["sh", "-c", "exec uvicorn api.app:app --host 0.0.0.0 --port ${PORT:-8080}"]
