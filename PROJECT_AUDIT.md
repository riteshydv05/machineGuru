# MachineGuru — Project Audit Document

**Generated:** 2026-07-23  
**Auditor:** Automated codebase inspection (no code modified, no assumptions made)  
**Purpose:** Determine Jetson Orin Nano + Ollama deployment readiness

---

## 1. Project Overview

| Field | Value |
|---|---|
| **Project Name** | MachineGuru |
| **Purpose** | Industrial RAG (Retrieval-Augmented Generation) system for querying uploaded technical documents (PDFs, DOCX, TXT) using an on-device LLM |
| **Current Version** | `0.2.0` (`.env` and `.env.example`); `frontend/package.json` shows `0.1.0` |
| **Overall Architecture** | Clean Architecture — Domain / Use Cases / Infrastructure / API layers. Full-stack: React SPA + FastAPI backend + Qdrant vector DB + Ollama LLM |
| **Main Features** | PDF/DOCX/TXT upload, text extraction, chunking, embedding, vector storage, hybrid RAG query (dense + BM25), streaming LLM responses, citation extraction, multimodal image captioning, document management |
| **Tech Stack** | Python 3.12 (backend), TypeScript / React 19 (frontend), Qdrant (vector DB), Ollama (LLM runtime) |
| **Frontend Framework** | React 19 + Vite 6 + TailwindCSS 3 |
| **Backend Framework** | FastAPI 0.115.6 with Uvicorn 0.34.0 |
| **Database** | No relational database. Document registry persisted as JSON file (`document_registry.json`) in the uploads directory |
| **Vector Database** | Qdrant 1.13.2 (local binary or Docker) |
| **Embedding Model** | `intfloat/multilingual-e5-small` via SentenceTransformers 3.4.1 (default). Optional fallback: Ollama `/api/embeddings` endpoint |
| **LLM** | `llama3.2:1b` (default, configurable via `LLM_MODEL` env var), served by Ollama |
| **Vision/Multimodal Model** | `llava:7b` (used for image captioning if `ENABLE_MULTIMODAL=true`) |
| **OCR Libraries** | PyMuPDF (`fitz`) for text extraction and image extraction; `pytesseract` (optional) for OCR on images; Pillow for image processing |
| **Deployment Methods** | Native script (`start.sh`), Docker Compose (`docker-compose.yml`), Jetson-specific setup (`deploy/jetson_setup.sh` + `deploy/install.sh`) |
| **Package Manager** | `pip` + `venv` (Python backend); `npm` (Node/frontend) |
| **Python Version** | 3.12 (Dockerfile base image: `python:3.12-slim`) |
| **Node Version** | Not pinned in code; Vite 6 + React 19 require Node >= 18 |

---

## 2. Folder Structure

```
Machine_Guru/
├── .env                          # Local dev environment (gitignored)
├── .env.example                  # Full annotated env template
├── .dockerignore
├── .gitignore
├── .qdrant-initialized           # Marker file (empty)
├── docker-compose.yml            # 4-service compose: backend, frontend, qdrant, ollama
├── Makefile                      # Convenience make targets
├── start.sh                      # Native start-all script (458 lines)
├── stop.sh                       # Stop all services
├── restart.sh                    # Restart all services
├── DEPLOYMENT.md
├── HOW-TO-RUN.md
├── JETSON_SETUP.md
├── PROJECT_STRUCTURE.md
├── PROJECT_VIVA_GUIDE.md
├── README.md
│
├── backend/
│   ├── main.py                   # FastAPI app factory, lifespan, middlewares
│   ├── requirements.txt          # Python dependencies
│   ├── Dockerfile                # Multi-stage Docker image (python:3.12-slim)
│   ├── pytest.ini
│   │
│   ├── api/
│   │   ├── dependencies.py       # DI container (lru_cache singletons)
│   │   └── v1/
│   │       ├── router.py         # API router assembly
│   │       ├── endpoints/
│   │       │   ├── health.py     # GET /health
│   │       │   ├── upload.py     # POST /upload
│   │       │   ├── ingestion.py  # POST /ingest
│   │       │   ├── query.py      # POST /query, POST /query/stream
│   │       │   └── documents.py  # GET/PUT/DELETE /documents
│   │       └── schemas/
│   │           ├── health.py
│   │           ├── upload.py
│   │           ├── ingestion.py
│   │           └── query.py
│   │
│   ├── core/
│   │   ├── config.py             # Pydantic settings (all env vars)
│   │   ├── exceptions.py         # Typed exception hierarchy
│   │   ├── cache.py              # LRU cache (embedding + query)
│   │   ├── concurrency.py        # Semaphore limiters + coalescer
│   │   ├── rate_limiter.py       # Token-bucket middleware (10 rps)
│   │   ├── memory.py             # ModelRegistry + MemoryManager
│   │   ├── benchmark.py          # Timer, ThroughputMeter, measure()
│   │   ├── metrics.py            # Prometheus counters/histograms/gauges
│   │   ├── logging.py            # Loguru setup (JSON or human-readable)
│   │   └── dependencies.py       # (empty wrapper module)
│   │
│   ├── domain/
│   │   ├── entities/
│   │   │   └── document.py       # Document Pydantic model
│   │   └── value_objects/
│   │       ├── chunk.py          # Chunk Pydantic model
│   │       └── query.py          # Query Pydantic model
│   │
│   ├── infrastructure/
│   │   ├── database/
│   │   │   ├── qdrant_repository.py  # Async Qdrant client wrapper
│   │   │   └── bm25_index.py         # In-memory BM25 (rank-bm25)
│   │   ├── document_processing/
│   │   │   ├── extractor.py          # PyMuPDF / python-docx text extraction
│   │   │   ├── cleaner.py            # Unicode + whitespace normalization
│   │   │   ├── chunker.py            # RecursiveTextSplitter
│   │   │   └── image_extractor.py    # PyMuPDF image extraction + pytesseract OCR
│   │   ├── embedding/
│   │   │   ├── embedding_service.py  # EmbeddingService (async wrapper)
│   │   │   └── model_loader.py       # SentenceTransformerModel + OllamaEmbeddingModel
│   │   └── llm/
│   │       ├── ollama_service.py     # OllamaService (chat streaming)
│   │       └── vision_service.py     # VisionService (image captioning)
│   │
│   ├── use_cases/
│   │   ├── health.py             # HealthUseCase
│   │   ├── upload.py             # UploadUseCase (save file only)
│   │   ├── ingestion.py          # IngestionUseCase (full pipeline)
│   │   ├── query.py              # QueryUseCase (RAG + streaming)
│   │   ├── hybrid_retriever.py   # HybridRetriever (dense + BM25 + RRF)
│   │   └── document_registry.py  # DocumentRegistry (JSON persistence)
│   │
│   ├── uploads/                  # (created at runtime)
│   ├── logs/                     # (created at runtime)
│   └── tests/
│
├── frontend/
│   ├── index.html
│   ├── package.json
│   ├── vite.config.ts            # Vite proxy config → backend:8001
│   ├── tsconfig.json
│   ├── nginx.conf                # Production nginx reverse-proxy config
│   ├── Dockerfile                # Nginx static serving
│   └── src/
│       ├── main.tsx              # React entry + BrowserRouter
│       ├── App.tsx               # Route tree
│       ├── index.css
│       ├── vite-env.d.ts
│       ├── components/
│       │   ├── chat/
│       │   │   ├── ActiveDocumentBar.tsx
│       │   │   ├── ChatInput.tsx
│       │   │   ├── ChatMessage.tsx
│       │   │   ├── DebugPanel.tsx
│       │   │   └── MessageActions.tsx
│       │   ├── citations/
│       │   │   ├── CitationBadge.tsx
│       │   │   ├── CitationRenderer.tsx
│       │   │   └── SourcePreview.tsx
│       │   ├── layout/
│       │   │   ├── AppLayout.tsx
│       │   │   ├── Sidebar.tsx
│       │   │   └── ThemeToggle.tsx
│       │   ├── upload/
│       │   │   ├── FileUploader.tsx
│       │   │   └── UploadProgress.tsx
│       │   └── ui/
│       │       ├── badge.tsx
│       │       ├── button.tsx
│       │       ├── card.tsx
│       │       ├── input.tsx
│       │       ├── progress.tsx
│       │       ├── scroll-area.tsx
│       │       ├── separator.tsx
│       │       └── skeleton.tsx
│       ├── context/
│       │   ├── DocumentContext.tsx
│       │   └── ThemeContext.tsx
│       ├── hooks/
│       │   ├── useChat.ts
│       │   └── useTheme.ts
│       ├── pages/
│       │   ├── DashboardPage.tsx
│       │   ├── ChatPage.tsx
│       │   ├── UploadPage.tsx
│       │   ├── DocumentsPage.tsx
│       │   ├── HistoryPage.tsx
│       │   └── SettingsPage.tsx
│       ├── services/
│       │   └── api.ts            # Axios client + stream fetch
│       ├── types/
│       │   └── index.ts          # TypeScript interface definitions
│       └── utils/
│           └── cn.ts             # clsx + tailwind-merge helper
│
├── config/                       # Empty (contains only .gitkeep)
├── deploy/
│   ├── install.sh                # Full install script (deps + venv + npm)
│   ├── jetson_setup.sh           # Jetson-specific setup (Ollama, PyTorch)
│   ├── preflight.sh              # Preflight checks
│   ├── healthcheck.sh            # Health verification
│   ├── verify_installation.sh    # Post-install verification
│   ├── update.sh                 # Update script
│   ├── deploy_lib.sh             # Shared bash functions library
│   ├── grafana/                  # Grafana dashboard config
│   └── prometheus/               # Prometheus scrape config
├── scripts/
│   ├── backup.sh
│   ├── healthcheck.sh
│   └── watchdog.sh
├── storage/                      # Runtime data (gitignored)
│   ├── uploads/
│   ├── cache/
│   ├── embeddings/
│   └── qdrant/
├── qdrant_bin/                   # Local Qdrant binary directory
├── qdrant_storage/               # (alternate) Qdrant on-disk storage
├── snapshots/                    # Qdrant snapshot directory
├── logs/                         # Application logs (gitignored)
├── docs/
└── tests/
```

