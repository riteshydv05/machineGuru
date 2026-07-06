# Future Improvements

## Critical

| Priority | Improvement | Effort | Impact |
|----------|-------------|--------|--------|
| 🔴 P0 | **Increase test coverage** — Currently <5%. Add tests for all API endpoints, use cases, infrastructure, and frontend components. Target >80%. | 3 weeks | High |
| 🔴 P0 | **Add authentication** — JWT-based auth for all API endpoints. Multi-user support with session management. | 2 weeks | High |
| 🔴 P0 | **TLS termination** — Add Let's Encrypt / cert-manager for HTTPS. Required for production deployment. | 2 days | High |

## High Priority

| Priority | Improvement | Effort | Impact |
|----------|-------------|--------|--------|
| 🟠 P1 | **Database persistence for documents** — Store document metadata, chunk mapping, and ingestion history in PostgreSQL. Currently metadata is only in Qdrant payloads. | 2 weeks | High |
| 🟠 P1 | **Document management API** — List, delete, re-ingest documents. Currently only upload/ingest exists. | 1 week | High |
| 🟠 P1 | **Multi-user support** — Isolate vector collections or add payload filters per user/tenant. | 2 weeks | High |
| 🟠 P1 | **Grafana dashboard** — Visualize Prometheus metrics (query latency, throughput, memory, GPU usage). | 3 days | Medium |
| 🟠 P1 | **OpenTelemetry tracing** — Distributed tracing across Ollama, Qdrant, and application layers for bottleneck identification. | 1 week | Medium |

## Medium Priority

| Priority | Improvement | Effort | Impact |
|----------|-------------|--------|--------|
| 🟡 P2 | **Reranking** — Add a cross-encoder reranker (e.g., `cross-encoder/ms-marco-MiniLM-L-6-v2`) after Qdrant retrieval to improve result quality. | 3 days | Medium |
| 🟡 P2 | **Hybrid search** — Combine vector search with BM25 keyword search using Qdrant's sparse vectors for better recall. | 1 week | Medium |
| 🟡 P2 | **Chunk overlap visualization** — Show chunk boundaries and overlap regions in the UI for debugging. | 2 days | Low |
| 🟡 P2 | **Document Q&A history** — Store conversation history per document with PostgreSQL. | 1 week | Medium |
| 🟡 P2 | **Batch ingestion API** — Accept multiple files in a single request. | 1 day | Medium |
| 🟡 P2 | **PDF text layer extraction** — Handle scanned PDFs with OCR (Tesseract) when text layer is missing. | 3 days | Medium |
| 🟡 P2 | **Local embedding model registry** — Support downloading embedding models via the API, with version management. | 2 days | Low |
| 🟡 P2 | **Health dashboard UI** — Frontend page showing system stats, cache hit rates, concurrency, and model status. | 2 days | Low |

## Low Priority

| Priority | Improvement | Effort | Impact |
|----------|-------------|--------|--------|
| 🟢 P3 | **Image/chart extraction** — Extract and describe images from PDFs using multimodal models. | 1 week | Low |
| 🟢 P3 | **Markdown/HTML export** — Export conversations as Markdown or HTML. | 1 day | Low |
| 🟢 P3 | **Dark mode refinement** — Improve theme consistency across all components. | 1 day | Low |
| 🟢 P3 | **i18n support** — Multi-language UI (already using multilingual-e5-small for embeddings). | 1 week | Low |
| 🟢 P3 | **PWA support** — Service worker for offline frontend access, installable as PWA. | 2 days | Low |
| 🟢 P3 | **Keyboard shortcuts** — Ctrl+Enter to send, / for commands, etc. | 1 day | Low |
| 🟢 P3 | **Slack/Teams integration** — Webhook-based bot that answers questions from ingested docs. | 3 days | Medium |
| 🟢 P3 | **API versioning** — Full versioned API (v1, v2) with deprecation headers. | 2 days | Low |

## Technical Debt

| Item | Detail | Effort |
|------|--------|--------|
| 🧹 Remove `python-dotenv` | `pydantic-settings` handles `.env` loading internally | 5 min |
| 🧹 Remove `UploadUseCase` | Legacy endpoint — `IngestionUseCase` supersedes it | 30 min |
| 🧹 Consolidate `api/v1/endpoints/upload.py` | Merge into `ingestion.py` | 15 min |
| 🧹 Add `pyproject.toml` | Modern Python project config (replaces `requirements.txt` + `pytest.ini`) | 1 day |
| 🧹 Frontend error boundaries | Wrap each route in React ErrorBoundary | 2 hours |
| 🧹 TypeScript strict checks | Fix remaining `any` types across frontend | 1 day |
| 🧹 Dependency audit | Run `pip-audit` and `npm audit` regularly | 1 hour/month |

## Scalability Considerations

| Concern | Current State | Path Forward |
|---------|--------------|--------------|
| **Concurrent users** | Single uvicorn worker, 2 concurrent LLM calls | Horizontal scaling: multiple backend instances behind nginx load balancer |
| **Vector DB** | Single Qdrant node | Qdrant cluster with sharding and replication |
| **Embedding throughput** | Single GPU, batch_size=64 | Multi-GPU inference with model parallelism |
| **Document volume** | Unlimited (disk-based) | Add document lifecycle management, archival policies |
| **LLM throughput** | 2 concurrent requests to Ollama | Ollama cluster or vLLM for higher throughput |
| **Cache invalidation** | TTL-based (5 min queries, 24h embeddings) | Add event-driven invalidation on document changes |
| **Monitoring** | Custom /stats + Prometheus | Full Grafana + alerting + distributed tracing |
