from pydantic import BaseModel, Field


class Query(BaseModel):
    text: str = Field(min_length=1, max_length=4096)
    top_k: int = Field(default=5, ge=1, le=50)
    document_id: str | None = Field(default=None, description="Filter search to a specific document")
    page_filter: int | None = Field(default=None, description="Filter to a specific page number")
    chunk_type_filter: str | None = Field(default=None, description="Filter by chunk type: text, image, table")
