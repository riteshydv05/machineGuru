# ===== Build Stage =====
FROM python:3.12-slim AS build

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ===== Runtime Stage =====
FROM python:3.12-slim AS runtime

LABEL org.opencontainers.image.title="MachineGuru Backend"
LABEL org.opencontainers.image.description="Industrial RAG backend for NVIDIA Jetson"
LABEL org.opencontainers.image.version="0.1.0"
LABEL org.opencontainers.image.source="https://github.com/machine-guru/backend"
LABEL org.opencontainers.image.licenses="MIT"

RUN groupadd -r machineguru && useradd -r -g machineguru -d /app -s /sbin/nologin machineguru

WORKDIR /app

COPY --from=build /install /usr/local

COPY . .

RUN mkdir -p /app/uploads /app/logs && \
    chown -R machineguru:machineguru /app && \
    find /app -type d -exec chmod 755 {} \; && \
    find /app -type f -exec chmod 644 {} \; && \
    chmod 755 /app/main.py

USER machineguru

EXPOSE 8000

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONHASHSEED=42 \
    OLLAMA_NUM_PARALLEL=2 \
    OLLAMA_KEEP_ALIVE=300s

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health', timeout=5)" || exit 1

STOPSIGNAL SIGTERM

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", "--loop", "uvloop", "--limit-concurrency", "16", "--timeout-graceful-shutdown", "30"]
