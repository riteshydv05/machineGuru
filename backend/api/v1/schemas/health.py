from pydantic import BaseModel


class QdrantStatusResponse(BaseModel):
    connected: bool
    collection: str | None = None
    vector_size: int | None = None
    point_count: int | None = None
    error: str | None = None


class HealthResponse(BaseModel):
    status: str
    version: str
    timestamp: str
    uptime_seconds: float | None = None
    qdrant: QdrantStatusResponse | None = None


class ErrorResponse(BaseModel):
    error_id: str
    error_code: str
    message: str
    detail: str | None = None
