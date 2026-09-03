# ---- Python Hello World --------------------------------------------------
FROM python:3.12-slim

WORKDIR /app

# Don't write .pyc files, and stream logs straight to the console
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install dependencies first so this layer stays cached
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

# Create and switch to a non-root user
RUN useradd --create-home appuser && chown -R appuser /app
USER appuser

CMD ["python", "app.py"]
