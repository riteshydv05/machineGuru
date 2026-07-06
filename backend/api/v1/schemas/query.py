from pydantic import BaseModel, Field


class QueryRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4096)
    top_k: int = Field(default=5, ge=1, le=50)
    document_id: str | None = Field(default=None, description="Filter to a specific document (None = all)")


class CitationResponse(BaseModel):
    source_index: int
    document_id: str
    filename: str
    page: int | None = None
    chunk_index: int | None = None


class SourceReferenceResponse(BaseModel):
    document_id: str
    filename: str
    page: int | None = None
    chunk_index: int | None = None
    score: float | None = None


class QueryResponse(BaseModel):
    answer: str
    sources: list[SourceReferenceResponse]
    citations: list[CitationResponse] | None = None
    query_text: str
    timestamp: str
    timings: dict | None = None
    debug: dict | None = None