---

## 3. Backend API Endpoints

All endpoints are mounted under the prefix `/api/v1`.

### 3.1 GET `/api/v1/health`

| Field | Value |
|---|---|
| **Method** | GET |
| **URL** | `/api/v1/health` |
| **Purpose** | System health check: returns backend status, version, uptime, and Qdrant connection status |
| **Input** | None |
| **Output** | `{ status, version, timestamp, uptime_seconds, qdrant: { connected, collection, vector_size, point_count, error } }` |
| **Files** | `api/v1/endpoints/health.py`, `use_cases/health.py` |
| **Authentication** | None |

### 3.2 POST `/api/v1/upload`

| Field | Value |
|---|---|
| **Method** | POST |
| **URL** | `/api/v1/upload` |
| **Purpose** | Saves uploaded file to disk only. Does NOT embed or index |
| **Input** | `multipart/form-data` — field `file` |
| **Output** | `{ id, filename, content_type, size_bytes, uploaded_at }` |
| **Files** | `api/v1/endpoints/upload.py`, `use_cases/upload.py` |
| **Authentication** | None |

### 3.3 POST `/api/v1/ingest`

| Field | Value |
|---|---|
| **Method** | POST |
| **URL** | `/api/v1/ingest` |
| **Purpose** | Full ingestion pipeline: validate → save → extract → clean → chunk → embed → store in Qdrant → register document |
| **Input** | `multipart/form-data` — field `file` |
| **Output** | `{ document_id, filename, content_type, size_bytes, page_count, chunk_count, image_count, average_chunk_length, embedding_dimensions, qdrant_stored, processing_time_seconds }` |
| **Files** | `api/v1/endpoints/ingestion.py`, `use_cases/ingestion.py` |
| **Authentication** | None |

### 3.4 POST `/api/v1/query`

| Field | Value |
|---|---|
| **Method** | POST |
| **URL** | `/api/v1/query` |
| **Purpose** | Non-streaming RAG query. Returns complete answer after full LLM generation |
| **Input** | `{ text: str, top_k?: int (1-50, default 5), document_id?: str or null, page_filter?: int or null, chunk_type_filter?: str or null }` |
| **Output** | `{ answer, sources[], citations[], query_text, timestamp, timings, debug (if DEBUG=true), model }` |
| **Files** | `api/v1/endpoints/query.py`, `use_cases/query.py`, `use_cases/hybrid_retriever.py` |
| **Authentication** | None |

### 3.5 POST `/api/v1/query/stream`

| Field | Value |
|---|---|
| **Method** | POST |
| **URL** | `/api/v1/query/stream` |
| **Purpose** | Streaming RAG query via Server-Sent Events (SSE). Sends sources first, then token-by-token LLM output, then done event |
| **Input** | Same as `/query` |
| **Output** | SSE stream: `{"type":"sources","sources":[...]}`, N x `{"type":"token","text":"..."}`, `{"type":"done","citations":[...],"timings":{...},"model":"..."}` |
| **Files** | `api/v1/endpoints/query.py`, `use_cases/query.py`, `infrastructure/llm/ollama_service.py` |
| **Authentication** | None |

### 3.6 GET `/api/v1/documents`

| Field | Value |
|---|---|
| **Method** | GET |
| **URL** | `/api/v1/documents` |
| **Purpose** | Returns list of all ingested documents with embedding counts from Qdrant |
| **Input** | None |
| **Output** | `{ documents: [DocumentInfo], total: int, active_document_id: str or null }` |
| **Files** | `api/v1/endpoints/documents.py`, `use_cases/document_registry.py` |
| **Authentication** | None |

### 3.7 GET `/api/v1/documents/active`

| Field | Value |
|---|---|
| **Method** | GET |
| **URL** | `/api/v1/documents/active` |
| **Purpose** | Returns the currently active document |
| **Input** | None |
| **Output** | `{ document: DocumentInfo or null }` |
| **Files** | `api/v1/endpoints/documents.py`, `use_cases/document_registry.py` |
| **Authentication** | None |

### 3.8 PUT `/api/v1/documents/active/{document_id}`

| Field | Value |
|---|---|
| **Method** | PUT |
| **URL** | `/api/v1/documents/active/{document_id}` |
| **Purpose** | Sets a specific document as the active document for queries |
| **Input** | Path parameter `document_id: str` |
| **Output** | `{ document: DocumentInfo or null }` |
| **Files** | `api/v1/endpoints/documents.py`, `use_cases/document_registry.py` |
| **Authentication** | None |

### 3.9 DELETE `/api/v1/documents/{document_id}`

| Field | Value |
|---|---|
| **Method** | DELETE |
| **URL** | `/api/v1/documents/{document_id}` |
| **Purpose** | Deletes a document: removes vectors from Qdrant, deletes file from disk, removes images directory, removes from registry |
| **Input** | Path parameter `document_id: str` |
| **Output** | `{ deleted: bool, document_id: str, filename: str, vectors_removed: bool }` |
| **Files** | `api/v1/endpoints/documents.py`, `use_cases/document_registry.py`, `infrastructure/database/qdrant_repository.py` |
| **Authentication** | None |

### 3.10 GET `/api/v1/stats`

| Field | Value |
|---|---|
| **Method** | GET |
| **URL** | `/api/v1/stats` |
| **Purpose** | Returns process memory, CPU, GPU info, loaded model status, cache stats, and concurrency limiter stats |
| **Input** | None |
| **Output** | `{ service, version, memory_mb, cpu_percent, gpu, models, caches, concurrency, shutting_down }` |
| **Files** | `main.py` (defined inline) |
| **Authentication** | None |

### 3.11 GET `/metrics`

| Field | Value |
|---|---|
| **Method** | GET |
| **URL** | `/metrics` |
| **Purpose** | Prometheus metrics endpoint (only active if `METRICS_ENABLED=true`) |
| **Input** | None |
| **Output** | Prometheus text format |
| **Files** | `main.py`, `core/metrics.py` |
| **Authentication** | None |

---

## 4. Frontend Analysis

### 4.1 Pages and Routes

| Route | Component File | Purpose |
|---|---|---|
| `/` | `DashboardPage.tsx` | System health cards (backend status, Qdrant status, vector count). Auto-refreshes every 15 seconds via `/api/v1/health` |
| `/upload` | `UploadPage.tsx` | File drag-and-drop upload with per-file progress bar and ingestion result summary |
| `/documents` | `DocumentsPage.tsx` | Document table with search, sort, set-active, and delete (with confirmation). Shows chunk/embedding/image counts |
| `/chat` | `ChatPage.tsx` | Main chat interface with streaming, source attribution, debug panel, export to Markdown |
| `/history` | `HistoryPage.tsx` | Browse past chat sessions from `localStorage` (`mg-chat-history`). Delete sessions |
| `/settings` | `SettingsPage.tsx` | Read-only system config display; theme toggle (light/dark/system); debug mode toggle |

### 4.2 Components

| Component | Purpose |
|---|---|
| `layout/AppLayout.tsx` | Outlet wrapper rendering Sidebar + Outlet |
| `layout/Sidebar.tsx` | Navigation links (Dashboard, Upload, Documents, Chat, History, Settings) |
| `layout/ThemeToggle.tsx` | Dark/light mode toggle button |
| `chat/ActiveDocumentBar.tsx` | Shows currently active document; allows switching query mode (current doc / all docs) |
| `chat/ChatInput.tsx` | Textarea + send button with keyboard shortcut |
| `chat/ChatMessage.tsx` | Renders user/assistant messages with markdown, citation badges |
| `chat/DebugPanel.tsx` | Shows retrieved chunks, prompt, timings, and raw answer when debug mode is on |
| `chat/MessageActions.tsx` | Copy, regenerate, and delete actions for messages |
| `citations/CitationBadge.tsx` | Renders `[Source N]` inline badge |
| `citations/CitationRenderer.tsx` | Parses answer text and replaces `[Source N]` patterns with badges |
| `citations/SourcePreview.tsx` | Hover popup showing source document, page, and score |
| `upload/FileUploader.tsx` | Drag-and-drop zone accepting `.pdf`, `.txt`, `.docx` |
| `upload/UploadProgress.tsx` | Progress bar component (uploading → processing → done/error) |
| `ui/*` | Primitive UI components (button, badge, card, input, progress, scroll-area, separator, skeleton) using `class-variance-authority` |

### 4.3 Hooks

