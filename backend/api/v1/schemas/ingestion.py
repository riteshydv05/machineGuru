from pydantic import BaseModel


class IngestionResponse(BaseModel):
    document_id: str
    filename: str
    content_type: str
    size_bytes: int
    page_count: int
    chunk_count: int
    average_chunk_length: float
    embedding_dimensions: int
    qdrant_stored: bool
    processing_time_seconds: float
