from datetime import datetime, timezone

from loguru import logger
from pydantic import BaseModel

from core.config import settings
from infrastructure.database import QdrantRepository


class QdrantStatus(BaseModel):
    connected: bool
    collection: str | None = None
    vector_size: int | None = None
    point_count: int | None = None
    error: str | None = None


class HealthResult(BaseModel):
    status: str
    version: str
    timestamp: str
    uptime_seconds: float | None = None
    qdrant: QdrantStatus | None = None


class HealthUseCase:
    def __init__(self, qdrant_repository: QdrantRepository | None = None) -> None:
        self._start_time = datetime.now(timezone.utc)
        self._qdrant = qdrant_repository

    async def execute(self) -> HealthResult:
        logger.debug("Health check requested")

        qdrant_status = None
        if self._qdrant is not None:
            raw = await self._qdrant.health()
            qdrant_status = QdrantStatus(
                connected=raw.get("connected", False),
                collection=raw.get("collection"),
                vector_size=raw.get("vector_size"),
                point_count=raw.get("point_count"),
                error=raw.get("error"),
            )

        return HealthResult(
            status="healthy",
            version=settings.VERSION,
            timestamp=datetime.now(timezone.utc).isoformat(),
            uptime_seconds=(datetime.now(timezone.utc) - self._start_time).total_seconds(),
            qdrant=qdrant_status,
        )