| Hook | File | Purpose |
|---|---|---|
| `useChat` | `hooks/useChat.ts` | All chat state: messages array, `send()`, `cancel()`, `clear()`, `regenerate()`, `deleteMessage()`, `exportMarkdown()`. Manages streaming via `sendQueryStream()`. Saves sessions to `localStorage` (max 50 sessions) |
| `useTheme` | `hooks/useTheme.ts` | Returns `{ theme, toggleTheme }` from ThemeContext |

### 4.4 Services

| Service | File | Functions |
|---|---|---|
| API Service | `services/api.ts` | `healthCheck()`, `fetchDocuments()`, `fetchActiveDocument()`, `setActiveDocument()`, `deleteDocument()`, `uploadFile()` (with progress callback), `sendQuery()`, `sendQueryStream()` (ReadableStream + SSE parsing) |

### 4.5 Context / Providers

| Context | File | State |
|---|---|---|
| `ThemeContext` | `context/ThemeContext.tsx` | `theme: "light" or "dark"`, `toggleTheme()`. Persists to `localStorage`. Applies `dark` class to `document.documentElement` |
| `DocumentContext` | `context/DocumentContext.tsx` | `documents[]`, `activeDocument`, `queryMode: "current" or "all"`, `loading`, `setActiveDocument()`, `deleteDocument()`, `refresh()`. Polls every 30 seconds |

### 4.6 How Chat Works (Step-by-Step)

1. User types in `ChatInput` and submits.
2. `ChatPage.handleSend()` determines `docId` based on `queryMode` (`"current"` → active document ID, `"all"` → `null`).
3. `useChat.send(text, useStream=true, docId)` is called.
4. A placeholder assistant message with empty content is immediately added to the messages state.
5. `sendQueryStream()` opens a `fetch` POST to `/api/v1/query/stream`.
6. The response body is read chunk-by-chunk via `ReadableStream.getReader()`.
7. The buffer is split on `\n`, SSE `data:` prefix is stripped, and each JSON line is parsed.
8. `onSources` callback updates the assistant message with retrieved sources.
9. `onToken` callback appends each token to the assistant message content in state.
10. `onDone` callback adds citations, timings, model name, and response time to the message.
11. The session is saved to `localStorage`.

### 4.7 How Upload Works (Step-by-Step)

1. User drops or selects a file in `FileUploader` (accepts `.pdf`, `.txt`, `.docx`).
2. `UploadPage.handleFile()` creates an `UploadItem` with status `"uploading"`.
3. `uploadFile(file, onProgress)` sends `multipart/form-data` POST to `/api/v1/ingest`.
4. `axios.onUploadProgress` updates the `progress` state (0-100%).
5. After server responds, status transitions: `uploading` → `processing` (600ms delay) → `done`.
6. The `UploadResponse` (chunk count, embedding dimensions, processing time) is displayed.
7. On error, status becomes `"error"` and the error message is shown.

### 4.8 How Streaming Works

- **Frontend:** `fetch()` via `ReadableStream.getReader()`. Manual SSE parsing (split on `\n`, strip `data:` prefix). No `EventSource` API used.
- **Backend:** `sse-starlette`'s `EventSourceResponse` wrapping an `async for` generator.
- **SSE protocol:** each event has `event: message` and `data: <json>` lines.
- **JSON types sent in order:** `sources` → N × `token` → `done`.

---

## 5. PDF Pipeline (Step-by-Step)

```
User uploads PDF via multipart/form-data (POST /api/v1/ingest)
              ↓
Validation
  - File extension check: must be .pdf, .txt, or .docx
  - File size check: must be <= MAX_FILE_SIZE (default 50 MB)
              ↓
Save to Disk
  - File saved as: {UPLOAD_DIR}/{uuid4}{.ext}
  - Document entity created (UUID id, filename, content_type, size_bytes, uploaded_at)
              ↓
Text Extraction (infrastructure/document_processing/extractor.py)
  - PDF: PyMuPDF (fitz) — page.get_text() per page
  - TXT: open() with UTF-8 encoding
  - DOCX: python-docx — joins paragraph text
  - Returns list of page strings + page count
              ↓
Text Cleaning (infrastructure/document_processing/cleaner.py)
  - Unicode NFKC normalization
  - CR/LF normalization
  - Null byte removal
  - Multiple space collapse
  - Excessive newline collapse (3+ becomes 2)
  - Zero-width character removal
              ↓
Chunking — RecursiveTextSplitter (infrastructure/document_processing/chunker.py)
  - chunk_size: 512 chars (configurable via CHUNK_SIZE)
  - chunk_overlap: 64 chars (configurable via CHUNK_OVERLAP)
  - Separators tried in order: "\n\n", "\n", ". ", "! ", "? ", "; ", ", ", " ", ""
  - Overlap applied by prepending tail of previous chunk
  - Pages processed in parallel (asyncio.Semaphore, PARALLEL_PAGES=4)
              ↓
Image Extraction (optional, only if ENABLE_MULTIMODAL=true and file is .pdf)
  - PyMuPDF page.get_images(full=True) → doc.extract_image(xref)
  - Filters: min 100x100 px, min area 15,000 px^2
  - Saved as: {UPLOAD_DIR}/images/{document_id}/page{N}_fig{M}.{ext}
  - Optional OCR: pytesseract.image_to_string() on each extracted image
  - Vision captioning: Ollama AsyncClient.chat() with llava:7b model
    - Prompt: "Describe this technical image in detail..."
    - Image encoded as base64
  - Image captions create Chunk objects with chunk_type="image"
              ↓
Embedding (infrastructure/embedding/embedding_service.py)
  - Primary: SentenceTransformer("intfloat/multilingual-e5-small").encode()
    - Text chunks prefixed: "passage: {content}"
    - Query text prefixed: "query: {text}"
    - normalize_embeddings=True
    - Dimension: 384
  - Fallback (USE_OLLAMA_EMBEDDINGS=true): Ollama /api/embeddings endpoint
  - Batch size: 64 (configurable via BATCH_SIZE)
  - In-memory LRU cache: capacity=1024, TTL=86400s (24 hours)
  - Embedding runs in executor (thread pool) via asyncio.run_in_executor
              ↓
Vector Storage (infrastructure/database/qdrant_repository.py)
  - Qdrant upsert in batches of 256 points per batch
  - Each point: { id: chunk_uuid, vector: float[384], payload: {...} }
              ↓
Document Registry (use_cases/document_registry.py)
  - DocumentInfo saved to {UPLOAD_DIR}/document_registry.json
  - New document set as "active"
              ↓
Response returned: IngestionResult with stats
```

**Libraries used in pipeline:**
- `pymupdf` (fitz): PDF text and image extraction
- `python-docx`: DOCX extraction
- `sentence-transformers`: local embedding model
- `qdrant-client`: vector storage
- `Pillow`: image processing (mode conversion before OCR)
- `pytesseract`: OCR (optional, gracefully skipped if not installed)
- `ollama`: vision model for image captioning; also LLM inference

---

## 6. Embedding System

| Property | Value |
|---|---|
| **Embedding Model** | `intfloat/multilingual-e5-small` (SentenceTransformers) |
| **Dimension** | 384 |
| **Chunk Size** | 512 characters (configurable via `CHUNK_SIZE`) |
| **Chunk Overlap** | 64 characters (configurable via `CHUNK_OVERLAP`) |
| **Batch Size** | 64 (configurable via `BATCH_SIZE`) |
| **Caching** | In-memory `EmbeddingCache` (LRU, capacity=1024, TTL=86400s). Key: SHA-256 of text. NOT persisted to disk across restarts |
| **Storage** | Embeddings stored in Qdrant as float vectors. The `EMBEDDINGS_DIR` path exists in config but is not used for persisting embedding objects — only Qdrant holds them |
| **Embeddings Regenerated on Startup?** | No. Existing Qdrant collection and `document_registry.json` are loaded at startup. Embeddings are only generated during `/api/v1/ingest` |
| **Duplicate PDF Detection?** | No. There is no content hashing or filename deduplication. Re-uploading the same file creates a new document ID and new vectors |
| **Alternative Backend** | `OllamaEmbeddingModel` via `USE_OLLAMA_EMBEDDINGS=true`. Uses Ollama `/api/embeddings` endpoint. Both backends implement the same `.encode()` interface |

---

## 7. Vector Database

| Property | Value |
|---|---|
| **Database** | Qdrant |
| **Version** | 1.13.2 (client) / `qdrant/qdrant:v1.13.2` (Docker image) |
| **Collection Name** | `machine_guru` (configurable via `QDRANT_COLLECTION`) |
| **Host** | `localhost` (default, configurable via `QDRANT_HOST`) |
| **Port** | `6333` (configurable via `QDRANT_PORT`) |
| **gRPC Port** | `6334` (Docker only) |
| **Search Algorithm** | Dense: HNSW (Qdrant default). BM25: in-memory BM25Okapi |
| **Similarity Metric** | Cosine distance |
| **Top K Retrieval** | Default 5, range 1-50, configurable per query via `top_k` parameter |
| **Delete Support** | Yes. `DELETE /api/v1/documents/{document_id}` calls `qdrant.delete_by_document()` using `Filter` on `document_id` field |
| **Update Support** | Upsert only. No in-place update endpoint |
| **Filtering Support** | Yes: `document_id`, `page` (int), `chunk_type` (str) via `FieldCondition` + `MatchValue` |

