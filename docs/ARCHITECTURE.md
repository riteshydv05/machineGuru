# Architecture

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Client Browser                            │
│                          (React SPA)                                │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ HTTP / SSE
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          Nginx (port 80)                             │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  • Static file serving (compiled React SPA)                  │   │
│  │  • API reverse proxy → backend:8000                          │   │
│  │  • Rate limiting (10 req/s per IP)                           │   │
│  │  • Security headers (HSTS, X-Frame, CSP)                     │   │
│  │  • Gzip compression                                          │   │
│  │  • Asset caching (1 year for /assets/)                       │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     FastAPI Backend (port 8000)                      │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                      Middleware Stack                          │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │  │
│  │  │ Request  │ │   CORS   │ │  Rate    │ │  Benchmark /     │  │  │
│  │  │  ID      │ │          │ │ Limiter  │ │  Metrics         │  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                       API Layer                                │  │
│  │  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │  │
│  │  │ Health  │ │  Query   │ │  Ingest  │ │  Upload          │  │  │
│  │  │ /health │ │ /query   │ │ /ingest  │ │  /upload         │  │  │
│  │  │         │ │/query/   │ │          │ │                  │  │  │
│  │  │         │ │ stream   │ │          │ │                  │  │  │
│  │  └─────────┘ └──────────┘ └──────────┘ └──────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                     Use Case Layer                             │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  │
│  │  │   Query    │  │ Ingestion  │  │   Health   │              │  │
│  │  │ UseCase    │  │  UseCase   │  │  UseCase   │              │  │
│  │  └─────┬──────┘  └─────┬──────┘  └────────────┘              │  │
│  └────────┼───────────────┼──────────────────────────────────────┘  │
│           │               │                                         │
│  ┌────────▼───────────────▼──────────────────────────────────────┐  │
│  │                    Infrastructure Layer                        │  │
│  │  ┌──────────────┐  ┌──────────┐  ┌──────────────────────┐    │  │
│  │  │  Embedding   │  │   LLM    │  │  Document Processing │    │  │
│  │  │  (Sentence-  │  │ (Ollama  │  │  ┌─────┐ ┌───────┐  │    │  │
│  │  │  Transformer)│  │  Async)  │  │  │Extr.│ │Chunker│  │    │  │
│  │  └──────┬───────┘  └────┬─────┘  │  └─────┘ └───────┘  │    │  │
│  │         │               │        └──────────────────────┘    │  │
│  │         │               │                                    │  │
│  │  ┌──────▼───────────────▼──────────────────────────────┐     │  │
│  │  │              Core Services                          │     │  │
│  │  │  ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌────────┐ │     │  │
│  │  │  │  Cache  │ │ Metrics │ │Concurrency│ │Memory  │ │     │  │
│  │  │  │(LRU+TTL)│ │(Prom)   │ │(Semaphore)│ │Manager │ │     │  │
│  │  │  └─────────┘ └─────────┘ └──────────┘ └────────┘ │     │  │
│  │  └───────────────────────────────────────────────────┘     │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
          ▼                    ▼                    ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────────┐
│  Qdrant DB   │   │   Ollama     │   │  Filesystem      │
│  (Vector     │   │  (LLM +      │   │  (Uploads/)      │
│   Store)     │   │   Embedding) │   │                  │
│  port 6333   │   │  port 11434  │   │  PDF/DOCX/TXT    │
└──────────────┘   └──────────────┘   └──────────────────┘
```

---

## Data Flow

### Query Flow

```
User Query
    │
    ▼
[1] Rate Limiter ──→ 429 if over limit
    │
    ▼
[2] Query Cache ──→ Return cached result if exists (TTL: 5 min)
    │
    ▼
[3] Embedding Cache ──→ Return cached embedding if exists (TTL: 24h)
    │
    ▼
[4] SentenceTransformer ──→ Generate query embedding (FP16, Flash Attn)
    │
    ▼
[5] Qdrant Search ──→ Top-K nearest chunks (COSINE similarity)
    │
    ▼
[6] Build Context ──→ Format chunks with [Source N] markers
    │
    ▼
[7] Ollama LLM ──→ Generate answer (streaming or full)
    │
    ▼
[8] Citation Parser ──→ Regex [Source N] → structured citations
    │
    ▼
[9] Cache Result ──→ Store in query cache
    │
    ▼
    Response (JSON or SSE stream)
```

### Ingestion Flow

```
PDF/DOCX/TXT Upload
    │
    ▼
[1] Validate file (ext, size)
    │
    ▼
[2] Save to uploads/
    │
    ▼
[3] Extract text per page (PyMuPDF / python-docx)
    │
    ▼
[4] Parallel chunking (4 workers) ──→ Chunks with page numbers
    │
    ▼
[5] Embedding cache check ──→ Skip cached chunks
    │
    ▼
