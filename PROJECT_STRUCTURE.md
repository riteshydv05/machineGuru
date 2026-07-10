# MachineGuru — Project Structure

This document describes every directory and significant file in the repository.

---

## Root Directory

```
MachineGuru/
│
├── .env                      # Local environment config (gitignored — never commit)
├── .env.example              # Environment template with documentation
├── .gitignore                # Comprehensive ignore list
├── .dockerignore             # Docker build context exclusions
│
├── start.sh                  # Start all services (Qdrant → Backend → Frontend)
├── stop.sh                   # Stop all services gracefully
├── docker-compose.yml        # Docker Compose for x86_64 development
├── Makefile                  # Shortcut commands (make help)
│
├── README.md                 # Project overview and quickstart
├── DEPLOYMENT.md             # Production deployment flow
├── JETSON_SETUP.md           # NVIDIA Jetson GPU configuration guide
├── PROJECT_STRUCTURE.md      # This file
├── HOW-TO-RUN.md             # Legacy run instructions (superseded)
│
├── backend/                  # ← Python FastAPI application
├── frontend/                 # ← React 19 + Vite application
├── deploy/                   # ← Deployment automation scripts
├── scripts/                  # ← Operational utility scripts
├── docs/                     # ← Technical documentation
├── storage/                  # ← Runtime data (gitignored, created on install)
├── logs/                     # ← Log files (gitignored, created on startup)
├── qdrant_bin/               # ← Qdrant native binary (gitignored, download separately)
└── config/                   # ← Optional config overrides (gitignored)
```

---

## Backend (`backend/`)

Clean Architecture pattern with strict layer separation.

```
backend/
│
├── main.py                   # FastAPI app factory, middleware, lifespan
├── requirements.txt          # Python dependencies (pinned versions)
├── pytest.ini                # Pytest configuration
├── Dockerfile                # Multi-stage Docker image
├── .venv/                    # Python virtual environment (gitignored)
│
├── api/                      # HTTP adapter layer
│   ├── dependencies.py       # Dependency injection (singleton factories)
│   └── v1/
│       ├── router.py         # Route registration
│       ├── endpoints/        # One file per endpoint group
│       │   ├── health.py     # GET /api/v1/health
│       │   ├── query.py      # POST /api/v1/query, /query/stream
│       │   ├── ingest.py     # POST /api/v1/ingest
│       │   └── upload.py     # POST /api/v1/upload
│       └── schemas/          # Pydantic request/response models
│           ├── health.py     # HealthResponse, ErrorResponse
│           ├── query.py      # QueryRequest, QueryResponse
│           └── ingest.py     # IngestRequest, IngestResponse
│
├── core/                     # Cross-cutting concerns
│   ├── config.py             # Settings class (pydantic-settings, .env aware)
│   ├── logging.py            # Loguru setup (file rotation, JSON mode)
│   ├── exceptions.py         # Domain exception hierarchy
│   ├── cache.py              # LRU caches (embeddings, queries)
│   ├── concurrency.py        # Semaphore limiters (LLM, embedding, Qdrant)
│   ├── rate_limiter.py       # Token-bucket HTTP rate limiter
│   ├── memory.py             # Model registry, idle eviction
│   ├── benchmark.py          # Timing decorators, memory/GPU sampling
│   └── metrics.py            # Prometheus counters, histograms, gauges
│
├── domain/                   # Business entities (no external dependencies)
│   ├── document.py           # Document entity
│   ├── chunk.py              # Chunk value object
│   └── query.py              # Query value object
│
├── infrastructure/           # External service adapters
│   ├── database/
│   │   ├── qdrant_repository.py  # Qdrant async client wrapper
│   │   └── bm25_index.py         # BM25 sparse retrieval index
│   ├── embedding/
│   │   ├── embedding_service.py  # Batch embedding + cache integration
│   │   └── model_loader.py       # SentenceTransformer lazy loader
│   ├── llm/
│   │   └── ollama_service.py     # Ollama async streaming client
│   └── document_processing/
│       ├── pdf_processor.py      # PyMuPDF PDF parser (text + OCR)
│       ├── docx_processor.py     # python-docx DOCX parser
│       └── text_chunker.py       # Semantic chunking with overlap
│
├── use_cases/                # Business logic (orchestrates infrastructure)
│   ├── query.py              # RAG pipeline: embed → search → generate
│   ├── ingestion.py          # Document pipeline: parse → chunk → embed → store
│   ├── upload.py             # File validation and storage
│   ├── health.py             # Multi-service health aggregation
│   └── document_registry.py  # JSON registry of ingested documents
│
└── tests/                    # Pytest test suite
    ├── test_query.py
    ├── test_ingest.py
    └── conftest.py
```

### Data Flow

```
Upload Request
  → upload.py (validate file type, size)
  → storage/uploads/<uuid>.<ext>

Ingest Request (document_id)
  → ingestion.py
  → document_processing/ (parse pages, extract text)
  → text_chunker.py (split into chunks)
  → embedding_service.py (batch encode → cache)
  → qdrant_repository.py (upsert vectors)
  → document_registry.py (record metadata)

Query Request (text)
  → query.py
  → embedding_service.py (encode question → cache)
  → qdrant_repository.py + bm25_index.py (hybrid search)
  → ollama_service.py (stream tokens)
  → SSE response to client
```

---

## Frontend (`frontend/`)

React 19 + TypeScript + Vite + TailwindCSS