### Qdrant Point Payload Schema

Each point stored in Qdrant has the following payload:

| Field | Type | Description |
|---|---|---|
| `chunk` | `str` | Raw chunk text content |
| `document_name` | `str` | Original filename |
| `document_id` | `str` | UUID of the document |
| `chunk_index` | `int` | Sequential index of chunk within document |
| `page` | `int` | Page number (1-indexed) |
| `metadata` | `dict[str, str]` | Additional metadata (e.g., image width/height) |
| `chunk_type` | `str` | `"text"` or `"image"` or `"table"` |
| `figure_number` | `str or null` | Figure label (e.g., `"Figure 5.2"`) |
| `image_path` | `str or null` | Filesystem path to extracted image file |

---

## 8. Retrieval Pipeline (Step-by-Step)

```
User sends query text
              ↓
Query validation
  - text must not be empty, length <= 4096 characters
              ↓
Query cache check (QueryCache: capacity=128, TTL=300s)
  - Key: SHA-256(query_text) + top_k
  - If hit: return cached QueryResult immediately
              ↓
Query Embedding
  - EmbeddingService.embed_query(text)
  - SentenceTransformer.encode("query: {text}", normalize_embeddings=True)
  - Returns float[384]
  - Embedding cache checked first (SHA-256 key, TTL=86400s)
              ↓
Hybrid Retrieval (use_cases/hybrid_retriever.py)
  |
  +-- Dense Vector Search (Qdrant)
  |     - QdrantRepository.search() or search_with_filter()
  |     - Fetches top_k * 2 candidates (to allow fusion headroom)
  |     - Optional filters: document_id, page, chunk_type
  |
  +-- BM25 Keyword Search (in-memory)
        - BM25Index.search(query_text, top_k=top_k*2)
        - Tokenizer: lowercase, strip punctuation, split on whitespace, min length 2
        - Index built lazily on first query from Qdrant scroll_all()
        - Falls back to dense-only if BM25 fails
              ↓
Reciprocal Rank Fusion (RRF)
  - Dense weight: 0.7, BM25 weight: 0.3 (configurable)
  - RRF score = weight / (k + rank + 1) where k=60
  - Results keyed by first 200 chars of chunk text
  - Final list sorted by fused score, truncated to top_k
              ↓
Post-processing
  - Deduplication: removes chunks with identical normalized text (first 200 chars)
  - Low-relevance filter: drops chunks below SCORE_THRESHOLD (default 0.15)
    - Always keeps at least 1 result if any were returned
              ↓
Context Building (_build_context)
  - Format: "[Source N] (Document: {name}, Page: {page}, Relevance: {score:.0%})\n{cleaned_text}"
  - Image chunks: "[Source N] (... Figure: {fig_num}, Type: Image Caption ...)"
  - Table chunks: "[Source N] (... Type: Table ...)"
  - OCR artifact cleanup applied (_clean_chunk_text)
              ↓
Prompt Assembly
  - System prompt: SYSTEM_PROMPT (engineering expert persona)
  - User prompt: USER_PROMPT_TEMPLATE.format(context=context, question=query.text)
              ↓
LLM Generation (OllamaService)
  - Model: llama3.2:1b (configurable)
  - API: Ollama AsyncClient.chat() with stream=True
  - Parameters: temperature=0.1, num_predict=4096, num_ctx=8192, top_p=0.9, repeat_penalty=1.15, top_k=40
              ↓
Citation Parsing
  - Regex: \[Source\s+(\d+)\]
  - Maps citation indices to SourceReference objects
  - Returns list[Citation]
              ↓
Result cached in QueryCache (TTL=300s)
              ↓
Response returned
```

**System Prompt:** MachineGuru is a "senior industrial maintenance engineer and technical documentation expert." Instructions: read all context, be thorough, use bullet points for procedures, cite sources with `[Source N]`, include safety warnings, never refuse if context is even partially relevant.

**User Prompt Template:**
```
Context from technical documentation:
{context}

---

Question: {question}

Provide a thorough, detailed, expert-level answer based on the context above...
```

---

## 9. LLM Configuration

| Property | Value |
|---|---|
| **Model Name** | `llama3.2:1b` (default, from `LLM_MODEL` env var) |
| **Inference Method** | Ollama `AsyncClient.chat()` with `stream=True` |
| **Streaming** | Yes. `generate_stream()` is the primary method; `generate()` calls it internally and joins tokens |
| **Temperature** | `0.1` (from `LLM_TEMPERATURE`, configurable) |
| **Context Length** | `8192` tokens (`NUM_CTX`, configurable) |
| **Max Tokens** | `4096` (`NUM_PREDICT`, configurable) |
| **top_p** | `0.9` (hardcoded in `ollama_service.py`) |
| **repeat_penalty** | `1.15` (hardcoded in `ollama_service.py`) |
| **top_k (sampling)** | `40` (hardcoded in `ollama_service.py`) |
| **keep_alive** | `10m` (`LLM_KEEP_ALIVE`, configurable) |
| **System Prompt** | Hard-coded string `SYSTEM_PROMPT` in `use_cases/query.py` |
| **User Prompt Template** | `USER_PROMPT_TEMPLATE` in `use_cases/query.py` |
| **Host URL** | `settings.OLLAMA_BASE_URL` — defaults to `http://localhost:11434` |

---

## 10. Ollama Configuration

| Property | Value |
|---|---|
| **Model** | `llama3.2:1b` (LLM), `llava:7b` (vision/multimodal) |
| **Host** | `http://localhost:11434` (default) |
| **API Client** | `ollama.AsyncClient(host=base_url)` (Python `ollama==0.4.7` library) |
| **Streaming Endpoint** | `AsyncClient.chat(..., stream=True)` — maps to Ollama `/api/chat` |
| **Generate Endpoint** | Not used directly; `ollama.AsyncClient.chat()` is used for both streaming and non-streaming |
| **Embeddings Endpoint** | `httpx.Client.post(f"{base_url}/api/embeddings", ...)` — only used if `USE_OLLAMA_EMBEDDINGS=true` |
| **Environment Variables** | `OLLAMA_BASE_URL`, `LLM_MODEL`, `VISION_MODEL`, `OLLAMA_NUM_PARALLEL`, `OLLAMA_KEEP_ALIVE`, `OLLAMA_DEBUG`, `LLM_KEEP_ALIVE` |
| **Timeouts** | Ollama Python library default. httpx timeout: 60s (for embedding fallback only) |
| **Slow query detection** | Logs warning if LLM generation takes > 10 seconds |
| **Concurrency limit** | `MAX_CONCURRENT_LLM=2` (asyncio Semaphore via `llm_limiter`) |

---

## 11. Upload System

| Property | Value |
|---|---|
| **Upload Validation** | File extension check (`.pdf`, `.txt`, `.docx`) — `InvalidFileTypeError` on mismatch. File size check (reads full bytes, compare to `MAX_FILE_SIZE`) — `FileTooLargeError` on excess |
| **Maximum File Size** | `52,428,800` bytes = 50 MB (default, configurable via `MAX_FILE_SIZE`) |
| **Supported Formats** | `.pdf`, `.txt`, `.docx` |
| **Duplicate Detection** | None. No filename or content-hash deduplication exists |
| **Progress Tracking** | Axios `onUploadProgress` callback in frontend. Backend does not emit progress events during processing |
| **Cancellation** | Frontend: `AbortController` signal passed to `sendQueryStream()`. No server-side cancellation handling exists for in-progress ingestion |
| **Retry** | No automatic retry logic implemented on either frontend or backend |
| **Error Handling** | Backend: `MachineGuruError` subclasses converted to JSON by exception handler. Frontend: `try/catch` on `uploadFile()`, sets `status="error"` |

---

## 12. OCR

| Property | Value |
|---|---|
| **Libraries** | `pytesseract` >= 0.3.10 (optional OCR), `Pillow` >= 10.0 (image processing), `PyMuPDF` (`fitz`) (image extraction from PDF) |
| **Image Extraction** | `fitz.Document.page.get_images(full=True)` → `doc.extract_image(xref)`. Saves extracted images as PNG/JPEG to disk |
| **Scanned PDFs** | Partially handled: `pytesseract.image_to_string()` is called on each extracted image (in `_try_ocr()`). If a PDF is entirely scanned (no embedded text layer), `fitz.page.get_text()` returns empty strings. There is no dedicated scanned-PDF pathway that renders pages as images first |
| **Tables** | No dedicated table extraction library. Table text captured only if it is part of the PDF text layer. `chunk_type="table"` exists in the schema but is never assigned by current ingestion code |
| **Diagrams / Charts** | Captured as images via PyMuPDF. Vision model (`llava:7b`) generates a text description. Stored as image chunk |
| **Math** | No dedicated math OCR |
| **Is OCR Optional?** | Yes. `pytesseract` is listed in `requirements.txt` but its `ImportError` is caught in `_try_ocr()` — system continues without OCR if not installed |
| **Multimodal Optional?** | Yes. Entire image extraction + vision captioning path is guarded by `if settings.ENABLE_MULTIMODAL and ext == ".pdf"`. Vision service errors are caught and logged |

---

## 13. Database

There is no relational SQL database. The only persistent storage structures are:

### 13.1 Document Registry (`document_registry.json`)

