from unittest.mock import AsyncMock

import pytest

from infrastructure.database.qdrant_repository import QdrantRepository


@pytest.fixture
def mock_client() -> AsyncMock:
    client = AsyncMock()
    return client


@pytest.fixture
def repo(mock_client: AsyncMock) -> QdrantRepository:
    repo = QdrantRepository(
        host="localhost",
        port=6333,
        collection_name="test_collection",
        vector_size=384,
    )
    repo._client = mock_client
    return repo
