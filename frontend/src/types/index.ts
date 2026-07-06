export interface HealthResponse {
  status: string
  version: string
  timestamp: string
  uptime_seconds: number | null
  qdrant: QdrantStatus | null
}

export interface QdrantStatus {
  connected: boolean
  collection: string | null
  vector_size: number | null
  point_count: number | null
  error: string | null
}

export interface UploadResponse {
  document_id: string
  filename: string
  content_type: string
  size_bytes: number
  page_count: number
  chunk_count: number
  average_chunk_length: number
  embedding_dimensions: number
  qdrant_stored: boolean
  processing_time_seconds: number
}

export interface QueryRequest {
  text: string
  top_k: number
  document_id?: string | null
}

export interface Citation {
  source_index: number
  document_id: string
  filename: string
  page: number | null
  chunk_index: number | null
}

export interface SourceReference {
  document_id: string
  filename: string
  page: number | null
  chunk_index: number | null
  score: number | null
}

export interface QueryResponse {
  answer: string
  sources: SourceReference[]
  citations: Citation[] | null
  query_text: string
  timestamp: string
  timings: QueryTimings | null
}

export interface QueryTimings {
  embedding_ms: number
  qdrant_search_ms: number
  prompt_build_ms?: number
  llm_generation_ms: number
  total_ms: number
  chunks_retrieved: number
}

export interface ChatMessage {
  id: string
  role: "user" | "assistant"
  content: string
  sources?: SourceReference[]
  citations?: Citation[]
  timestamp: string
  responseTimeMs?: number
  retrievedChunks?: number
  timings?: QueryTimings
}

// ── Document Management ──────────────────────────────────

export interface DocumentInfo {
  document_id: string
  filename: string
  uploaded_at: string
  page_count: number
  chunk_count: number
  size_bytes: number
  status: string
}

export interface DocumentListResponse {
  documents: DocumentInfo[]
  total: number
  active_document_id: string | null
}
