"""
Hybrid retriever combining dense vector search with BM25 keyword search.

Uses Reciprocal Rank Fusion (RRF) to merge results from both retrieval methods.
"""

import time
from dataclasses import dataclass

from loguru import logger

from core.config import settings
from infrastructure.database.bm25_index import BM25Document, BM25Index
from infrastructure.database import QdrantRepository
from infrastructure.embedding import EmbeddingService


@dataclass
class HybridResult:
    """A search result from hybrid retrieval."""
    payload: dict
    score: float
    dense_score: float = 0.0
    bm25_score: float = 0.0
    retrieval_method: str = "hybrid"


class HybridRetriever:
    """Combines dense vector search with BM25 for hybrid retrieval."""

    def __init__(
        self,
        embedder: EmbeddingService,
        qdrant: QdrantRepository,
        bm25_weight: float = settings.BM25_WEIGHT,
        dense_weight: float = settings.DENSE_WEIGHT,
    ) -> None:
        self._embedder = embedder
        self._qdrant = qdrant
        self._bm25_weight = bm25_weight
        self._dense_weight = dense_weight
        self._bm25 = BM25Index.instance()

    async def ensure_bm25_index(self, document_id: str | None = None) -> None:
        """Build or rebuild BM25 index from Qdrant data if not already built."""
        if self._bm25.is_built:
            return

        try:
            logger.info("Building BM25 index from Qdrant data...")
            points = await self._qdrant.scroll_all(document_id=None, limit=500)

            documents = []
            for point in points:
                payload = point.payload or {}
                documents.append(BM25Document(
                    point_id=str(point.id),
                    document_id=payload.get("document_id", ""),
                    chunk_text=payload.get("chunk", ""),
                    page=payload.get("page"),
                    chunk_type=payload.get("chunk_type", "text"),
                    payload=payload,
                ))

            self._bm25.build(documents)
        except Exception as exc:
            logger.warning("Failed to build BM25 index | error={}", exc)

    async def retrieve(
        self,
        query_text: str,
        query_vector: list[float],
        top_k: int = 5,
        document_id: str | None = None,
        page_filter: int | None = None,
        chunk_type_filter: str | None = None,
    ) -> tuple[list, dict]:
        """
        Perform hybrid retrieval.
        Returns (results, timing_dict) where results are in ScoredPoint-like format.
        """
        timings = {}

        # Dense vector search
        t = time.perf_counter()
        if page_filter or chunk_type_filter:
            dense_results = await self._qdrant.search_with_filter(
                vector=query_vector,
                top_k=top_k * 2,  # fetch more for fusion
                document_id=document_id,
                page_filter=page_filter,
                chunk_type_filter=chunk_type_filter,
            )
        else:
            dense_results = await self._qdrant.search(
                vector=query_vector,
                top_k=top_k * 2,
                document_id=document_id,
            )
        timings["dense_search_ms"] = round((time.perf_counter() - t) * 1000, 1)

        # BM25 search
        t = time.perf_counter()
        bm25_results = []
        try:
            await self.ensure_bm25_index()
            bm25_results = self._bm25.search(
                query=query_text,
                top_k=top_k * 2,
                document_id=document_id,
            )
        except Exception as exc:
            logger.debug("BM25 search failed, using dense only | error={}", exc)
        timings["bm25_search_ms"] = round((time.perf_counter() - t) * 1000, 1)

        # If no BM25 results, just return dense results directly
        if not bm25_results:
            timings["retrieval_method"] = "dense_only"
            return dense_results[:top_k], timings

        # Reciprocal Rank Fusion
        t = time.perf_counter()
        fused = self._reciprocal_rank_fusion(dense_results, bm25_results, top_k)
        timings["fusion_ms"] = round((time.perf_counter() - t) * 1000, 1)
        timings["retrieval_method"] = "hybrid"
        timings["dense_candidates"] = len(dense_results)
        timings["bm25_candidates"] = len(bm25_results)

        return fused[:top_k], timings

    def _reciprocal_rank_fusion(
        self,
        dense_results: list,
        bm25_results: list[tuple[BM25Document, float]],
        top_k: int,
        k: int = 60,
    ) -> list:
        """
        Merge dense and BM25 results using Reciprocal Rank Fusion.
        RRF score = sum(1 / (k + rank)) for each result list.
        """
        # Build lookup by chunk text (since point IDs may differ)
        scores: dict[str, float] = {}
        result_map: dict[str, object] = {}

        # Dense results
        for rank, result in enumerate(dense_results):
            chunk_key = result.payload.get("chunk", "")[:200]
            rrf_score = self._dense_weight / (k + rank + 1)
            scores[chunk_key] = scores.get(chunk_key, 0) + rrf_score
            result_map[chunk_key] = result

        # BM25 results
        for rank, (doc, bm25_score) in enumerate(bm25_results):
            chunk_key = doc.chunk_text[:200]
            rrf_score = self._bm25_weight / (k + rank + 1)
            scores[chunk_key] = scores.get(chunk_key, 0) + rrf_score
            # Only add to result_map if not already there from dense search
            if chunk_key not in result_map:
                # Create a mock result object with same interface as ScoredPoint
                result_map[chunk_key] = _MockScoredPoint(
                    payload=doc.payload,
                    score=bm25_score,
                )

        # Sort by fused score
        sorted_keys = sorted(scores.keys(), key=lambda k: scores[k], reverse=True)

        # Update scores on the result objects
        results = []
        for key in sorted_keys[:top_k]:
            result = result_map[key]
            result.score = scores[key]
            results.append(result)

        return results


class _MockScoredPoint:
    """Lightweight mock that matches ScoredPoint interface for BM25-only results."""
    def __init__(self, payload: dict, score: float):
        self.payload = payload
        self.score = score
