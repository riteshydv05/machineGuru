from datetime import datetime, timezone
from uuid import uuid4

from pydantic import BaseModel, Field


class Document(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    filename: str
    content_type: str
    size_bytes: int
    uploaded_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
