# ---- build stage: compile wheels, so the runtime image needs no compiler and no pip cache
FROM python:3.12-slim AS build
WORKDIR /src
COPY requirements.txt .
RUN pip wheel --no-cache-dir --retries 10 --timeout 60 --wheel-dir /wheels -r requirements.txt

# ---- runtime stage
FROM python:3.12-slim
ARG APP_VERSION=1.0.0
ARG GIT_SHA=local
LABEL org.opencontainers.image.source="https://github.com/BinaryBhakti/devops-homework" \
      org.opencontainers.image.title="incidentdesk-backend" \
      org.opencontainers.image.revision="${GIT_SHA}"
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 APP_VERSION=${APP_VERSION}
WORKDIR /app
# bind-mount the wheels instead of COPYing them: a COPY layer would keep them in the image
# forever, even after an `rm` in a later layer
RUN --mount=type=bind,from=build,source=/wheels,target=/wheels \
    pip install --no-cache-dir --no-index --root-user-action=ignore /wheels/* \
 && useradd --create-home --uid 10001 appuser
COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app
USER 10001
EXPOSE 8000
# A real HTTP check of /health, done with bash's /dev/tcp instead of starting a Python
# interpreter: on a CPU-starved host `python -c urllib...` alone took longer than the timeout.
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=3 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8000 && printf 'GET /health HTTP/1.0\\r\\n\\r\\n' >&3 && grep -q '\"UP\"' <&3"]
# Alembic is the single source of truth for the schema: migrate, then serve.
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers"]