**Location:** `{UPLOAD_DIR}/document_registry.json`  
**Type:** JSON file, read into memory at startup, written on every mutation.

**Schema (one entry per document):**

| Field | Type | Description |
|---|---|---|
| `document_id` | `str` (UUID) | Unique document identifier |
| `filename` | `str` | Original uploaded filename |
| `uploaded_at` | `str` (ISO 8601) | Upload timestamp (UTC) |
| `page_count` | `int` | Number of pages extracted |
| `chunk_count` | `int` | Number of text chunks created |
| `embedding_count` | `int` | Number of vectors stored in Qdrant |
| `size_bytes` | `int` | File size in bytes |
| `status` | `str` | `"indexed"` or `"processing"` or `"error"` |
| `image_count` | `int` | Number of images extracted |

**Top-level JSON fields:**

| Field | Type | Description |
|---|---|---|
| `active_id` | `str or null` | ID of the currently active document |
| `documents` | `list[DocumentInfo]` | All registered documents |

**Relationships:** None. Flat structure. `document_id` links to Qdrant points via payload field.  
**Indexes:** None (in-memory dict keyed by `document_id`).

### 13.2 Qdrant Vector Collection (`machine_guru`)

See Section 7 for full schema. Qdrant persists to disk at `QDRANT_STORAGE_PATH` (default: `./storage/qdrant`).

### 13.3 BM25 Index

**Type:** In-memory singleton (`BM25Index`). Built lazily on first query from Qdrant scroll_all(). Not persisted. Rebuilt on application restart.

---

## 14. Authentication

| Property | Value |
|---|---|
| **Login** | None. No login system exists |
| **JWT** | None |
| **Sessions** | None |
| **API Keys** | None |
| **Role System** | None |

The application has no authentication or authorization mechanism of any kind. All API endpoints are publicly accessible to anyone who can reach the backend port.

---

## 15. Configuration Files

### 15.1 `.env` (Active Dev Config — All Variables)

| Variable | Current Dev Value | Purpose |
|---|---|---|
| `PROJECT_NAME` | `MachineGuru` | Application name |
| `VERSION` | `0.2.0` | Version string |
| `DEBUG` | `true` | Enables `/docs`, `/redoc`, debug fields in responses |
| `BACKEND_PORT` | `8001` | FastAPI/Uvicorn listening port |
| `FRONTEND_PORT` | `5173` | Vite dev server port |
| `CORS_ORIGINS` | `["http://localhost:5173","http://localhost:3000","http://localhost:80"]` | Allowed CORS origins |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Ollama server URL |
| `LLM_MODEL` | `llama3.2:1b` | Ollama chat model |
| `VISION_MODEL` | `llava:7b` | Ollama vision model |
| `OLLAMA_NUM_PARALLEL` | `2` | Ollama parallel requests |
| `OLLAMA_KEEP_ALIVE` | `300s` | Ollama model idle timeout |
| `OLLAMA_DEBUG` | `0` | Ollama debug flag |
| `NUM_CTX` | `8192` | LLM context window (tokens) |
| `NUM_PREDICT` | `4096` | Max LLM output tokens |
| `LLM_TEMPERATURE` | `0.1` | LLM sampling temperature |
| `LLM_KEEP_ALIVE` | `10m` | Keep model loaded duration |
| `EMBEDDING_MODEL` | `intfloat/multilingual-e5-small` | SentenceTransformers model |
| `USE_OLLAMA_EMBEDDINGS` | not set (defaults `false`) | Use Ollama for embeddings |
| `QDRANT_HOST` | `localhost` | Qdrant host |
| `QDRANT_PORT` | `6333` | Qdrant REST port |
| `QDRANT_COLLECTION` | `machine_guru` | Collection name |
| `QDRANT_LOG_LEVEL` | `INFO` | Qdrant log verbosity |
| `QDRANT_STORAGE_PATH` | `./storage/qdrant` | Qdrant on-disk storage |
| `UPLOAD_DIR` | `./storage/uploads` | Uploaded files directory |
| `LOG_DIR` | `./logs` | Log files directory |
| `CACHE_DIR` | `./storage/cache` | Cache directory (path only, not used for disk cache) |
| `EMBEDDINGS_DIR` | `./storage/embeddings` | Embeddings directory (path only, embeddings stored in Qdrant) |
| `MAX_FILE_SIZE` | `52428800` | 50 MB max upload |
| `CHUNK_SIZE` | `512` | Characters per chunk |
| `CHUNK_OVERLAP` | `64` | Overlap characters |
| `TOP_K` | `5` | Default retrieval top-k |
| `BATCH_SIZE` | `64` | Embedding batch size |
| `PARALLEL_PAGES` | `4` | Concurrent page processing |
| `BM25_WEIGHT` | `0.3` | BM25 fusion weight |
| `DENSE_WEIGHT` | `0.7` | Dense vector fusion weight |
| `SCORE_THRESHOLD` | `0.15` | Min relevance score |
| `DEVICE` | `cpu` | CPU/GPU device for embeddings |
| `USE_FP16` | `false` | Half-precision model |
| `USE_FLASH_ATTENTION` | `false` | Flash attention |
| `QUANTIZE` | `dynamic` | Quantization setting (read but not applied) |
| `ENABLE_MULTIMODAL` | `true` | Enable image extraction + captioning |
| `MEMORY_BUDGET_MB` | `2048` | Memory budget before GC |
| `IDLE_MODEL_TIMEOUT` | `300` | Seconds before idle model unload |
| `MAX_CONCURRENT_LLM` | `2` | Max concurrent LLM calls |
| `MAX_CONCURRENT_EMBEDDING` | `1` | Max concurrent embedding calls |
| `MAX_CONCURRENT_QDRANT` | `4` | Max concurrent Qdrant calls |
| `ENABLE_CACHING` | `true` | Toggle caching (read but not gate-checked in code) |
| `CACHE_TTL_QUERY` | `300` | Query cache TTL seconds |
| `CACHE_TTL_EMBEDDING` | `86400` | Embedding cache TTL seconds |
| `JSON_LOGGING` | `false` | Structured JSON logs |
| `LOG_LEVEL` | `INFO` | Log level |
| `LOG_RETENTION_DAYS` | `30` | Log rotation retention |
| `LOG_MAX_SIZE_MB` | `10` | Log file rotation size |
| `ENABLE_STREAMING` | `true` | Toggle streaming (read but not gate-checked in code) |
| `ENABLE_BENCHMARK` | `true` | Enable benchmark logging |
| `ENABLE_REQUEST_LOGGING` | `true` | Log every HTTP request |
| `METRICS_ENABLED` | `true` | Enable Prometheus metrics |
| `REQUEST_TIMEOUT_SECONDS` | `120` | Request timeout |

### 15.2 `docker-compose.yml`

4 services: `backend` (FastAPI, port 8001), `frontend` (nginx, port 80), `qdrant` (v1.13.2, port 6333/6334), `ollama` (latest, port 11434).

Docker-specific overrides: `QDRANT_HOST=qdrant`, `OLLAMA_BASE_URL=http://ollama:11434`.

Note in file: "The official `ollama/ollama` Docker image does NOT support NVIDIA Jetson CUDA. For GPU acceleration on Jetson, install Ollama natively."

### 15.3 `backend/Dockerfile`

Multi-stage build. Base: `python:3.12-slim`. Runs as non-root user `machineguru`. Exposes port `8000`. CMD: `uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2 --loop uvloop`.

### 15.4 `frontend/nginx.conf`

Reverse proxy for `/api/` to backend. Rate limiting: 10 req/s with burst of 20. Max upload body: 64 MB. Security headers: X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy, Permissions-Policy, HSTS.

### 15.5 `frontend/vite.config.ts`

Dev-mode proxy: `/api` → `http://localhost:{BACKEND_PORT}` (default 8001). Reads `BACKEND_PORT` and `FRONTEND_PORT` from root `.env`.

---

## 16. Deployment

### 16.1 Development (macOS or Linux)

```bash
cp .env.example .env   # Edit for your system
./start.sh             # Starts Qdrant, backend (uvicorn), and frontend (Vite dev server)
```

`start.sh` startup order:
1. Validate environment
2. Create storage directories
3. Auto-start Ollama if installed but stopped
4. Start Qdrant binary from `qdrant_bin/`
5. Wait for Qdrant to be ready
6. Activate Python venv, start FastAPI on port 8001
7. Wait for backend health check
8. Verify Ollama is reachable
9. Start Vite dev server (optional, `--no-frontend` skips)

### 16.2 Docker Compose

```bash
docker compose up -d
```

Note from codebase: Ollama Docker image does not support Jetson CUDA. Recommendation: run `backend frontend qdrant` only and install Ollama natively on Jetson.

### 16.3 Jetson Orin Nano

```bash
./deploy/jetson_setup.sh   # Installs Ollama natively, pulls llama3.2:1b, PyTorch Jetson wheel
./deploy/install.sh        # Full install
./start.sh                 # Start all services
```

`jetson_setup.sh` performs: install Ollama via official script, pull `llama3.2:1b`, install JetPack-specific PyTorch from NVIDIA's Jetson PyPI index.

`requirements.txt` comment: "Do NOT install PyTorch from PyPI on Jetson Orin. NVIDIA provides JetPack-specific wheels."

### 16.4 Deployment Scripts

