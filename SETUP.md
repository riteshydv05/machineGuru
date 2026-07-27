# MachineGuru — Setup & Deployment Guide

Complete guide for setting up and running MachineGuru on **macOS (development)** and **NVIDIA Jetson Orin (production)**.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Clone & Environment File](#2-clone--environment-file)
3. [Python Virtual Environment](#3-python-virtual-environment)
4. [Backend — Install Dependencies](#4-backend--install-dependencies)
5. [Qdrant Vector Database](#5-qdrant-vector-database)
6. [Ollama LLM Server](#6-ollama-llm-server)
7. [Frontend — Build](#7-frontend--build)
8. [Start All Services](#8-start-all-services)
9. [Stop All Services](#9-stop-all-services)
10. [Jetson Orin — Extra Steps](#10-jetson-orin--extra-steps)
11. [Verify the Deployment](#11-verify-the-deployment)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

### macOS (development)

| Tool | Minimum Version | Install |
|---|---|---|
| Python | 3.10+ | `brew install python@3.11` |
| Node.js | 20 LTS | `brew install node@20` |
| npm | 9+ | bundled with Node.js |
| curl | any | pre-installed |

### Jetson Orin (production)

| Tool | Minimum Version | Notes |
|---|---|---|
| JetPack | 5.x or 6.x | Ubuntu 20.04 / 22.04 ARM64 |
| Python | 3.10+ | `sudo apt install python3.10 python3.10-venv` |
| Node.js | 20 LTS | see § 10 |
| CUDA | 11.8+ | included in JetPack |

> **Jetson**: Run `./deploy/jetson_setup.sh` **before** anything else — it installs the JetPack-specific PyTorch wheel. See [§ 10](#10-jetson-orin--extra-steps).

---

## 2. Clone & Environment File

```bash
# Clone the repository
git clone <your-repo-url> Machine_Guru
cd Machine_Guru

# Create your local .env from the example
cp .env.example .env
```

### Key `.env` values to review

Open `.env` and verify these settings match your environment:

```dotenv
# Ports
BACKEND_PORT=8001
FRONTEND_PORT=5173

# ── Ollama ─────────────────────────────────────────────────
# Jetson Orin (Docker bridge):
OLLAMA_BASE_URL=http://172.17.0.1:11434
# macOS / local dev — override to:
# OLLAMA_BASE_URL=http://localhost:11434

LLM_MODEL=llama3.2:1b          # fixed — do not change for Jetson
NUM_CTX=1024                    # keeps ~500 MB RAM free on Jetson

# ── Qdrant ─────────────────────────────────────────────────
QDRANT_HOST=localhost
QDRANT_PORT=6333
QDRANT_STORAGE_PATH=./storage/qdrant

# ── Storage ────────────────────────────────────────────────
UPLOAD_DIR=./storage/uploads
LOG_DIR=./logs
```

> **Never commit `.env`** — it is listed in `.gitignore`.

---

## 3. Python Virtual Environment

All Python commands must be run from the **`backend/`** directory.

### Standard (macOS / Ubuntu with venv available)

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate

# Confirm you are inside the venv
which python   # should print .../backend/.venv/bin/python
```

---

### If `python3 -m venv` fails — `ensurepip not available`

This error is common on **Jetson Cloud Lab** and restricted Ubuntu environments where `python3.10-venv` is not in the apt repositories.

Work through these fallbacks in order until one succeeds:

#### Fallback 1 — install the generic venv package (no version suffix)

```bash
sudo apt install python3-venv -y
python3 -m venv .venv
source .venv/bin/activate
```

#### Fallback 2 — use `virtualenv` via pip (no apt required)

`virtualenv` ships its own `pip` and does not depend on `ensurepip`:

```bash
pip3 install --user virtualenv
python3 -m virtualenv .venv
source .venv/bin/activate
```

#### Fallback 3 — bootstrap venv without ensurepip, then install pip manually

```bash
python3 -m venv .venv --without-pip
source .venv/bin/activate

# Install pip into the empty venv
curl -sS https://bootstrap.pypa.io/get-pip.py | python
```

#### Fallback 4 — skip the venv entirely (install into user site-packages)

Use this only when venv creation is completely blocked (e.g. read-only filesystem):

```bash
# Install directly to user site — no activation needed
pip3 install --user -r requirements.txt

# Verify fastapi is reachable
python3 -c "import fastapi; print(fastapi.__version__)"
```

> `start.sh` checks for `backend/.venv/bin/activate` first. If it does not exist, it falls back to system/user packages automatically, so the app will still start correctly with Fallback 4.

---

> The `start.sh` script automatically activates `backend/.venv/bin/activate` on every run — you do not need to activate manually when using `start.sh`.

---

## 4. Backend — Install Dependencies

```bash
# Make sure you are inside backend/ with the venv active
cd backend
source .venv/bin/activate

# Upgrade pip first
pip install --upgrade pip

# Install dependencies
# --no-cache-dir  → do NOT write to ~/.cache/pip (saves disk on Jetson)
# TMPDIR override → redirect /tmp unpacking to home dir if /tmp is small
TMPDIR=~/tmp pip install --no-cache-dir -r requirements.txt
```

> If you still run out of space, install packages one group at a time:
> ```bash
> pip install --no-cache-dir fastapi uvicorn pydantic pydantic-settings sse-starlette
> pip install --no-cache-dir qdrant-client httpx requests
> pip install --no-cache-dir pymupdf python-docx rank-bm25
> pip install --no-cache-dir Pillow psutil loguru python-multipart python-dotenv
> ```

### What gets installed (minimal — space-optimised for Jetson)

| Category | Packages |
|---|---|
| Web framework | `fastapi`, `uvicorn`, `pydantic`, `sse-starlette` |
| Vector DB client | `qdrant-client`, `httpx` |
| Document processing | `pymupdf`, `python-docx` |
| HTTP (Ollama REST) | `requests` |
| Image processing | `Pillow` |
| Retrieval | `rank-bm25` |
| Monitoring | `psutil` |
| Utilities | `loguru`, `python-dotenv`, `python-multipart` |

### Intentionally excluded (too large / not needed)

| Package | Reason |
|---|---|
| `torch` | JetPack installs the CUDA wheel via `jetson_setup.sh`; not needed for Ollama embeddings |
| `sentence-transformers` | Not needed when `USE_OLLAMA_EMBEDDINGS=true` (default) |
| `numpy` | Pulled in by JetPack / torch; `OllamaEmbeddingModel` uses pure-Python math |
| `pytesseract` | Optional OCR — `image_extractor.py` silently skips if missing |
| `prometheus-client` | Optional metrics — `main.py` disables `/metrics` endpoint if missing |

### Optional extras (install manually if needed)

```bash
# OCR support
pip install --no-cache-dir pytesseract

# Prometheus /metrics endpoint
pip install --no-cache-dir "prometheus-client>=0.21.0,<1.0.0"

# Local SentenceTransformers embeddings (x86_64 dev machines only)
pip install --no-cache-dir sentence-transformers
```



---

## 5. Qdrant Vector Database

Qdrant is the vector database used for semantic search.

### Download the binary (first time only)

```bash
# From the project root
mkdir -p qdrant_bin

# macOS (Apple Silicon / M-series)
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-aarch64-apple-darwin.tar.gz \
  | tar xz -C qdrant_bin/

# macOS (Intel x86_64)
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-apple-darwin.tar.gz \
  | tar xz -C qdrant_bin/

# Linux x86_64
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-musl.tar.gz \
  | tar xz -C qdrant_bin/

# Linux ARM64 (Jetson Orin)
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-aarch64-unknown-linux-musl.tar.gz \
  | tar xz -C qdrant_bin/

# Make it executable
chmod +x qdrant_bin/qdrant
```

> `start.sh` starts Qdrant automatically from `qdrant_bin/qdrant`. If you already have Qdrant running elsewhere, pass `--no-qdrant` to `start.sh`.

### Storage directory

Qdrant data is persisted at `./storage/qdrant` (configurable via `QDRANT_STORAGE_PATH` in `.env`). This directory is created automatically on first run.

---

## 6. Ollama LLM Server

> **Jetson Orin**: Ollama is pre-installed and already running on the board. The model `llama3.2:1b` is pre-loaded. **Skip this section entirely** — do not run `ollama pull` or restart the service.

### macOS / Linux — Install Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### Start the server

```bash
ollama serve
```

### Pull the required model

```bash
# Only approved model — must match LLM_MODEL in .env
ollama pull llama3.2:1b
```

### Verify

```bash
curl http://localhost:11434/api/tags
# Should list llama3.2:1b in the models array
```

---

## 7. Frontend — Build

The React frontend is built with Vite + TypeScript. After building, **FastAPI serves the compiled files directly** — no separate frontend server is needed in production.

```bash
cd frontend

# Install Node.js dependencies (first time, or after package.json changes)
npm install

# Production build — outputs to frontend/dist/
npm run build
```

The build creates:

```
frontend/dist/
├── index.html          ← entry point (served by FastAPI catch-all)
├── favicon.svg
└── assets/
    ├── index-[hash].js
    └── index-[hash].css
```

FastAPI automatically picks up `frontend/dist/` when the directory exists (see `backend/main.py`). To deploy new frontend code, just re-run `npm run build` — no backend restart needed.

### Development mode (optional)

For live-reload during development, skip the build and use the Vite dev server instead:

```bash
cd frontend
npm run dev
# Vite proxies all /api/* requests to localhost:8001 automatically
```

---

## 8. Start All Services

From the **project root**:

```bash
# Make scripts executable (first time only)
chmod +x start.sh stop.sh deploy/*.sh

# Production: backend serves both the API and the built React frontend
./start.sh --no-frontend
```

### Start script flags

| Flag | Effect |
|---|---|
| *(none)* | Starts Qdrant + Backend + Vite dev server |
| `--no-frontend` | Starts Qdrant + Backend only — use this when React is built and served by FastAPI |
| `--no-qdrant` | Skip Qdrant startup (use if already running externally) |
| `--dev` | Explicitly force Vite dev server (default behaviour without `--no-frontend`) |
| `--prod-serve` | Use nginx static server (requires nginx configured to proxy `/api/`) |

### Recommended for production

```bash
./start.sh --no-frontend
```

The backend is now accessible at **`http://localhost:8001`** and serves both the REST API and the React UI.

### Service startup sequence

```
[1/8] Validating environment
[2/8] Creating directories
[3/8] Cleaning up old processes
[4/8] Checking Ollama
[5/8] Starting Qdrant         → http://localhost:6333
[6/8] Starting Backend        → http://localhost:8001
[7/8] Starting Frontend       → (skipped with --no-frontend)
[8/8] Verifying services
```

### URLs after startup

| Service | URL |
|---|---|
| **App (React UI)** | `http://localhost:8001` |
| **API health** | `http://localhost:8001/api/v1/health` |
| **API docs** (`DEBUG=true` only) | `http://localhost:8001/docs` |
| **Qdrant dashboard** | `http://localhost:6333/dashboard` |
| **Prometheus metrics** | `http://localhost:8001/metrics` |

---

## 9. Stop All Services

```bash
./stop.sh
```

### Stop script flags

| Flag | Effect |
|---|---|
| `--force` | Send SIGKILL if SIGTERM doesn't exit within 10 s |
| `--stop-ollama` | Also stop the Ollama server |

Graceful shutdown order: Frontend → Backend → Qdrant.

---

## 10. Jetson Orin — Extra Steps

### 10a. One-time Jetson setup (run before everything else)

```bash
chmod +x deploy/jetson_setup.sh
./deploy/jetson_setup.sh
```

This script:
- Detects your JetPack version (5.x / 6.x)
- Installs the CUDA-enabled PyTorch wheel from the NVIDIA Jetson index
- Installs `jtop`, CUDA samples, and ARM64-specific system packages
- Falls back gracefully in Cloud Lab environments where `apt` is restricted

### 10b. Full automated install (after jetson_setup.sh)

```bash
chmod +x deploy/install.sh
./deploy/install.sh
```

This runs all setup steps automatically:
1. Detects environment (Jetson Native / Cloud Lab / macOS)
2. Installs system packages via `apt` (if available)
3. Installs Node.js 20 LTS
4. Sets up Python venv and installs `requirements.txt`
5. Builds the frontend (`npm install && npm run build`)
6. Creates all storage directories
7. Auto-configures `.env` (`DEVICE=cuda`, `OLLAMA_BASE_URL`)

### 10c. Ollama on Jetson

```
⚠  DO NOT run:  ollama pull         (models are already loaded)
⚠  DO NOT run:  ollama serve        (server is already running)
⚠  DO NOT change LLM_MODEL         (llama3.2:1b is the only permitted model)
```

Ollama is reachable from all Docker containers via the bridge IP:

```
http://172.17.0.1:11434
```

This is already set as the default in `config.py` and `.env`.

### 10d. Start on Jetson

```bash
# If Qdrant is also pre-running on the board:
./start.sh --no-frontend --no-qdrant

# If you want start.sh to manage Qdrant:
./start.sh --no-frontend
```

---

## 11. Verify the Deployment

### Quick health check

```bash
curl http://localhost:8001/api/v1/health
```

Expected response:

```json
{
  "status": "ok",
  "qdrant": { "status": "ok", "point_count": 0 },
  "ollama": { "status": "ok", "model": "llama3.2:1b" }
}
```

### Full preflight check

```bash
chmod +x deploy/preflight.sh
./deploy/preflight.sh
```

### Full verification script

```bash
chmod +x deploy/verify_installation.sh
./deploy/verify_installation.sh
```

### Test the LLM endpoint

```bash
curl -s -X POST http://localhost:8001/api/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"query": "What is MachineGuru?", "session_id": "test"}' | python3 -m json.tool
```

### Check live logs

```bash
tail -f logs/backend.log    # FastAPI + Uvicorn
tail -f logs/qdrant.log     # Qdrant vector DB
tail -f logs/frontend.log   # Vite dev server (only if used)
```

---

## 12. Troubleshooting

### Backend fails to start

```bash
# View the last 50 lines of the backend log
tail -50 logs/backend.log

# Check if port 8001 is already occupied
lsof -i :8001           # macOS
ss -tulpn | grep 8001   # Linux
```

### `ModuleNotFoundError` on startup

The virtual environment is not activated, or `requirements.txt` was not installed:

```bash
cd backend
source .venv/bin/activate
pip install -r requirements.txt
```

### Frontend not loading (404 on `/`)

The React build is missing. Rebuild and restart:

```bash
cd frontend && npm run build
cd ..
./stop.sh && ./start.sh --no-frontend
```

### Qdrant not starting

```bash
# Confirm the binary exists and is executable
ls -la qdrant_bin/qdrant

# Check storage path permissions
ls -la storage/qdrant/

# Read qdrant startup logs
cat logs/qdrant.log
```

### Ollama unreachable — macOS

```bash
# Start Ollama
ollama serve

# Verify it responds
curl http://localhost:11434
```

Update `.env`:
```dotenv
OLLAMA_BASE_URL=http://localhost:11434
```

### Ollama unreachable — Jetson

The Docker bridge IP may differ from `172.17.0.1`. Find the actual gateway:

```bash
ip route | grep docker
# Example output: 172.17.0.0/16 dev docker0 ... src 172.17.0.1
```

Update `OLLAMA_BASE_URL` in `.env` if the IP is different, then restart the backend.

### Port conflicts on restart

```bash
./stop.sh --force
sleep 3
./start.sh --no-frontend
```

---

## Quick Reference Card

```bash
# ── First-time setup ───────────────────────────────────────────
cp .env.example .env                        # configure environment

cd backend
python3 -m venv .venv                       # create virtual environment
source .venv/bin/activate                   # activate it
pip install --upgrade pip
pip install -r requirements.txt             # install backend deps
cd ..

cd frontend
npm install                                 # install JS deps
npm run build                               # build React for production
cd ..

# ── Jetson only (run ONCE before the steps above) ──────────────
./deploy/jetson_setup.sh                    # CUDA PyTorch wheel
./deploy/install.sh                         # full automated install

# ── Daily workflow ─────────────────────────────────────────────
./start.sh --no-frontend                    # start (backend serves UI)
./stop.sh                                   # stop everything

# ── Logs ───────────────────────────────────────────────────────
tail -f logs/backend.log
tail -f logs/qdrant.log

# ── Health ─────────────────────────────────────────────────────
curl http://localhost:8001/api/v1/health
./deploy/healthcheck.sh
./deploy/verify_installation.sh
```
