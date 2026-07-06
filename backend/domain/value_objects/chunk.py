from uuid import uuid4

from pydantic import BaseModel, Field


class Chunk(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    document_id: str
    index: int
    content: str
    page: int = 0
    metadata: dict[str, str] = Field(default_factory=dict)
    embedding: list[float] | None = None
