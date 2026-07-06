# 🤖 MachineGuru — Complete How-To-Run Guide

> **Last updated:** June 29, 2026  
> Local RAG (Retrieval-Augmented Generation) system using FastAPI + React + Qdrant + Ollama.

---

## 📋 Table of Contents

1. [What This Project Does](#what-this-project-does)
2. [Architecture Overview](#architecture-overview)
3. [Prerequisites](#prerequisites)
4. [Environment Variables](#environment-variables)
   - [Required Variables](#required-variables)
   - [Optional / Advanced Variables](#optional--advanced-variables)
   - [What Is NOT Needed (No MongoDB, No Cloudinary)](#what-is-not-needed)
5. [Quick Start (Local Dev)](#quick-start-local-dev)
6. [Running with Docker](#running-with-docker)
7. [Frontend Pages](#frontend-pages)
8. [API Reference](#api-reference)
9. [Known Issues & Bugs Fixed](#known-issues--bugs-fixed)
10. [What Is Still Missing](#what-is-still-missing)
11. [Troubleshooting](#troubleshooting)

---

## What This Project Does

MachineGuru lets you upload PDF, DOCX, or TXT documents and then chat with them using a local LLM. Everything runs **100% on your machine** — no cloud APIs, no external databases beyond Qdrant.

**Workflow:**
1. Upload a document → it gets chunked, embedded, and stored in Qdrant
2. Ask a question → the system finds the most relevant chunks
3. Ollama generates an answer with `[Source N]` citations

---

## Architecture Overview

```
Browser (React + Vite :5174)
        │
        ▼
FastAPI Backend (:8001)
   ├── /api/v1/health       — system health + Qdrant status
   ├── /api/v1/ingest       — upload + chunk + embed + store
   ├── /api/v1/query        — one-shot RAG query
   ├── /api/v1/query/stream — streaming SSE RAG query
   └── /api/v1/upload       — raw file upload (no embedding)
        │
   ┌────┴────┐
   │         │
Qdrant    Ollama
(:6333)   (:11434)
(vectors) (LLM + embeddings via SentenceTransformers)
```

**No MongoDB. No Redis. No Cloudinary. No S3.** This is a fully self-contained local stack.

---

## Prerequisites

### Required Tools

| Tool | Version | Check | Install |
|---|---|---|---|
| Python | 3.12+ | `python3 --version` | [python.org](https://www.python.org/downloads/) |
| Node.js | 18+ | `node --version` | [nodejs.org](https://nodejs.org/) |
| Ollama | Latest | `ollama --version` | [ollama.com](https://ollama.com) |
| Qdrant | 1.x | see below | Binary or Docker |

### Ollama Models to Pull

```bash
# LLM for answering questions (already on your machine ✅)
ollama pull llama3.2:1b

# Optional: larger / smarter model
ollama pull llama3.2:3b
```

> **Note:** The embedding model (`intfloat/multilingual-e5-small`) is downloaded automatically from HuggingFace by `sentence-transformers` on first use. You do NOT need to pull it from Ollama.

### Qdrant (Two Options)

**Option A — Binary (no Docker needed):**
```bash
# ARM Mac (M1/M2/M3)
mkdir -p ~/qdrant_bin
curl -L "https://github.com/qdrant/qdrant/releases/download/v1.13.2/qdrant-aarch64-apple-darwin.tar.gz" \
  -o ~/qdrant_bin/qdrant.tar.gz
cd ~/qdrant_bin && tar -xzf qdrant.tar.gz && chmod +x qdrant

# Intel Mac / Linux x86_64
curl -L "https://github.com/qdrant/qdrant/releases/download/v1.13.2/qdrant-x86_64-unknown-linux-musl.tar.gz" \
  -o ~/qdrant_bin/qdrant.tar.gz
cd ~/qdrant_bin && tar -xzf qdrant.tar.gz && chmod +x qdrant
```

**Option B — Docker:**
```bash
docker run -d -p 6333:6333 qdrant/qdrant
```

---

## Environment Variables

### Setup

```bash
cd /Users/apple/Desktop/Machine_Guru
cp .env.example .env
```

Then edit `.env` for local dev:

```bash
# Key changes for LOCAL dev:
OLLAMA_BASE_URL=http://localhost:11434   # was http://ollama:11434
QDRANT_HOST=localhost                    # was qdrant (Docker hostname)
DEVICE=cpu                               # was cuda (for Jetson)
USE_FP16=false                           # was true
USE_FLASH_ATTENTION=false                # was true
DEBUG=true
CORS_ORIGINS=["http://localhost:5173","http://localhost:5174","http://localhost:3000"]
```

---

### Required Variables

These MUST be set correctly for the app to work:

| Variable | Description | Default | Local Dev Value |
|---|---|---|---|
| `OLLAMA_BASE_URL` | URL of your Ollama server | `http://ollama:11434` | `http://localhost:11434` |
| `LLM_MODEL` | Ollama model for answering | `llama3.2:1b` | `llama3.2:1b` |
| `EMBEDDING_MODEL` | HuggingFace sentence-transformer model | `intfloat/multilingual-e5-small` | _(same)_ |
| `QDRANT_HOST` | Qdrant server hostname | `qdrant` | `localhost` |
| `QDRANT_PORT` | Qdrant REST port | `6333` | `6333` |
| `QDRANT_COLLECTION` | Collection name for vectors | `machine_guru` | _(same)_ |
| `UPLOAD_DIR` | Where uploaded files are saved | `uploads` | _(same)_ |
| `MAX_FILE_SIZE` | Max upload size in bytes | `52428800` (50 MB) | _(same)_ |
| `CORS_ORIGINS` | Allowed frontend origins (JSON array) | `[...]` | Add `5174` if Vite moved ports |
| `DEVICE` | CPU or CUDA for embedding | `cuda` | **`cpu`** |

---

### Optional / Advanced Variables

These have safe defaults and usually don't need changing:

| Variable | Description | Default |
|---|---|---|
| `CHUNK_SIZE` | Characters per text chunk | `512` |
| `CHUNK_OVERLAP` | Overlap between chunks | `64` |
| `TOP_K` | Number of chunks to retrieve per query | `5` |
| `BATCH_SIZE` | Embedding batch size | `64` |
| `PARALLEL_PAGES` | Concurrent page processing threads | `4` |
| `USE_FP16` | Half-precision for GPU (Jetson only) | `true` |
| `USE_FLASH_ATTENTION` | Flash attention (Jetson / A100 only) | `true` |
| `MEMORY_BUDGET_MB` | RAM budget before model unload | `2048` |
| `IDLE_MODEL_TIMEOUT` | Seconds idle before model unload | `300` |
| `ENABLE_CACHING` | Cache query results | `true` |
| `CACHE_TTL_QUERY` | Query cache lifetime (seconds) | `300` |
| `ENABLE_STREAMING` | Enable SSE streaming responses | `true` |
| `MAX_CONCURRENT_LLM` | Max parallel LLM calls | `2` |
| `MAX_CONCURRENT_EMBEDDING` | Max parallel embedding calls | `1` |
| `LOG_LEVEL` | Logging verbosity | `INFO` |
| `JSON_LOGGING` | Structured JSON logs | `false` |
| `METRICS_ENABLED` | Prometheus-style metrics | `true` |

---

### What Is NOT Needed

> ❌ **MongoDB URI** — Not used. Document metadata is stored in Qdrant payloads alongside vectors.

> ❌ **Cloudinary / S3 / File Storage URL** — Not used. Files are saved locally to `UPLOAD_DIR` (default: `uploads/` inside the backend directory).

> ❌ **Redis URL** — Not used. Query caching and request coalescing are in-memory using Python dicts.

> ❌ **JWT Secret / Auth** — Not used. There is no authentication in this version.

> ❌ **Email / SMTP** — Not used.

> ❌ **Stripe / Payment** — Not used.

---

## Quick Start (Local Dev)

Open **3 separate terminal tabs:**

### Terminal 1 — Qdrant

```bash
mkdir -p ~/qdrant_storage
QDRANT__STORAGE__STORAGE_PATH=~/qdrant_storage \
  /Users/apple/Desktop/Machine_Guru/qdrant_bin/qdrant
```

> Qdrant UI available at: http://localhost:6333/dashboard

### Terminal 2 — Backend

```bash
cd /Users/apple/Desktop/Machine_Guru/backend
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8001
```

> API docs at: http://localhost:8001/docs  
> Health check: http://localhost:8001/api/v1/health

### Terminal 3 — Frontend

```bash
cd /Users/apple/Desktop/Machine_Guru/frontend
npm run dev
```

> App at: http://localhost:5174 (or 5173 if port is free)

### First-Time Backend Setup

```bash
cd /Users/apple/Desktop/Machine_Guru/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### First-Time Frontend Setup

```bash
cd /Users/apple/Desktop/Machine_Guru/frontend
npm install
```

---

## Running with Docker

> **Note:** Port 8000 is used by another project on this machine. If you use docker-compose, override the port or rename the service.

```bash
cd /Users/apple/Desktop/Machine_Guru
docker-compose up --build
```

The `docker-compose.yml` starts:
- `backend` on port `8000` (internal) — change to `8001:8000` if needed
- `qdrant` on port `6333`
- `ollama` on port `11434`

**Frontend is NOT in docker-compose** — run it locally with `npm run dev`.

---

## Frontend Pages

All pages are fully implemented:

| Page | Route | What It Does |
|---|---|---|
| **Dashboard** | `/` | Live health status cards (Backend, Qdrant, document count, vector size). Polls every 15 seconds. |
| **Upload** | `/upload` | Drag-and-drop file upload with progress bar. Shows chunk count, page count, and embed time after ingestion. Accepts PDF, DOCX, TXT up to 50 MB. |
| **Chat** | `/chat` | Full streaming chat with the RAG system. Shows typing indicator, suggestion chips, stop/clear buttons, and `[Source N]` citation badges. |
| **History** | `/history` | Browse, search, and delete past chat sessions stored in your browser's localStorage. |
| **Settings** | `/settings` | Light/dark/system theme toggle. Read-only view of system configuration. |

### Responsive Design

- **Desktop (≥768px):** Persistent sidebar on the left
- **Mobile (<768px):** Fixed top navigation bar + slide-in drawer menu with backdrop

---

## API Reference

Base URL: `http://localhost:8001/api/v1`

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Returns system health, Qdrant connection, vector count |
| `POST` | `/ingest` | Upload a file → chunk → embed → store. Form field: `file` |
| `POST` | `/query` | One-shot RAG query. Body: `{"text": "...", "top_k": 5}` |
| `POST` | `/query/stream` | Streaming SSE RAG. Body: `{"text": "...", "top_k": 5}` |
| `POST` | `/upload` | Raw file upload without embedding |

Interactive docs: http://localhost:8001/docs

---

## Known Issues & Bugs Fixed

### ✅ Fixed: Upload 500 Error (`memory_track` async bug)

**Root cause:** `core/memory.py` defined `memory_track` as a synchronous `@contextmanager`, but `use_cases/ingestion.py` and `use_cases/query.py` used it with `async with`. Python 3.13 raises:

```
TypeError: '_GeneratorContextManager' object does not support 
           the asynchronous context manager protocol
```

**Fix:** Converted `memory_track` to `@asynccontextmanager` in `core/memory.py`. The old sync version is preserved as `memory_track_sync`.

### ✅ Fixed: Import collision (`use_cases/ingestion/`)

There was both a `use_cases/ingestion.py` file and a `use_cases/ingestion/` empty directory. Python resolves the package (directory) first, causing `ImportError`. Fixed by populating `use_cases/ingestion/__init__.py` to re-export `IngestionUseCase` from the actual file.

### ✅ Fixed: Vite proxy target

Changed from `http://backend:8000` (Docker hostname) to `http://localhost:8001` for local development.

### ✅ Fixed: Tailwind CSS variable tokens

The `tailwind.config.ts` was missing the `theme.extend.colors` mapping for CSS variables (`--border`, `--card`, `--primary`, etc.), causing all shadcn-style classes to render as transparent/wrong colors. Added the full mapping.

---

## What Is Still Missing

### 🔴 Critical (Breaks Core Functionality)

| Missing | Impact | How to Add |
|---|---|---|
| **No authentication** | Anyone on the network can access the API | Add FastAPI JWT auth or an API key middleware |
| **No `.env` validation on startup** | App starts silently with wrong config | Add Pydantic `model_validator` to `core/config.py` |

### 🟡 Important (Limits Usefulness)

| Missing | Impact | Notes |
|---|---|---|
| **No document list API** | Can't see what's been uploaded | Add `GET /api/v1/documents` that queries Qdrant payloads |
| **No document delete API** | Can't remove documents from the vector store | Add `DELETE /api/v1/documents/{id}` |
| **Chat history not persisted to backend** | History is localStorage only — lost if browser cleared | Add a `POST /api/v1/sessions` endpoint + SQLite or Qdrant payload storage |
| **No streaming on Chat page reconnect** | If page refreshes mid-stream, message is lost | Add session recovery |
| **Ollama not auto-started** | If Ollama isn't running, uploads work but chat fails silently | Add `/api/v1/health/llm` endpoint and show in Dashboard |

### 🟢 Nice-to-Have

| Missing | Notes |
|---|---|
| **Multi-document filtering** | Chat currently searches ALL documents; add per-document filter |
| **File preview** | Show uploaded PDFs in a viewer |
| **Export chat** | Download conversation as PDF or markdown |
| **User accounts** | Multi-user support with isolated document collections |
| **Cloudinary / S3 support** | For production file storage (currently saves to local `uploads/` dir) |
| **MongoDB support** | For production metadata storage (currently stored in Qdrant payloads) |
| **Progress indicator for embedding** | The embedding download (~90 MB) on first run shows no progress |
| **Docker Compose frontend service** | Frontend currently requires manual `npm run dev` |
| **HTTPS / SSL** | Required for production deployment |

---

## Troubleshooting

### Upload fails with 500 error
- ✅ This was a bug in `core/memory.py` — **now fixed** (see Known Issues above)
- If still failing: check backend terminal for the full traceback
- First upload will be slow (~60s) because it downloads the embedding model from HuggingFace

### "Backend not reachable" on Dashboard
```bash
# Check backend is running
curl http://localhost:8001/api/v1/health

# Check Qdrant is running
curl http://localhost:6333/healthz

# Check Ollama is running
curl http://localhost:11434/api/tags
```

### Frontend shows blank page / no styles
- Run `npm install` in the `frontend/` directory
- Check browser console for errors
- Make sure `tailwind.config.ts` has the color token extensions (see fixed version)

### Port already in use
```bash
# Find what's using port 8001
lsof -i :8001

# Kill it
kill -9 $(lsof -t -i :8001)
```

### Embedding model download on first run
The `intfloat/multilingual-e5-small` model (~90 MB) downloads from HuggingFace automatically on the **first document upload**. This will appear slow — the upload will sit at 100% for 1-2 minutes while the model loads. This only happens once; it's cached in `~/.cache/huggingface/`.

### `OLLAMA_BASE_URL` wrong
If Ollama is running but chat doesn't work:
```bash
# Verify Ollama is reachable
curl http://localhost:11434/api/tags

# Make sure your .env has:
OLLAMA_BASE_URL=http://localhost:11434
```
