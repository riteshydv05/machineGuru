# MachineGuru

> Industrial Retrieval-Augmented Generation (RAG) for offline, on-device operation on NVIDIA Jetson Orin Nano.

[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![React](https://img.shields.io/badge/React-19-61DAFB?logo=react)](https://react.dev)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://docker.com)
[![Jetson](https://img.shields.io/badge/Jetson-Orin-76B900?logo=nvidia)](https://www.nvidia.com/jetson)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## Quick Start

```bash
cp .env.example .env
docker compose up -d
docker exec machine-guru-ollama ollama pull llama3.2:1b
```

Open **http://localhost** in your browser.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Client Browser (React SPA)               │
└────────────────────────────┬────────────────────────────────┘
                             │ HTTP / SSE
┌────────────────────────────▼────────────────────────────────┐
│                   Nginx Reverse Proxy (port 80)              │
│  • Static files • API proxy • Rate limiting • Security     │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                    FastAPI Backend (port 8000)                │
│  ┌─────────┐ ┌──────────┐ ┌─────────┐ ┌────────────────┐   │
│  │ Health  │ │  Query   │ │ Ingest  │ │   Upload       │   │
│  └────┬────┘ └────┬─────┘ └────┬────┘ └───────┬────────┘   │
│       │           │            │               │            │
│  ┌────▼───────────▼────────────▼───────────────▼─────────┐  │
│  │              Use Cases (Business Logic)                │  │
│  └────┬───────────┬────────────┬───────────────┬─────────┘  │
│       │           │            │               │            │
│  ┌────▼───────────▼────────────▼───────────────▼─────────┐  │
│  │           Infrastructure (Adapters)                    │  │
│  │  Qdrant • Ollama • SentenceTransformers • PyMuPDF     │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼───────┐   ┌───────▼───────┐   ┌────────▼────────┐
│  Qdrant (VecDB)│   │ Ollama (LLM) │   │  Filesystem     │
│  port 6333     │   │ port 11434   │   │  uploads/       │
└───────────────┘   └───────────────┘   └─────────────────┘
```

### Clean Architecture Layers

| Layer | Tech | Responsibility |
|-------|------|----------------|
| **Domain** | Pydantic models | Business entities and value objects |
| **Use Cases** | Python classes | Orchestration of business logic |
| **API** | FastAPI routes | HTTP adapters, request/response schemas |
| **Infrastructure** | Adapters | Qdrant, Ollama, SentenceTransformers, PyMuPDF |

---

## Features

- **RAG pipeline** — Ingest PDF/DOCX/TXT, chunk, embed, query, generate
- **Citation rendering** — Interactive inline `[Source N]` badges with hover previews
- **Streaming** — Server-Sent Events (SSE) for real-time token output
- **Jetson optimized** — Flash Attention 2, FP16, GPU acceleration
- **Fully offline** — No internet required after initial model download
- **Production monitoring** — Prometheus metrics, health checks, stats endpoint, Grafana dashboards
- **Caching** — LRU caches for embeddings (24h TTL) and query results (5min TTL)
- **Concurrency control** — Semantic rate limiters for LLM, embeddings, Qdrant
- **Memory management** — Auto-unload idle models, aggressive GC at thresholds
- **Clean Architecture** — Strict layer separation with dependency injection
- **Graceful shutdown** — SIGTERM handling, in-flight request draining
- **Structured logging** — Loguru with JSON output, file rotation, request IDs
- **Rate limiting** — Token-bucket at application layer + nginx rate limiting
- **Health checks** — Multi-service health monitoring with recovery

---

## Project Structure

```
MachineGuru/
├── backend/
│   ├── api/v1/               # FastAPI routes and Pydantic schemas
│   │   ├── endpoints/        #  Health, Query, Ingest, Upload
│   │   └── schemas/          #  Request/response models
│   ├── core/                 # Config, cache, metrics, logging, exceptions
│   ├── domain/               # Entities (Document) and value objects (Chunk, Query)
│   ├── infrastructure/       # Adapters: Qdrant, Ollama, embedding, document processing
│   ├── use_cases/            # Business logic: query, ingestion, health, upload
│   └── tests/                # Pytest test suite
├── frontend/
│   ├── src/                  # React app with TypeScript
│   │   ├── components/       # UI (chat, citations, upload, layout)
│   │   ├── hooks/            # useChat, useTheme
│   │   ├── services/         # Axios API + SSE streaming
│   │   └── types/            # TypeScript definitions
│   ├── nginx.conf            # Production nginx reverse proxy
│   └── Dockerfile            # Multi-stage build
├── deploy/
│   ├── prometheus/           # Prometheus config + alerting rules
│   └── grafana/              # Grafana dashboards + datasources
├── scripts/
│   ├── healthcheck.sh        # Multi-service health checker
│   ├── watchdog.sh           # Auto-recovery watchdog
│   └── backup.sh             # Volume backup script
├── docs/                     # Production documentation
├── docker-compose.yml        # Multi-service orchestration
└── Makefile                  # Build/run/test/monitor shortcuts
```

---

## Configuration

All configuration is via environment variables (`.env` file). See [`.env.example`](.env.example) for all options.

### Key Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `LLM_MODEL` | `llama3.2:1b` | Ollama model for answer generation |
| `EMBEDDING_MODEL` | `multilingual-e5-small` | SentenceTransformer for embeddings |
| `DEVICE` | `cpu` | `cuda` for Jetson GPU acceleration |
| `USE_FP16` | `false` | Half-precision embedding inference |
| `USE_FLASH_ATTENTION` | `false` | Flash Attention 2 (Ampere+ GPUs) |
| `CHUNK_SIZE` | `512` | Document chunk size (characters) |
| `TOP_K` | `5` | Number of chunks retrieved per query |
| `BATCH_SIZE` | `64` | Embedding batch size |
| `MEMORY_BUDGET_MB` | `2048` | Max memory before aggressive GC |
| `JSON_LOGGING` | `false` | Enable JSON structured log output |
| `LOG_LEVEL` | `INFO` | Log verbosity (DEBUG, INFO, WARNING) |

### Production Settings

```env
DEBUG=false
CORS_ORIGINS=["https://yourdomain.com"]
JSON_LOGGING=true
LOG_LEVEL=INFO
DEVICE=cuda
USE_FP16=true
USE_FLASH_ATTENTION=true
```

---

## Production Deployment

### Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Docker & Compose | 24+ / 2.20+ | Container orchestration |
| NVIDIA Container Toolkit | 1.14+ | GPU passthrough (Jetson) |
| NVIDIA Jetson Orin Nano | Any | Target hardware |
| 16 GB+ RAM | — | For models + Qdrant |
| 20 GB+ disk | — | Docker images + storage |

### Production Setup

```bash
# 1. Configure
cp .env.example .env
# Edit .env: set DEVICE=cuda, USE_FP16=true, CORS_ORIGINS

# 2. Build and start
docker compose build
docker compose up -d

# 3. Pull AI models
docker exec machine-guru-ollama ollama pull llama3.2:1b
docker exec machine-guru-ollama ollama pull multilingual-e5-small

# 4. Verify
curl http://localhost/api/v1/health
```

### Production Checklist

- `DEBUG=false` in `.env`
- `CORS_ORIGINS` restricted to your domain
- TLS termination configured (reverse proxy with certbot)
- Regular backups scheduled via `make backup`
- Resource limits tuned in `docker-compose.yml`
- Monitoring set up (Prometheus + Grafana)
- `JSON_LOGGING=true` for log aggregation
- Health check alerts configured

---

## Monitoring

### Prometheus Metrics

The backend exposes metrics at `/metrics` (Prometheus format):

```prometheus
# HELP machineguru_query_total Total queries processed
# TYPE machineguru_query_total counter
machineguru_query_total{status="ok"} 42.0

# HELP machineguru_query_duration_seconds Query execution time
# TYPE machineguru_query_duration_seconds histogram
```

### Available Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `machineguru_query_total` | Counter | Total queries by status |
| `machineguru_query_duration_seconds` | Histogram | Query latency distribution |
| `machineguru_query_tokens_total` | Counter | Tokens generated by LLM |
| `machineguru_query_cache_hits_total` | Counter | Query cache hits |
| `machineguru_ingestion_total` | Counter | Documents ingested |
| `machineguru_ingestion_duration_seconds` | Histogram | Ingestion time |
| `machineguru_memory_mb` | Gauge | Process RSS memory |
| `machineguru_gpu_memory_mb` | Gauge | GPU memory usage |
| `machineguru_gpu_util_percent` | Gauge | GPU utilization |
| `machineguru_concurrent_llm` | Gauge | Concurrent LLM requests |
| `machineguru_request_total` | Counter | HTTP requests by endpoint |
| `machineguru_request_duration_seconds` | Histogram | HTTP request latency |

### Stats Endpoint

```bash
curl http://localhost:8000/api/v1/stats
```

Returns memory, CPU, GPU, model status, cache hit rates, and concurrency stats.

---

## Logging

Structured logging via [Loguru](https://github.com/Delgan/loguru):

- **Console**: Colorized human-readable output (default)
- **JSON**: Machine-readable for log aggregation (`JSON_LOGGING=true`)
- **File rotation**: 10 MB per file, 30-day retention, gzip compressed
- **Request IDs**: Every request tagged with `X-Request-ID` for correlation
- **Slow request warnings**: Logged when response exceeds 1 second

### Log Levels

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Set to `DEBUG` for development verbosity |
| `JSON_LOGGING` | `false` | Set to `true` for JSON output |

---

## Error Handling

Structured error responses with unique error IDs:

```json
{
  "error_id": "uuid",
  "error_code": "ERROR_CODE",
  "message": "Human-readable message",
  "detail": "Optional debug details"
}
```

| Code | Status | Description |
|------|--------|-------------|
| `INVALID_FILE_TYPE` | 400 | Unsupported file extension |
| `FILE_TOO_LARGE` | 413 | File exceeds 50 MB limit |
| `QUERY_VALIDATION_ERROR` | 422 | Invalid query |
| `NOT_FOUND` | 404 | Resource not found |
| `LLM_ERROR` | 503 | LLM generation failed |
| `QDRANT_ERROR` | 503 | Qdrant operation failed |
| `EMBEDDING_ERROR` | 500 | Embedding generation failed |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `INTERNAL_ERROR` | 500 | Unhandled exception |

Detail is only included when `DEBUG=true`.

---

## Automatic Restart

Docker containers are configured with `restart: unless-stopped`. For additional resilience:

```bash
# Watchdog with auto-recovery
./scripts/watchdog.sh --interval 30

# As systemd service (see docs/DEPLOYMENT.md)
sudo cp deploy/machine-guru-watchdog.service /etc/systemd/system/
sudo systemctl enable --now machine-guru-watchdog
```

---

## Offline Deployment

For air-gapped environments:

```bash
# On internet-connected machine
docker compose build
make offline-save           # Exports images to ./offline/

# Copy ./offline/ to target machine

# On offline machine
make offline-load
docker compose up -d
docker exec machine-guru-ollama ollama pull llama3.2:1b
```

See [Offline Guide](docs/INSTALL.md#3-offline-deployment) for model pre-download.

---

## Documentation

- **[Installation Guide](docs/INSTALL.md)** — Detailed setup for Jetson, Docker, development, and offline
- **[API Reference](docs/API.md)** — All endpoints, schemas, and examples
- **[Architecture](docs/ARCHITECTURE.md)** — Layer diagrams, data flow, component design
- **[Deployment Guide](docs/DEPLOYMENT.md)** — Production deployment, TLS, scaling
- **[Monitoring Guide](docs/MONITORING.md)** — Prometheus, Grafana, alerting
- **[Improvements](docs/IMPROVEMENTS.md)** — Future roadmap and technical debt

---

## Development

```bash
# Backend
cd backend && python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
make dev-backend

# Frontend
cd frontend && npm install && npm run dev

# Infrastructure (separate terminal)
docker compose up qdrant ollama -d

# Tests
make test
```

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/health` | Service health check |
| `POST` | `/api/v1/ingest` | Upload and ingest a document |
| `POST` | `/api/v1/query` | Ask a question |
| `POST` | `/api/v1/query/stream` | Stream answer via SSE |
| `POST` | `/api/v1/upload` | Upload without ingesting |
| `GET` | `/api/v1/stats` | Runtime diagnostics |
| `GET` | `/metrics` | Prometheus metrics |

---

## License

MIT
