from datetime import datetime

from pydantic import BaseModel


class UploadResponse(BaseModel):
    id: str
    filename: str
    content_type: str
    size_bytes: int
    uploaded_at: datetime
