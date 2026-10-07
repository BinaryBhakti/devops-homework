# ---- stage 1: dependencies into a virtualenv ----
FROM python:3.12-slim AS builder
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y pip   # the venv only has to run the app, not install anything

# ---- stage 2: runtime ----
FROM python:3.12-slim
ARG GIT_SHA=local
LABEL org.opencontainers.image.source="https://github.com/BinaryBhakti/devops-homework" \
      org.opencontainers.image.description="Homework 16 DevSecOps demo (Session 17)"
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    GIT_SHA=${GIT_SHA}
# Pick up Debian security fixes published after the base image was built, drop the base
# image's own pip (a package manager the runtime never uses, and the only fixable CVEs Trivy
# found here), and create the unprivileged user.
RUN apt-get update && apt-get upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/* \
 && python -m pip uninstall -y pip \
 && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY app ./app
USER 10001
EXPOSE 5001
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5001/health',timeout=2).status==200 else 1)"
# --worker-tmp-dir /dev/shm: gunicorn's heartbeat files must not need a writable root filesystem
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "2", "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "app.app:app"]
