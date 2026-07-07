from loguru import logger
from qdrant_client import AsyncQdrantClient
from qdrant_client.http.exceptions import ResponseHandlingException
from qdrant_client.http.models import (
    Distance,
    FieldCondition,
    Filter,
    MatchValue,
    PointStruct,
    ScoredPoint,
    UpdateResult,
    VectorParams,
)

from core.exceptions import QdrantError


class QdrantRepository:
    def __init__(
        self,
        host: str = "localhost",
        port: int = 6333,
        collection_name: str = "machine_knowledge",
        vector_size: int = 384,
    ) -> None:
        self._host = host
        self._port = port
        self._collection_name = collection_name
        self._vector_size = vector_size
        self._client: AsyncQdrantClient | None = None

    async def _get_client(self) -> AsyncQdrantClient:
        if self._client is None:
            self._client = AsyncQdrantClient(host=self._host, port=self._port)
        return self._client

    async def ensure_collection(self) -> bool:
        client = await self._get_client()
        try:
            collections = await client.get_collections()
            existing = [c.name for c in collections.collections]
            if self._collection_name in existing:
                info = await client.get_collection(self._collection_name)
                logger.info(
                    "Collection exists | name={} vectors={}",
                    self._collection_name,
                    info.config.params.vectors.size,
                )
                return False

            await client.create_collection(
                collection_name=self._collection_name,
                vectors_config=VectorParams(
                    size=self._vector_size,
                    distance=Distance.COSINE,
                ),
            )
            logger.info(
                "Collection created | name={} dim={} distance=COSINE",
                self._collection_name,
                self._vector_size,
            )
            return True
        except ResponseHandlingException as exc:
            raise QdrantError(
                message="Cannot connect to Qdrant",
                detail=f"host={self._host} port={self._port} error={exc}",
            ) from exc

    async def upsert(self, points: list[PointStruct]) -> UpdateResult:
        client = await self._get_client()
        try:
            result = await client.upsert(
                collection_name=self._collection_name,
                points=points,
            )
            logger.debug("Upserted {} points into '{}'", len(points), self._collection_name)
            return result
        except Exception as exc:
            raise QdrantError(
                message="Failed to upsert points",
                detail=str(exc),
            ) from exc

    async def delete(self, point_ids: list[str]) -> UpdateResult:
        client = await self._get_client()
        try:
            result = await client.delete(
                collection_name=self._collection_name,
                points_selector=point_ids,
            )
            logger.debug("Deleted {} points from '{}'", len(point_ids), self._collection_name)
            return result
        except Exception as exc:
            raise QdrantError(
                message="Failed to delete points",
                detail=str(exc),
            ) from exc

    async def delete_by_document(self, document_id: str) -> UpdateResult:
        client = await self._get_client()
        try:
            result = await client.delete(
                collection_name=self._collection_name,
                points_selector=Filter(
                    must=[
                        FieldCondition(
                            key="document_id",
                            match=MatchValue(value=document_id),
                        ),
                    ],
                ),
            )
            logger.info("Deleted document '{}' from '{}'", document_id, self._collection_name)
            return result
        except Exception as exc:
            raise QdrantError(
                message=f"Failed to delete document '{document_id}'",
                detail=str(exc),
            ) from exc

    async def search(
        self,
        vector: list[float],
        top_k: int = 5,
        score_threshold: float | None = None,
        document_id: str | None = None,
    ) -> list[ScoredPoint]:
        client = await self._get_client()
        try:
            query_filter = None
            if document_id:
                query_filter = Filter(
                    must=[FieldCondition(key="document_id", match=MatchValue(value=document_id))]
                )

            results = await client.search(
                collection_name=self._collection_name,
                query_vector=vector,
                limit=top_k,
                score_threshold=score_threshold,
                query_filter=query_filter,
            )
            return results
        except Exception as exc:
            raise QdrantError(
                message="Vector search failed",
                detail=str(exc),
            ) from exc

    async def search_with_filter(
        self,
        vector: list[float],
        top_k: int = 5,
        score_threshold: float | None = None,
        document_id: str | None = None,
        page_filter: int | None = None,
        chunk_type_filter: str | None = None,
    ) -> list[ScoredPoint]:
        """Search with advanced metadata filtering."""
        client = await self._get_client()
        try:
            conditions = []
            if document_id:
                conditions.append(FieldCondition(key="document_id", match=MatchValue(value=document_id)))
            if page_filter is not None:
                conditions.append(FieldCondition(key="page", match=MatchValue(value=page_filter)))
            if chunk_type_filter:
                conditions.append(FieldCondition(key="chunk_type", match=MatchValue(value=chunk_type_filter)))

            query_filter = Filter(must=conditions) if conditions else None

            results = await client.search(
                collection_name=self._collection_name,
                query_vector=vector,
                limit=top_k,
                score_threshold=score_threshold,
                query_filter=query_filter,
            )
            return results
        except Exception as exc:
            raise QdrantError(
                message="Filtered vector search failed",
                detail=str(exc),
            ) from exc

    async def count(self) -> int:
        client = await self._get_client()
        try:
            result = await client.count(
                collection_name=self._collection_name,
                exact=True,
            )
            return result.count
        except Exception as exc:
            raise QdrantError(
                message="Failed to count points",
                detail=str(exc),
            ) from exc

    async def count_by_document(self, document_id: str) -> int:
        """Count vectors belonging to a specific document."""
        client = await self._get_client()
        try:
            result = await client.count(
                collection_name=self._collection_name,
                count_filter=Filter(
                    must=[FieldCondition(key="document_id", match=MatchValue(value=document_id))]
                ),
                exact=True,
            )
            return result.count
        except Exception as exc:
            raise QdrantError(
                message=f"Failed to count points for document '{document_id}'",
                detail=str(exc),
            ) from exc

    async def scroll_all(self, document_id: str | None = None, limit: int = 100) -> list:
        """Scroll through all points, optionally filtered by document. Returns payload data."""
        client = await self._get_client()
        try:
            query_filter = None
            if document_id:
                query_filter = Filter(
                    must=[FieldCondition(key="document_id", match=MatchValue(value=document_id))]
                )

            all_points = []
            offset = None
            while True:
                points, next_offset = await client.scroll(
                    collection_name=self._collection_name,
                    scroll_filter=query_filter,
                    limit=limit,
                    offset=offset,
                    with_payload=True,
                    with_vectors=False,
                )
                all_points.extend(points)
                if next_offset is None:
                    break
                offset = next_offset

            return all_points
        except Exception as exc:
            raise QdrantError(
                message="Failed to scroll points",
                detail=str(exc),
            ) from exc

    async def health(self) -> dict:
        try:
            client = await self._get_client()
            collections = await client.get_collections()
            info = await client.get_collection(self._collection_name)
            point_count = await self.count()
            return {
                "connected": True,
                "collection": self._collection_name,
                "vector_size": info.config.params.vectors.size,
                "distance": info.config.params.vectors.distance.name,
                "point_count": point_count,
            }
        except Exception as exc:
            return {
                "connected": False,
                "collection": self._collection_name,
                "error": str(exc),
            }