| Script | Purpose |
|---|---|
| `start.sh` | Start all services (458 lines) |
| `stop.sh` | Stop all services |
| `restart.sh` | Restart all services |
| `deploy/install.sh` | Full install (24 KB) |
| `deploy/jetson_setup.sh` | Jetson-specific setup (12 KB) |
| `deploy/preflight.sh` | Prerequisite checks (13 KB) |
| `deploy/healthcheck.sh` | Post-start health verification (17 KB) |
| `deploy/verify_installation.sh` | Installation verification (15 KB) |
| `deploy/update.sh` | Update existing installation (4 KB) |
| `deploy/deploy_lib.sh` | Shared bash utilities (20 KB) |
| `scripts/backup.sh` | Backup storage directories |
| `scripts/healthcheck.sh` | Simple health check |
| `scripts/watchdog.sh` | Process watchdog |

---

## 17. Performance Instrumentation

No benchmark results are available from the codebase. The following instrumentation exists to capture performance at runtime:

| Metric | Instrumentation |
|---|---|
| Ingestion time | `IngestionResult.processing_time_seconds` returned per upload |
| Embedding time | `embed_time` tracked in `IngestionUseCase.execute()`. Logged per call |
| Dense search time | `timings["qdrant_search_ms"]` in `HybridRetriever.retrieve()` |
| BM25 search time | `timings["bm25_search_ms"]` in `HybridRetriever.retrieve()` |
| Fusion time | `timings["fusion_ms"]` |
| LLM generation time | `timings["llm_generation_ms"]`, `timings["first_token_ms"]`, `timings["total_ms"]` |
| Memory usage | `psutil.Process.memory_info().rss` per request. Prometheus gauge `machineguru_memory_mb` |
| CPU usage | `psutil.cpu_percent()` logged in BENCHMARK output |
| GPU usage | `pynvml` (optional). Prometheus gauges `machineguru_gpu_memory_mb`, `machineguru_gpu_util_percent` |

---

## 18. Existing Features (Complete Checklist)

| Status | Feature |
|---|---|
| YES | PDF Upload |
| YES | TXT Upload |
| YES | DOCX Upload |
| YES | Text Extraction (PyMuPDF, python-docx) |
| YES | Text Cleaning (unicode normalize, whitespace) |
| YES | Recursive Text Chunking |
| YES | Local Embedding (SentenceTransformers, multilingual-e5-small) |
| YES | Ollama Embedding Fallback (USE_OLLAMA_EMBEDDINGS) |
| YES | Qdrant Vector Storage |
| YES | Dense Vector Search (cosine similarity) |
| YES | BM25 Keyword Search (in-memory, rank-bm25) |
| YES | Hybrid Retrieval (RRF fusion: dense + BM25) |
| YES | Streaming LLM Responses (SSE) |
| YES | Non-streaming LLM Responses |
| YES | Citation Extraction (regex [Source N]) |
| YES | Source Attribution (page, chunk, score, chunk type) |
| YES | Document Registry (JSON persistence) |
| YES | Active Document Selection |
| YES | Query Filtering by Document ID |
| YES | Query Filtering by Page |
| YES | Query Filtering by Chunk Type |
| YES | Delete Document (vectors + file + registry) |
| YES | Image Extraction from PDF (PyMuPDF) |
| YES | Vision Captioning (llava:7b via Ollama) |
| YES | pytesseract OCR on extracted images (optional) |
| YES | In-memory Embedding Cache (LRU, 24h TTL) |
| YES | In-memory Query Cache (LRU, 5min TTL) |
| YES | Request Coalescing (duplicate concurrent queries merged) |
| YES | Concurrency Limiters (LLM, embedding, Qdrant) |
| YES | Token Bucket Rate Limiter (10 rps) |
| YES | Memory Budget Management (GC + model unload) |
| YES | Prometheus Metrics Endpoint |
| YES | Loguru Logging (human-readable + JSON mode) |
| YES | Health Check Endpoint |
| YES | System Stats Endpoint |
| YES | CORS Middleware |
| YES | Graceful Shutdown (SIGTERM/SIGINT) |
| YES | Dark/Light Theme Toggle |
| YES | Dashboard with real-time health monitoring |
| YES | Documents Page (search, sort, delete) |
| YES | Chat History (localStorage, max 50 sessions) |
| YES | Chat Export (Markdown download) |
| YES | Message Regeneration |
| YES | Message Deletion |
| YES | Stop Generation (AbortController) |
| YES | Debug Mode Panel |
| YES | Docker Compose deployment |
| YES | Jetson setup scripts |
| YES | Nginx reverse proxy config |

---

## 19. Missing Features

Based strictly on what is absent in the current codebase:

- **No Authentication or Authorization.** No login, no API keys, no JWT, no role-based access.
- **No Duplicate Document Detection.** Re-uploading the same file creates duplicate documents and embeddings.
- **No Ingestion Progress Streaming.** The `/api/v1/ingest` endpoint is a single synchronous POST with no progress events during chunking/embedding.
- **No Table Extraction.** `chunk_type="table"` exists in the schema and context-building code, but no ingestion code assigns this type.
- **No Math OCR.** No library for mathematical expression recognition.
- **No Dedicated Scanned-PDF OCR Path.** `page.get_text()` returns empty for fully scanned PDFs; no render-to-image → OCR fallback exists for the text layer.
- **No Upload Retry Logic.** Frontend and backend have no automatic retry on transient failure.
- **No Webhook or Notification System.** No way to notify external systems of completed ingestion.
- **No Multi-Tenant / User Isolation.** All documents visible to all clients.
- **No BM25 Index Persistence.** BM25 index is rebuilt from Qdrant on first query after every restart.
- **No Embedding Persistence to Disk.** `EMBEDDINGS_DIR` path exists but is never written to; embeddings only exist in Qdrant.
- **No Stream Cancellation on Backend.** When the frontend cancels via `AbortController`, the backend LLM generation continues until completion.
- **No Configurable Settings via UI.** The Settings page is read-only; all configuration requires `.env` file edits.
- **No Pagination for Document List.** All documents returned in a single response.
- **No Bulk Delete.** Documents must be deleted one at a time.
- **No Re-ingestion / Rebuild Embeddings.** No endpoint to re-process an already-uploaded document.

---

## 20. Third-party Dependencies

### Backend (Python)

| Package | Version | Purpose |
|---|---|---|
| `fastapi` | 0.115.6 | Web framework |
| `uvicorn[standard]` | 0.34.0 | ASGI server |
| `pydantic` | 2.10.4 | Data validation/serialization |
| `pydantic-settings` | 2.7.1 | Settings from env vars |
| `sse-starlette` | 2.2.1 | Server-Sent Events |
| `qdrant-client` | 1.13.2 | Qdrant vector DB client |
| `httpx` | >=0.28.0,<1.0.0 | HTTP client (Qdrant + Ollama embedding fallback) |
| `pymupdf` | 1.25.3 | PDF text + image extraction |
| `python-docx` | 1.1.2 | DOCX text extraction |
| `ollama` | 0.4.7 | Ollama Python client |
| `sentence-transformers` | 3.4.1 | Local embedding model |
| `torch` | >=2.1.0,<3.0.0 | PyTorch (SentenceTransformers dependency) |
| `Pillow` | >=10.0.0,<12.0.0 | Image processing |
| `pytesseract` | >=0.3.10,<1.0.0 | OCR (optional) |
| `rank-bm25` | >=0.2.2,<1.0.0 | BM25 keyword search |
| `psutil` | >=6.1.0,<7.0.0 | CPU + memory monitoring |
| `prometheus-client` | >=0.21.0,<1.0.0 | Prometheus metrics |
| `python-multipart` | 0.0.20 | File upload parsing |
| `python-dotenv` | 1.0.1 | `.env` file loading |
| `loguru` | 0.7.3 | Structured logging |

### Frontend (npm)

| Package | Version | Purpose |
|---|---|---|
| `react` | ^19.0.0 | UI framework |
| `react-dom` | ^19.0.0 | React DOM renderer |
| `react-router-dom` | ^7.1.1 | Client-side routing |
| `axios` | ^1.7.9 | HTTP client |
| `react-markdown` | ^9.0.3 | Markdown rendering in chat |
| `lucide-react` | ^0.468.0 | Icon library |
| `class-variance-authority` | ^0.7.1 | UI component variants |
| `clsx` | ^2.1.1 | Conditional classnames |
| `tailwind-merge` | ^2.6.0 | Tailwind class deduplication |
| `tailwindcss-animate` | ^1.0.7 | Animation utilities |
| `vite` | ^6.0.5 | Build tool / dev server |
| `typescript` | ^5.7.2 | Type system |
| `tailwindcss` | ^3.4.17 | CSS framework |
| `@vitejs/plugin-react` | ^4.3.4 | Vite React plugin |
| `@tailwindcss/typography` | ^0.5.16 | Prose typography |
| `postcss` | ^8.4.49 | CSS processing |
| `autoprefixer` | ^10.4.20 | CSS vendor prefixing |

---

## 21. All Environment Variables