[6] Batch embedding (batch_size=64, GPU)
    │
    ▼
[7] Batch upsert to Qdrant (batch_size=256)
    │
    ▼
    IngestionResult response
```

---

## Component Design

### Clean Architecture Layers

```
┌────────────────────────────────────────────┐
│           API Layer (Adapters)             │
│  FastAPI routes, Pydantic schemas,         │
│  request/response transformation           │
├────────────────────────────────────────────┤
│         Use Case Layer (Boundary)          │
│  Business logic, orchestration,            │
│  does NOT import infrastructure directly   │
├────────────────────────────────────────────┤
│         Domain Layer (Enterprise)          │
│  Entities: Document                        │
│  Value Objects: Chunk, Query               │
│  Pure Pydantic — zero dependencies         │
├────────────────────────────────────────────┤
│      Infrastructure Layer (Framework)      │
│  QdrantRepository, OllamaService,          │
│  EmbeddingService, TextExtractor           │
│  Concrete implementations of ports         │
└────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Clean Architecture** | Swap any infra component (e.g., Qdrant → Pinecone) without touching business logic |
| **Dependency Injection** | `FastAPI Depends()` + `lru_cache` singletons — testable, swappable |
| **All async** | `asyncio` throughout — non-blocking I/O for LLM, DB, file operations |
| **Pydantic everywhere** | Runtime type safety, automatic validation, `model_validate()` for layered crossing |
| **Loguru** | Structured logging with rotation, JSON output option, zero-config |
| **Custom exceptions** | Every error has `error_id`, `error_code`, `status_code` — consistent API error responses |

---

## Optimization Architecture

```
┌──────────────────────────────────────────────────┐
│                  Cache Layer                      │
│  ┌──────────────┐          ┌──────────────┐      │
│  │  Embedding   │          │    Query     │      │
│  │  Cache       │          │    Cache     │      │
│  │  (1024, 24h) │          │  (128, 5min) │     │
│  └──────┬───────┘          └──────┬───────┘      │
└─────────┼─────────────────────────┼──────────────┘
          │                         │
┌─────────▼─────────────────────────▼──────────────┐
│              Concurrency Control                  │
│  ┌──────────────┐  ┌──────────┐  ┌──────────┐   │
│  │  LLM: max 2  │  │ Embed: 1 │  │Qdrant: 8 │   │
│  └──────────────┘  └──────────┘  └──────────┘   │
│  ┌──────────────────────────────────────────┐    │
│  │      Request Coalescer (dedup)           │    │
│  └──────────────────────────────────────────┘    │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│              Memory Management                    │
│  ┌──────────────────────────────────────────┐    │
│  │  ModelRegistry  │  MemoryManager         │    │
│  │  • track loaded │  • check at 75% budget │   │
│  │  • idle timeout │  • unload idle models  │   │
│  │  • force unload │  • GC + empty cache    │   │
│  └──────────────────────────────────────────┘    │
└──────────────────────────────────────────────────┘
```

---

## Deployment Architecture

```
┌──────────────────────────────────────────────────┐
│                  Docker Host                      │
│                                                   │
│  ┌─────────────┐  ┌─────────────┐                │
│  │  Container  │  │  Container  │                │
│  │  Backend    │◄─┤  Frontend   │                │
│  │  :8000      │  │  :80        │                │
│  └──────┬──────┘  └─────────────┘                │
│         │                                         │
│  ┌──────▼──────┐  ┌─────────────┐                │
│  │  Container  │  │  Container  │                │
│  │  Qdrant     │  │  Ollama     │                │
│  │  :6333      │  │  :11434     │                │
│  └─────────────┘  └─────────────┘                │
│                                                   │
│  Volumes: qdrant_storage, ollama_models, uploads  │
│  Network: machine-guru-network (bridge)           │
└──────────────────────────────────────────────────┘
```

---

## Monitoring Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Prometheus (port 9090)                   │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │  Scrape Jobs     │  │  Alerting Rules  │                   │
│  │  backend:8000    │  │  BackendDown     │                   │
│  │  qdrant:6333     │  │  HighErrorRate   │                   │
│  │  ollama:11434    │  │  SlowQueries     │                   │
│  └─────────────────┘  └─────────────────┘                   │
└──────────────────────────┬───────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────┐
│                       Grafana (port 3000)                     │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Dashboards: Query Latency, Throughput, Cache, GPU    │    │
│  │  Datasource: Prometheus (provisioned)                 │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

## Graceful Shutdown Flow

```
SIGTERM/SIGINT
    │
    ▼
Set _SHUTTING_DOWN flag
    │
    ▼
New requests → 503 Service Unavailable
    │
    ▼
Drain in-flight requests (30s timeout)
    │
    ▼
Unload all ML models
    │
    ▼
Clear GPU memory cache
    │
    ▼
Exit cleanly
```
