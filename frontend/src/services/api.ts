import axios from "axios";
import type {
  Citation,
  DocumentInfo,
  DocumentListResponse,
  HealthResponse,
  QueryResponse,
  QueryTimings,
  SourceReference,
  UploadResponse,
} from "@/types";

const api = axios.create({
  baseURL: "/api/v1",
  headers: { "Content-Type": "application/json" },
});

// ── Health ──────────────────────────────────────────────

export const healthCheck = async () => {
  const { data } = await api.get<HealthResponse>("/health");
  return data;
};

// ── Documents ───────────────────────────────────────────

export const fetchDocuments = async (): Promise<DocumentListResponse> => {
  const { data } = await api.get<DocumentListResponse>("/documents");
  return data;
};

export const fetchActiveDocument = async (): Promise<DocumentInfo | null> => {
  const { data } = await api.get<{ document: DocumentInfo | null }>("/documents/active");
  return data.document;
};

export const setActiveDocument = async (documentId: string): Promise<DocumentInfo | null> => {
  const { data } = await api.put<{ document: DocumentInfo | null }>(`/documents/active/${documentId}`);
  return data.document;
};

export const deleteDocument = async (documentId: string): Promise<{ deleted: boolean; filename: string }> => {
  const { data } = await api.delete(`/documents/${documentId}`);
  return data;
};

// ── Upload ──────────────────────────────────────────────

export const uploadFile = async (
  file: File,
  onProgress?: (percent: number) => void,
) => {
  const form = new FormData();
  form.append("file", file);
  const { data } = await api.post<UploadResponse>("/ingest", form, {
    headers: { "Content-Type": "multipart/form-data" },
    onUploadProgress: (e) => {
      if (onProgress && e.total) {
        onProgress(Math.round((e.loaded * 100) / e.total));
      }
    },
  });
  return data;
};

// ── Query ───────────────────────────────────────────────

export const sendQuery = async (text: string, topK = 5, documentId?: string | null) => {
  const { data } = await api.post<QueryResponse>("/query", {
    text,
    top_k: topK,
    document_id: documentId ?? null,
  });
  return data;
};

export interface StreamCallbacks {
  onToken: (token: string) => void;
  onSources: (sources: SourceReference[]) => void;
  onDone: (citations: Citation[] | null, timings: QueryTimings | null, model?: string | null) => void;
  onError: (error: string) => void;
}

export const sendQueryStream = async (
  text: string,
  topK: number,
  callbacks: StreamCallbacks,
  signal?: AbortSignal,
  documentId?: string | null,
) => {
  const response = await fetch("/api/v1/query/stream", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text, top_k: topK, document_id: documentId ?? null }),
    signal,
  });

  if (!response.ok) {
    callbacks.onError(`Server error: ${response.status}`);
    return;
  }

  const reader = response.body?.getReader();
  if (!reader) {
    callbacks.onError("No response body");
    return;
  }

  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;

      // EventSourceResponse sends SSE format: "event: message" and "data: {...}"
      // We need to extract the JSON payload from "data:" lines
      let jsonStr = trimmed;
      if (trimmed.startsWith("data:")) {
        jsonStr = trimmed.slice(5).trim();
      } else if (trimmed.startsWith("event:") || trimmed.startsWith("id:") || trimmed.startsWith("retry:")) {
        continue; // skip SSE control lines
      }

      if (!jsonStr) continue;

      try {
        const data = JSON.parse(jsonStr);
        switch (data.type) {
          case "token":
            callbacks.onToken(data.text);
            break;
          case "sources":
            callbacks.onSources(data.sources);
            break;
          case "done":
            callbacks.onDone(data.citations, data.timings ?? null, data.model ?? null);
            break;
        }
      } catch {
        continue;
      }
    }
  }
};

export default api;