| Variable | Default in Code | Required |
|---|---|---|
| `PROJECT_NAME` | `MachineGuru` | No |
| `VERSION` | `0.2.0` | No |
| `DEBUG` | `False` | No |
| `BACKEND_PORT` | `8001` | No |
| `CORS_ORIGINS` | `["http://localhost:5173", ...]` | No |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | No |
| `LLM_MODEL` | `llama3.2:1b` | No |
| `VISION_MODEL` | `llava:7b` | No |
| `NUM_CTX` | `8192` | No |
| `NUM_PREDICT` | `4096` | No |
| `LLM_TEMPERATURE` | `0.1` | No |
| `LLM_KEEP_ALIVE` | `10m` | No |
| `EMBEDDING_MODEL` | `intfloat/multilingual-e5-small` | No |
| `USE_OLLAMA_EMBEDDINGS` | `False` | No |
| `QDRANT_HOST` | `localhost` | No |
| `QDRANT_PORT` | `6333` | No |
| `QDRANT_COLLECTION` | `machine_guru` | No |
| `UPLOAD_DIR` | `./storage/uploads` | No |
| `LOG_DIR` | `./logs` | No |
| `CACHE_DIR` | `./storage/cache` | No |
| `EMBEDDINGS_DIR` | `./storage/embeddings` | No |
| `MAX_FILE_SIZE` | `52428800` (50 MB) | No |
| `ALLOWED_EXTENSIONS` | `{".pdf", ".txt", ".docx"}` | No |
| `CHUNK_SIZE` | `512` | No |
| `CHUNK_OVERLAP` | `64` | No |
| `TOP_K` | `5` | No |
| `BATCH_SIZE` | `64` | No |
| `PARALLEL_PAGES` | `4` | No |
| `BM25_WEIGHT` | `0.3` | No |
| `DENSE_WEIGHT` | `0.7` | No |
| `SCORE_THRESHOLD` | `0.15` | No |
| `DEVICE` | `cpu` | No |
| `USE_FP16` | `False` | No |
| `USE_FLASH_ATTENTION` | `False` | No |
| `ENABLE_MULTIMODAL` | `True` | No |
| `MEMORY_BUDGET_MB` | `2048` | No |
| `IDLE_MODEL_TIMEOUT` | `300` | No |
| `MAX_CONCURRENT_LLM` | `2` | No |
| `MAX_CONCURRENT_EMBEDDING` | `1` | No |
| `MAX_CONCURRENT_QDRANT` | `4` | No |
| `CACHE_TTL_QUERY` | `300` | No |
| `CACHE_TTL_EMBEDDING` | `86400` | No |
| `JSON_LOGGING` | `False` | No |
| `LOG_LEVEL` | `INFO` | No |
| `LOG_RETENTION_DAYS` | `30` | No |
| `LOG_MAX_SIZE_MB` | `10` | No |
| `METRICS_ENABLED` | `True` | No |
| `REQUEST_TIMEOUT_SECONDS` | `120` | No |

---

## 22. Known Limitations

Based strictly on what is observable in the current implementation:

1. **No authentication.** Any client with network access can upload documents, query data, or delete all documents.

2. **Entire file read into memory on upload.** `await file.read()` loads the complete file bytes before the size check. A 50 MB file is held fully in memory during upload.

3. **Embedding cache is not persisted.** The in-memory LRU embedding cache (capacity 1024) is lost on every backend restart. Embeddings must be recomputed from scratch on first request after restart.

4. **BM25 index is not persisted.** Rebuilt from a Qdrant scroll on the first query after every restart. For large collections this has a startup cost.

5. **Qdrant vector size is hardcoded to 384** in `api/dependencies.py` (`get_qdrant_repository(vector_size=384)`). If `USE_OLLAMA_EMBEDDINGS=true` with a model that returns a different dimension, the collection creation will fail or produce incorrect results.

6. **No scanned PDF support at the text level.** `fitz.page.get_text()` returns empty strings for fully scanned PDFs. The only OCR available is on extracted embedded images, not on rendered page pixels.

7. **Duplicate uploads create duplicate embeddings.** No content or filename deduplication.

8. **Document registry and Qdrant can become desynchronized.** If Qdrant fails during `_store_vectors()` but the document is registered, or if the registry is manually edited, state is inconsistent. No reconciliation logic exists.

9. **Rate limiter is per-process, not distributed.** With multiple Uvicorn workers or instances, rate limiting state is not shared.

10. **`ENABLE_CACHING` env var is read but caching is not actually toggled.** The `EmbeddingCache` and `QueryCache` are always instantiated and used regardless of this setting.

11. **`ENABLE_STREAMING` env var is read but streaming is not actually toggled.** The `/query/stream` endpoint always streams regardless.

12. **`QUANTIZE` env var is read but not applied.** No quantization code uses this value.

13. **Vision model (`llava:7b`) may be too large for Jetson Orin Nano.** The model must be separately pulled. If not available, image captioning silently fails and image chunks are not created.

14. **LLM backend cancellation missing.** When a frontend user cancels streaming (AbortController), the `fetch()` connection closes on the frontend but the backend Ollama generation continues until completion.

15. **The `CACHE_DIR` and `EMBEDDINGS_DIR` paths are created at startup but never used.** No disk cache reads or writes occur at these paths.

16. **Chat history stored only in browser localStorage.** History is local to a single browser instance; no server-side persistence.

---

## 23. Code Quality

### Dead Code / Unused Functionality

- `core/dependencies.py` — file exists but is effectively empty (no exports used elsewhere).
- `ENABLE_CACHING` setting — read but never gates actual caching behavior.
- `ENABLE_STREAMING` setting — read but never gates the stream endpoint.
- `QUANTIZE` setting — read but no quantization is applied anywhere.
- `CACHE_DIR` / `EMBEDDINGS_DIR` — paths created but never used for file I/O.
- `AdaptiveBatcher` class in `core/concurrency.py` — implemented but never used anywhere. `_process_batch()` raises `NotImplementedError`.
- `MemorySnapshot` class in `core/benchmark.py` — implemented but not used.
- `tracemalloc` imported in `core/benchmark.py` but never called.
- `prometheus_client.multiprocess.MultiProcessCollector` imported in `core/metrics.py` but not instantiated or used.
- `core/metrics.py` defines many counters (`query_total`, `query_tokens`, `query_cache_hits`, `ingestion_total`, `ingestion_chunks`, `embedding_cache_hits`, etc.) that are never incremented in the application code.

### Duplicate Logic

- File extension validation appears in both `UploadUseCase._validate_extension()` and `IngestionUseCase._validate_file()` with identical logic.
- File read and size check logic appears in both `UploadUseCase._read_content()` and `IngestionUseCase._read_content()` identically.
- `UploadUseCase._save_file()` and the file-saving portion of `IngestionUseCase` have nearly identical code.

### TODO / FIXME Comments

No `TODO` or `FIXME` comments found in the Python or TypeScript source files. `AdaptiveBatcher._flush()` contains `raise NotImplementedError("override _process_batch")` as a placeholder.

### Circular Imports

No circular imports detected. Dependency flow: `api` → `use_cases` → `infrastructure` → `domain` → `core`. Clean architecture dependency rule is followed.

---

## 24. Security

| Property | Current State |
|---|---|
| **Authentication** | None. All endpoints are open |
| **Input Validation** | Query text: min length 1, max 4096 chars (Pydantic). `top_k`: 1-50 (Pydantic). File extension and size validated in use cases |
| **File Validation** | Extension whitelist: `.pdf`, `.txt`, `.docx`. Size limit: 50 MB. No MIME type verification. No file content scanning for malware |
| **Rate Limiting** | Token-bucket in-process middleware: 10 req/s, burst 20, per client IP. Nginx also applies rate limit (10 req/s, burst 20) in production |
| **Secrets** | No secrets in code. All sensitive configuration via `.env` (gitignored). `.env.example` contains no real secrets |
| **CORS** | Configured via `CORS_ORIGINS`. Defaults allow `localhost:5173`, `localhost:3000`, `localhost:80`. Not wildcard. `allow_credentials=True` |
| **SQL Injection** | Not applicable. No SQL database |
| **Prompt Injection Protection** | None. User query text is inserted directly into the LLM prompt template via `.format(question=query.text)` |
| **Path Traversal** | File writes use UUIDs (`{document_id}{ext}`) in `UPLOAD_DIR`. No user-controlled path construction for writes |
| **Secrets in Response** | In `DEBUG=True` mode, exception details (potentially revealing internal paths) are returned in error responses |
| **Security Headers** | Nginx config includes: X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy, Permissions-Policy, HSTS. Not applied in FastAPI dev mode |
| **HTTPS** | Not configured. Only HTTP in all service configurations. Nginx config listens on port 80 only |

---

## 25. Jetson Readiness Report

Based strictly on the current implementation:

