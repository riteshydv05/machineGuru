"""
Document Registry — in-memory store with JSON file persistence.

Tracks every ingested document's metadata and which document is currently
"active" (being chatted with).  Loaded at application startup from
``uploads/document_registry.json``.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from loguru import logger
from pydantic import BaseModel, Field


class DocumentInfo(BaseModel):
    document_id: str
    filename: str
    uploaded_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    page_count: int = 0
    chunk_count: int = 0
    size_bytes: int = 0
    status: str = "indexed"          # "indexed" | "processing" | "error"


class DocumentRegistry:
    """Singleton registry — one instance for the whole app."""

    def __init__(self, persist_path: str = "uploads/document_registry.json") -> None:
        self._docs: dict[str, DocumentInfo] = {}
        self._active_id: str | None = None
        self._path = Path(persist_path)

    # ── public API ────────────────────────────────────────

    async def load(self) -> None:
        """Load persisted state from JSON file (called once at startup)."""
        if not self._path.exists():
            logger.info("Document registry file not found — starting fresh")
            return
        try:
            raw = json.loads(self._path.read_text(encoding="utf-8"))
            for d in raw.get("documents", []):
                info = DocumentInfo.model_validate(d)
                self._docs[info.document_id] = info
            self._active_id = raw.get("active_id")
            logger.info(
                "Document registry loaded | documents={} active={}",
                len(self._docs),
                self._active_id,
            )
        except Exception as exc:
            logger.warning("Failed to load document registry | error={}", exc)

    async def register(self, info: DocumentInfo) -> None:
        self._docs[info.document_id] = info
        await self._persist()
        logger.info("Document registered | id={} file={}", info.document_id, info.filename)

    async def list_all(self) -> list[DocumentInfo]:
        return sorted(self._docs.values(), key=lambda d: d.uploaded_at, reverse=True)

    async def get(self, document_id: str) -> DocumentInfo | None:
        return self._docs.get(document_id)

    async def set_active(self, document_id: str) -> DocumentInfo | None:
        if document_id not in self._docs:
            return None
        self._active_id = document_id
        await self._persist()
        logger.info("Active document set | id={}", document_id)
        return self._docs[document_id]

    async def get_active(self) -> DocumentInfo | None:
        if self._active_id and self._active_id in self._docs:
            return self._docs[self._active_id]
        # Fallback: return most recently uploaded
        docs = await self.list_all()
        return docs[0] if docs else None

    async def delete(self, document_id: str) -> bool:
        if document_id not in self._docs:
            return False
        del self._docs[document_id]
        if self._active_id == document_id:
            self._active_id = None
        await self._persist()
        logger.info("Document deleted from registry | id={}", document_id)
        return True

    @property
    def count(self) -> int:
        return len(self._docs)

    # ── persistence ───────────────────────────────────────

    async def _persist(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "active_id": self._active_id,
            "documents": [d.model_dump() for d in self._docs.values()],
        }
        self._path.write_text(json.dumps(data, indent=2), encoding="utf-8")
