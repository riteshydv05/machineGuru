"""
In-memory BM25 index for hybrid retrieval.

Builds a BM25 index from Qdrant payloads and provides keyword-based search
to complement dense vector retrieval.
"""

import threading
import time
from dataclasses import dataclass, field

from loguru import logger


@dataclass
class BM25Document:
    """A document in the BM25 index."""
    point_id: str
    document_id: str
    chunk_text: str
    page: int | None = None
    chunk_type: str = "text"
    payload: dict = field(default_factory=dict)


class BM25Index:
    """Thread-safe singleton BM25 index."""

    _instance: "BM25Index | None" = None
    _lock = threading.Lock()

    def __init__(self) -> None:
        self._documents: list[BM25Document] = []
        self._corpus: list[list[str]] = []
        self._bm25 = None
        self._built = False
        self._doc_count = 0

    @classmethod
    def instance(cls) -> "BM25Index":
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = cls()
        return cls._instance

    def build(self, documents: list[BM25Document]) -> None:
        """Build BM25 index from a list of documents."""
        start = time.perf_counter()
        try:
            from rank_bm25 import BM25Okapi

            self._documents = documents
            self._corpus = [self._tokenize(doc.chunk_text) for doc in documents]
            self._bm25 = BM25Okapi(self._corpus) if self._corpus else None
            self._built = True
            self._doc_count = len(documents)

            elapsed = time.perf_counter() - start
            logger.info(
                "BM25 index built | documents={} time={:.2f}s",
                len(documents), elapsed,
            )
        except ImportError:
            logger.warning("rank-bm25 not installed — BM25 search disabled")
            self._built = False

    def search(
        self,
        query: str,
        top_k: int = 10,
        document_id: str | None = None,
    ) -> list[tuple[BM25Document, float]]:
        """Search the BM25 index. Returns (document, score) pairs."""
        if not self._built or self._bm25 is None:
            return []

        tokens = self._tokenize(query)
        if not tokens:
            return []

        scores = self._bm25.get_scores(tokens)

        # Pair documents with scores and filter
        results = []
        for doc, score in zip(self._documents, scores):
            if score <= 0:
                continue
            if document_id and doc.document_id != document_id:
                continue
            results.append((doc, float(score)))

        # Sort by score descending
        results.sort(key=lambda x: x[1], reverse=True)
        return results[:top_k]

    def add_documents(self, documents: list[BM25Document]) -> None:
        """Add documents and rebuild index."""
        self._documents.extend(documents)
        self.build(self._documents)

    def remove_document(self, document_id: str) -> None:
        """Remove all chunks for a document and rebuild."""
        self._documents = [d for d in self._documents if d.document_id != document_id]
        if self._documents:
            self.build(self._documents)
        else:
            self._bm25 = None
            self._built = False
            self._doc_count = 0

    def _tokenize(self, text: str) -> list[str]:
        """Simple whitespace tokenizer with lowercasing."""
        import re
        # Remove special characters, lowercase, split
        text = re.sub(r'[^\w\s]', ' ', text.lower())
        return [t for t in text.split() if len(t) > 1]

    @property
    def is_built(self) -> bool:
        return self._built

    @property
    def doc_count(self) -> int:
        return self._doc_count