| Check | Status | Evidence |
|---|---|---|
| Uses Ollama | YES | `ollama==0.4.7` library; `OllamaService` uses `AsyncClient(host=settings.OLLAMA_BASE_URL)` |
| Uses localhost | YES | `OLLAMA_BASE_URL` defaults to `http://localhost:11434`; `QDRANT_HOST` defaults to `localhost` |
| Supports configurable host | YES | `OLLAMA_BASE_URL`, `QDRANT_HOST`, and `QDRANT_PORT` are all configurable via env vars |
| Supports llama3.2:1b | YES | `LLM_MODEL=llama3.2:1b` is the default value in both `core/config.py` and `.env` |
| Streams responses | YES | `POST /api/v1/query/stream` uses `EventSourceResponse` with `AsyncClient.chat(..., stream=True)` |
| Saves embeddings | YES | Embeddings saved to Qdrant collection which persists to `QDRANT_STORAGE_PATH` on disk |
| Saves vector database | YES | Qdrant persists to disk. Storage path: `./storage/qdrant` (configurable) |
| Loads vector database on startup | YES | At startup, `ensure_collection()` checks for existing collection; existing data is preserved. `DocumentRegistry.load()` reads `document_registry.json` |
| Deletes PDFs | YES | `DELETE /api/v1/documents/{document_id}` removes vectors from Qdrant, deletes file from disk, removes images directory |
| Rebuilds embeddings every startup | NO | Embeddings are NOT rebuilt on startup. Existing Qdrant vectors are used |
| Uses GPU (currently) | NO (configurable) | `DEVICE=cpu` in both `.env` and default config. GPU requires `DEVICE=cuda` + Jetson PyTorch wheel from NVIDIA |
| Works offline | YES | All inference (LLM, embedding) runs locally. No external API calls at runtime |
| Has Docker deployment | YES | `docker-compose.yml` provided. Note: Ollama Docker image not supported on Jetson — native install required |
| Has Jetson deployment scripts | YES | `deploy/jetson_setup.sh`, `deploy/install.sh`, `deploy/preflight.sh`, `start.sh`, `stop.sh`, `restart.sh` |

---

## 26. File Inventory (Key Files)

| File | Lines | Key Responsibilities |
|---|---|---|
| `backend/main.py` | 217 | FastAPI app factory, lifespan, CORS, rate limiter, request logging, exception handlers, metrics endpoint, stats endpoint, router mounting |
| `backend/core/config.py` | 151 | All application settings via Pydantic BaseSettings; path resolution; startup validation |
| `backend/core/exceptions.py` | 85 | Exception hierarchy: MachineGuruError, InvalidFileTypeError, FileTooLargeError, DocumentProcessingError, QueryValidationError, LlmError, QdrantError, EmbeddingError, NotFoundError |
| `backend/core/cache.py` | 93 | LRUCache, EmbeddingCache, QueryCache — in-memory with TTL and hit/miss stats |
| `backend/core/concurrency.py` | 120 | RateLimiter (semaphore), RequestCoalescer (dedup concurrent queries), AdaptiveBatcher (unused) |
| `backend/core/rate_limiter.py` | 61 | TokenBucket + RateLimiterMiddleware — per-IP token bucket, 10 rps default |
| `backend/core/memory.py` | 146 | ManagedModel ABC, ModelRegistry, MemoryManager (GC + unload), memory_track context manager |
| `backend/core/benchmark.py` | 160 | Timer, measure() context manager, bench() decorator, ThroughputMeter, MemorySnapshot, force_gc() |
| `backend/core/metrics.py` | 65 | Prometheus counters, histograms, gauges; metrics_endpoint() |
| `backend/core/logging.py` | 94 | Loguru setup (human-readable + JSON modes), log rotation |
| `backend/api/dependencies.py` | 62 | lru_cache DI factory functions for all use cases and repositories |
| `backend/api/v1/router.py` | 12 | Assembles all endpoint routers into api_router |
| `backend/use_cases/ingestion.py` | 292 | Full pipeline: validate, save, extract, chunk (parallel), image extraction+captioning, embed, store, register |
| `backend/use_cases/query.py` | 530 | QueryUseCase.execute() (non-streaming) and execute_stream(), context building, citation parsing, deduplication, relevance filtering, prompt logging, debug info |
| `backend/use_cases/hybrid_retriever.py` | 184 | HybridRetriever.retrieve() — dense + BM25 search, RRF fusion, timing; _MockScoredPoint adapter |
| `backend/use_cases/document_registry.py` | 139 | DocumentRegistry — in-memory dict + JSON file persistence, CRUD for document metadata |
| `backend/infrastructure/database/qdrant_repository.py` | 271 | QdrantRepository — ensure_collection, upsert, delete, delete_by_document, search, search_with_filter, count, count_by_document, scroll_all, health |
| `backend/infrastructure/database/bm25_index.py` | 126 | BM25Index singleton — build, search, add_documents, remove_document, tokenizer |
| `backend/infrastructure/document_processing/extractor.py` | 42 | TextExtractor — PDF (PyMuPDF), TXT, DOCX extraction |
| `backend/infrastructure/document_processing/cleaner.py` | 20 | TextCleaner.clean() — unicode normalize, whitespace collapse |
| `backend/infrastructure/document_processing/chunker.py` | 65 | RecursiveTextSplitter.split_text() — recursive separator splitting + overlap |
| `backend/infrastructure/document_processing/image_extractor.py` | 134 | ImageExtractor.extract_images() — PyMuPDF image extraction, size filtering, image saving, _try_ocr() |
| `backend/infrastructure/embedding/embedding_service.py` | 120 | EmbeddingService — async wrapper, cache check, batch embedding, embed_query() |
| `backend/infrastructure/embedding/model_loader.py` | 305 | SentenceTransformerModel, OllamaEmbeddingModel, singleton selection via USE_OLLAMA_EMBEDDINGS, ModelRegistry registration |
| `backend/infrastructure/llm/ollama_service.py` | 132 | OllamaService — generate_stream() (primary), generate() (collects tokens), stats tracking |
| `backend/infrastructure/llm/vision_service.py` | 121 | VisionService — caption_image(), caption_images_batch(), base64 encoding, llava:7b |
| `backend/domain/entities/document.py` | 13 | Document Pydantic model (id, filename, content_type, size_bytes, uploaded_at) |
| `backend/domain/value_objects/chunk.py` | 18 | Chunk Pydantic model (id, document_id, index, content, page, metadata, embedding, chunk_type, image_path, figure_number, caption) |
| `backend/domain/value_objects/query.py` | 10 | Query Pydantic model (text, top_k, document_id, page_filter, chunk_type_filter) |
| `frontend/src/services/api.ts` | 156 | All API calls: health, documents CRUD, upload (with progress), query, stream parsing |
| `frontend/src/hooks/useChat.ts` | 245 | All chat state management: messages, streaming, session persistence, regenerate, delete, export |
| `frontend/src/context/DocumentContext.tsx` | 105 | DocumentProvider: document list, active document, query mode, 30s poll, CRUD |
| `frontend/src/types/index.ts` | 134 | TypeScript interfaces for all API types |
| `frontend/src/pages/ChatPage.tsx` | 274 | Full chat UI: messages, streaming indicators, debug panel, export |
| `frontend/src/pages/DocumentsPage.tsx` | 317 | Document table: search, sort, active set, delete with confirm |
| `frontend/nginx.conf` | 68 | Nginx reverse proxy + security headers + rate limiting |
| `frontend/vite.config.ts` | 34 | Vite dev server proxy config |
| `backend/Dockerfile` | 52 | Multi-stage backend Docker image |
| `start.sh` | 458 | Native start-all script |

---

## 27. Final Project Snapshot

### Architecture Summary

MachineGuru follows Clean Architecture with four layers:

1. **Domain** (`domain/`) — entities (`Document`) and value objects (`Chunk`, `Query`)
2. **Use Cases** (`use_cases/`) — business logic (ingestion, query, RAG, hybrid retrieval, document registry, health)
3. **Infrastructure** (`infrastructure/`) — Qdrant client, BM25 index, SentenceTransformers, Ollama client, PyMuPDF, vision service, text extractor/cleaner/chunker
4. **API** (`api/`) — FastAPI endpoints, schemas, DI dependencies

The frontend is a React 19 SPA communicating with the backend via a Vite dev proxy (development) or Nginx (production).

### Core Data Flow

**Ingestion:** PDF → PyMuPDF text extraction → Unicode cleaning → RecursiveTextSplitter (512 chars, 64 overlap) → SentenceTransformers embedding (`multilingual-e5-small`, dim=384) → Qdrant upsert.

**Query:** Query embedding → Hybrid retrieval (dense cosine + BM25 Okapi, RRF fusion 0.7/0.3) → context building with `[Source N]` headers → SYSTEM_PROMPT + USER_PROMPT → Ollama AsyncClient streaming → token-by-token SSE to frontend → citation parsing via regex.

### Strengths of Current Implementation

- All inference runs locally; no external API dependencies at runtime.
- Configurable model endpoints via environment variables (`OLLAMA_BASE_URL`, `QDRANT_HOST`).
- Default model (`llama3.2:1b`) is specifically chosen for low-memory devices.
- Qdrant data persists to disk; document registry persists to JSON; embeddings survive restarts.
- Streaming is implemented end-to-end (backend → SSE → frontend ReadableStream).
- Delete document functionality is fully implemented (Qdrant vectors + disk files + registry).
- Hybrid retrieval (dense + BM25) improves recall compared to dense-only search.
- Multimodal pipeline (image extraction + vision captioning) is implemented.
- Dedicated Jetson setup scripts handle ARM64-specific dependencies (Ollama native install, JetPack PyTorch, Docker limitations).

### Implementation Status

The core RAG pipeline is fully implemented: upload, ingest, embed, store, query (streaming + non-streaming), and delete. The frontend provides a complete UI with all primary workflows. Deployment scripts for Jetson Orin Nano are present and specifically account for Jetson constraints. The application is designed for offline, on-device operation with Ollama as the LLM backend.

---

*End of PROJECT_AUDIT.md*
