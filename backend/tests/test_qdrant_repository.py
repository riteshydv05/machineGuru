from unittest.mock import AsyncMock

import pytest
from qdrant_client.http.models import Distance, PointStruct, ScoredPoint, VectorParams

from infrastructure.database.qdrant_repository import QdrantRepository


class TestEnsureCollection:
    async def test_creates_when_missing(self, repo: QdrantRepository, mock_client: AsyncMock) -> None:
        mock_client.get_collections.return_value = AsyncMock(collections=[])

        created = await repo.ensure_collection()

        assert created is True
        mock_client.create_collection.assert_awaited_once_with(
            collection_name="test_collection",
            vectors_config=VectorParams(size=384, distance=Distance.COSINE),
        )

    async def test_skips_when_exists(self, repo: QdrantRepository, mock_client: AsyncMock) -> None:
        class FakeCollection:
            name = "test_collection"

        mock_client.get_collections.return_value = AsyncMock(
            collections=[FakeCollection()]
        )

        created = await repo.ensure_collection()

        assert created is False
        mock_client.create_collection.assert_not_called()


class TestUpsert:
    async def test_inserts_points(self, repo: QdrantRepository, mock_client: AsyncMock) -> None:
        points = [
            PointStruct(
                id="p1",
                vector=[0.1] * 384,
                payload={"chunk": "text", "document_id": "d1"},
            ),
        ]
        mock_client.upsert.return_value = AsyncMock(status="completed")

        result = await repo.upsert(points)

        assert result.status == "completed"
        mock_client.upsert.assert_awaited_once_with(
            collection_name="test_collection",
            points=points,
        )


class TestDelete:
    async def test_deletes_by_ids(self, repo: QdrantRepository, mock_client: AsyncMock) -> None:
        mock_client.delete.return_value = AsyncMock(status="completed")

        result = await repo.delete(["p1", "p2"])

        assert result.status == "completed"
        mock_client.delete.assert_awaited_once()


class TestDeleteByDocument:
    async def test_deletes_with_filter(self, repo: QdrantRepository, mock_client: AsyncMock) -> None:
        mock_client.delete.return_value = AsyncMock(status="completed")

        result = await repo.delete_by_document("doc-123")

        assert result.status == "completed"
        call_kwargs = mock_client.delete.call_args.kwargs
        assert call_kwargs["collection_name"] == "test_collection"
        assert "must" in str(call_kwargs["points_selector"])


class TestSearch:
    async def test_returns_scored_points(self, repo: QdrantRepository, mock_client: AsyncMock) -> None:
        vector = [0.1] * 384
        mock_client.search.return_value = [
            ScoredPoint(
                id="p1",
                version=1,
                score=0.95,
                vector=vector,
                payload={"chunk": "result text", "document_id": "d1"},
            ),
        ]

        results = await repo.search(vector=vector, top_k=5)

        assert len(results) == 1
        assert results[0].score == 0.95
        mock_client.search.assert_awaited_once_with(
            collection_name="test_collection",
            query_vector=vector,
            limit=5,
            score_threshold=None,
            query_filter=None,
        )


class TestCount:
    async def test_returns_count(self, repo: QdrantRepository, mock_client: AsyncMock) -> None:
        mock_client.count.return_value = AsyncMock(count=42)

        count = await repo.count()

        assert count == 42


class TestHealth:
    async def test_healthy(self, repo: QdrantRepository, mock_client: AsyncMock) -> None:
        mock_client.get_collections.return_value = AsyncMock()
        mock_client.get_collection.return_value = AsyncMock(
            config=AsyncMock(
                params=AsyncMock(
                    vectors=AsyncMock(size=384, distance=AsyncMock(name="Cosine"))
                )
            )
        )
        mock_client.count.return_value = AsyncMock(count=10)

        status = await repo.health()

        assert status["connected"] is True
        assert status["collection"] == "test_collection"
        assert status["vector_size"] == 384
        assert status["point_count"] == 10

    async def test_unhealthy(self, repo: QdrantRepository, mock_client: AsyncMock) -> None:
        mock_client.get_collections.side_effect = Exception("Connection refused")

        status = await repo.health()

        assert status["connected"] is False
        assert "error" in status