```
frontend/
│
├── index.html                # SPA entry point
├── vite.config.ts            # Vite config (dev proxy → localhost:8001)
├── tailwind.config.ts        # TailwindCSS configuration
├── tsconfig.json             # TypeScript configuration
├── package.json              # npm dependencies
├── nginx.conf                # Production nginx config (for Docker)
├── Dockerfile                # Multi-stage: build → nginx serve
│
├── public/                   # Static assets
│
└── src/
    ├── main.tsx              # React root mount
    ├── App.tsx               # Router setup
    ├── index.css             # Global styles
    │
    ├── components/           # Reusable UI components
    │   ├── chat/             # Chat interface, message list, input
    │   ├── upload/           # File upload with drag-and-drop
    │   ├── citations/        # Citation badges with hover preview
    │   └── layout/           # Navigation, sidebar, theme toggle
    │
    ├── hooks/                # React hooks
    │   ├── useChat.ts        # Chat state + SSE streaming
    │   └── useTheme.ts       # Dark/light mode
    │
    ├── services/             # API client
    │   ├── api.ts            # Axios instance + all endpoints
    │   └── streaming.ts      # SSE EventSource wrapper
    │
    ├── pages/                # Route-level components
    │   ├── Chat.tsx          # Main chat page
    │   └── Documents.tsx     # Document management page
    │
    ├── context/              # React context providers
    │
    ├── types/                # TypeScript type definitions
    │   └── index.ts          # Shared types (Message, Document, etc.)
    │
    └── utils/                # Utility functions
```

---

## Deploy (`deploy/`)

```
deploy/
│
├── install.sh            # Full automated install (run once on new system)
│                         # Installs: apt packages, Node, Ollama, Python venv,
│                         #           npm deps, frontend build, storage dirs
│
├── update.sh             # Update existing installation
│                         # Does: git pull, pip reinstall (if changed),
│                         #       npm reinstall (if changed), frontend rebuild
│
├── jetson_setup.sh       # NVIDIA Jetson Orin specific setup
│                         # Does: NVIDIA Container Toolkit, PyTorch Jetson wheel,
│                         #       swap configuration, power mode, .env GPU update
│
├── healthcheck.sh        # Comprehensive health check
│                         # Checks: Python, Node, disk, RAM, GPU,
│                         #         .env, storage, Ollama, Qdrant, Backend,
│                         #         Frontend, ports, model availability
│
├── verify_installation.sh # End-to-end functional verification
│                         # Tests: upload, RAG query, streaming, stats, logs
│
├── grafana/              # Grafana dashboard definitions
│
└── prometheus/           # Prometheus scrape config + alerting rules
```

---

## Scripts (`scripts/`)

```
scripts/
│
├── healthcheck.sh        # Lightweight HTTP health check (used by Docker)
├── watchdog.sh           # Monitors services, auto-restarts if down
└── backup.sh             # Backs up storage/ and .env to timestamped archive
```

---

## Storage (`storage/`)

All runtime data. **Gitignored** — never committed to the repository.
Created automatically by `./deploy/install.sh` and `./start.sh`.

```
storage/
│
├── uploads/              # Files uploaded via /api/v1/upload
│   └── <uuid>.<ext>      # Named with UUID to prevent collisions
│
├── qdrant/               # Qdrant vector database files
│   ├── collection/       # Collection segments
│   └── wal/              # Write-Ahead Log
│
├── cache/                # Persistent cache files (future use)
│
├── embeddings/           # Cached embedding vectors (future use)
│
├── history/              # Chat history / conversation log (future use)
│
├── temporary/            # Short-lived files
│   ├── backend.pid       # Backend process PID (used by stop.sh)
│   ├── qdrant.pid        # Qdrant process PID
│   └── frontend.pid      # Frontend process PID
│
└── models/               # Model download cache (future use)
```

---

## Logs (`logs/`)

**Gitignored** — created by the backend on startup.

```
logs/
│
├── backend.log           # Backend application log (rotating, 10 MB max)
├── qdrant.log            # Qdrant server stdout/stderr
├── frontend.log          # Frontend server stdout/stderr
└── deployment.log        # install.sh / update.sh / jetson_setup.sh log
```

Log files rotate at `LOG_MAX_SIZE_MB` and are retained for `LOG_RETENTION_DAYS` (see `.env`).

---

## Configuration Files

| File | Purpose |
|------|---------|
| `.env.example` | Template — document all variables here |
| `.env` | Your actual config (gitignored) |
| `backend/core/config.py` | Pydantic Settings model — source of truth for types and defaults |
| `frontend/vite.config.ts` | Dev server port + API proxy target |
| `frontend/nginx.conf` | Production nginx (Docker only) |
| `docker-compose.yml` | x86_64 Docker Compose orchestration |

---

## Gitignored Directories

These directories exist on disk but are never committed:

| Path | Reason |
|------|--------|
| `storage/` | All runtime data (uploads, DB, cache) |
| `logs/` | Log files |
| `qdrant_bin/` | Large binary (~50 MB) |
| `qdrant_storage/` | Legacy storage location |
| `snapshots/` | Qdrant snapshots |
| `backend/.venv/` | Python virtual environment |
| `frontend/node_modules/` | npm packages |
| `frontend/dist/` | Built frontend |
| `.env` | Secrets |
| `offline/` | Docker image exports |
| `backups/` | Backup archives |
