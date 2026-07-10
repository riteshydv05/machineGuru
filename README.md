# MachineGuru

> **Industrial Retrieval-Augmented Generation (RAG)** — Fully offline, on-device AI for NVIDIA Jetson Orin.  
> Ask questions about your machine manuals, maintenance records, and technical documents. No cloud. No internet required.

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![React](https://img.shields.io/badge/React-19-61DAFB?logo=react)](https://react.dev)
[![Jetson](https://img.shields.io/badge/Jetson-Orin-76B900?logo=nvidia)](https://www.nvidia.com/jetson)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## ⚡ Quickstart (3 Commands)

```bash
# Clone the repository
git clone <repo-url> MachineGuru && cd MachineGuru

# Install everything (system deps, Python venv, Node, Ollama, models)
./deploy/install.sh

# Start all services
./start.sh
```

Open **http://localhost:5173** in your browser.

> **Jetson Orin?** Run `./deploy/jetson_setup.sh` before `./deploy/install.sh` to enable GPU acceleration.

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  React Frontend (port 5173)                  │
│              TypeScript · Vite · TailwindCSS                 │
└────────────────────────────┬────────────────────────────────┘
                             │ HTTP / SSE
┌────────────────────────────▼────────────────────────────────┐
│              FastAPI Backend (port 8001)                     │
│  API → Use Cases → Infrastructure                           │
│  Clean Architecture · Loguru · Prometheus Metrics           │
└────────┬──────────────────┬──────────────────┬─────────────┘
         │                  │                  │
┌────────▼───────┐ ┌────────▼───────┐ ┌────────▼────────┐
│ Qdrant (6333)  │ │ Ollama (11434) │ │  Local Storage  │
│ Vector DB      │ │ LLM inference  │ │  storage/       │
│ storage/qdrant │ │ Native install │ │  uploads/       │
└────────────────┘ └────────────────┘ └─────────────────┘
```

### Key Design Decisions

| Decision | Reason |
|----------|--------|
| **Ollama installed natively** (not Docker) | Docker Ollama image has no Jetson CUDA support |
| **Qdrant binary bundled** in `qdrant_bin/` | No internet required after first install |
| **SentenceTransformers local** | Embeddings run on-device, no API calls |
| **Storage in `storage/`** | Runtime data separated from source code |
| **PID files in `storage/temporary/`** | Reliable start/stop without `lsof` |

---

## 📁 Project Structure

```
MachineGuru/
├── backend/                  # FastAPI application (Python 3.10+)
│   ├── api/v1/               # HTTP layer (routes, schemas)
│   ├── core/                 # Config, cache, logging, exceptions
│   ├── domain/               # Business entities (Document, Chunk)
│   ├── infrastructure/       # Adapters (Qdrant, Ollama, embedding)
│   ├── use_cases/            # Business logic (query, ingest, upload)
│   ├── tests/                # Pytest test suite
│   ├── main.py               # FastAPI app entry point
│   ├── requirements.txt      # Python dependencies
│   └── .venv/                # Python virtual environment (gitignored)
│
├── frontend/                 # React 19 + Vite + TypeScript
│   ├── src/                  # Application source
│   │   ├── components/       # UI components
│   │   ├── hooks/            # React hooks
│   │   ├── services/         # API client + SSE streaming
│   │   └── types/            # TypeScript types
│   ├── dist/                 # Production build (gitignored)
│   └── package.json          # Node dependencies
│
├── storage/                  # ALL runtime data (gitignored)
│   ├── uploads/              # Uploaded documents
│   ├── qdrant/               # Qdrant vector database files
│   ├── cache/                # Query and embedding cache
│   ├── embeddings/           # Cached embedding vectors
│   ├── history/              # Chat history
│   └── temporary/            # PID files, temp files
│
├── logs/                     # Rotating log files (gitignored)
│
├── qdrant_bin/               # Qdrant native binary (gitignored)
│
├── deploy/                   # Deployment automation
│   ├── install.sh            # Full automated install
│   ├── update.sh             # Pull and redeploy
│   ├── jetson_setup.sh       # NVIDIA Jetson GPU setup
│   ├── healthcheck.sh        # Service health verification
│   └── verify_installation.sh # End-to-end functional test
│
├── scripts/                  # Operational scripts
│   ├── healthcheck.sh        # Lightweight health check
│   ├── watchdog.sh           # Auto-recovery watchdog
│   └── backup.sh             # Data backup
│
├── docs/                     # Technical documentation
│
├── start.sh                  # Start all services
├── stop.sh                   # Stop all services
├── docker-compose.yml        # Docker deployment (non-Jetson)
├── Makefile                  # Development shortcuts
├── .env.example              # Environment template (copy to .env)
└── .env                      # Your local config (gitignored)
```

See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for detailed descriptions.

---

## ⚙️ Configuration

Copy `.env.example` to `.env` and edit:

```bash
cp .env.example .env
nano .env
```

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LLM_MODEL` | `llama3.2:1b` | Ollama model for answer generation |
| `EMBEDDING_MODEL` | `multilingual-e5-small` | Local embedding model |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Ollama server URL |
| `QDRANT_HOST` | `localhost` | Qdrant host |
| `BACKEND_PORT` | `8001` | Backend API port |
| `DEVICE` | `cpu` | `cuda` for Jetson GPU |
| `USE_FP16` | `false` | `true` for Jetson |
| `USE_FLASH_ATTENTION` | `false` | `true` for Jetson Orin |
| `DEBUG` | `false` | Enables `/docs` API explorer |
| `LOG_LEVEL` | `INFO` | `DEBUG` for verbose output |
| `UPLOAD_DIR` | `./storage/uploads` | Where uploads are stored |
| `LOG_DIR` | `./logs` | Where logs are written |

### Jetson Production Settings

```env
DEBUG=false
DEVICE=cuda
USE_FP16=true
USE_FLASH_ATTENTION=true
JSON_LOGGING=true
LOG_LEVEL=INFO
MEMORY_BUDGET_MB=4096
OLLAMA_BASE_URL=http://localhost:11434
```

---

## 🚀 Deployment

### Native Deployment (Recommended for Jetson)

```bash
# 1. [Jetson only] Enable GPU acceleration
./deploy/jetson_setup.sh

# 2. Install all dependencies
./deploy/install.sh

# 3. Edit environment config
nano .env

# 4. Start services
./start.sh

# 5. Verify everything works
./deploy/verify_installation.sh
```

### Docker Deployment (x86_64 development)

```bash
cp .env.example .env
docker compose up -d
docker exec machine-guru-ollama ollama pull llama3.2:1b
```

> ⚠️ Docker is for x86_64 development only. Jetson requires native deployment because the Ollama Docker image has no Jetson CUDA support.

---

## 🛑 Stopping Services

```bash
./stop.sh          # Graceful shutdown (SIGTERM)
./stop.sh --force  # Force kill if graceful fails
```

---

## 📊 Monitoring

```bash
# Real-time health check
./deploy/healthcheck.sh

# Backend stats (memory, GPU, cache, concurrency)
curl http://localhost:8001/api/v1/stats | python3 -m json.tool

# Prometheus metrics
curl http://localhost:8001/metrics

# Live log tailing
tail -f logs/backend.log
```

---

## 🔌 API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/health` | Service health + Qdrant status |
| `POST` | `/api/v1/ingest` | Upload and ingest a document |
| `POST` | `/api/v1/query` | Ask a question (blocking) |
| `POST` | `/api/v1/query/stream` | Stream answer via SSE |
| `POST` | `/api/v1/upload` | Upload without ingesting |
| `GET` | `/api/v1/stats` | Runtime diagnostics |
| `GET` | `/metrics` | Prometheus metrics |
| `GET` | `/docs` | Swagger UI (DEBUG=true only) |

---

## 🔧 Development

```bash
# Start infrastructure only
docker compose up qdrant -d    # or run qdrant_bin/qdrant natively

# Backend (hot reload)
./start.sh --dev

# Frontend (hot reload with Vite proxy)
cd frontend && npm run dev

# Run backend tests
cd backend && source .venv/bin/activate && pytest -v

# Type-check frontend
cd frontend && npx tsc --noEmit

# Full health check
./deploy/healthcheck.sh --verbose
```

---

## 🐛 Troubleshooting

| Symptom | Solution |
|---------|----------|
| Backend won't start | Check `logs/backend.log` — likely missing `.env` or Qdrant not running |
| `UPLOAD_DIR` errors | Run `./deploy/install.sh` to create storage directories |
| Ollama not reachable | Start it: `ollama serve` or `sudo systemctl start ollama` |
| Model not found | Pull it: `ollama pull llama3.2:1b` |
| CUDA not available | Run `./deploy/jetson_setup.sh` for Jetson GPU setup |
| Port conflict | Change `BACKEND_PORT` in `.env` and restart |
| Qdrant collection missing | Restart backend — it auto-creates the collection on startup |
| `lsof` not found | Install: `sudo apt-get install lsof` |

---

## 📖 Documentation

- [DEPLOYMENT.md](DEPLOYMENT.md) — Native deployment flow
- [JETSON_SETUP.md](JETSON_SETUP.md) — Jetson GPU configuration  
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) — Directory layout
- [docs/API.md](docs/API.md) — Full API reference
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Design diagrams

---

## 📜 License

MIT
