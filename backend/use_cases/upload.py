from pathlib import Path

from fastapi import UploadFile
from loguru import logger

from core.config import settings
from core.exceptions import FileTooLargeError, InvalidFileTypeError
from domain.entities.document import Document


class UploadResult(Document):
    pass


class UploadUseCase:
    def __init__(self) -> None:
        self._upload_dir = Path(settings.UPLOAD_DIR)

    async def execute(self, file: UploadFile) -> Document:
        self._validate_extension(file)
        content = await self._read_content(file)
        document = self._save_file(file, content)
        logger.info("Document uploaded | id={} filename={} size={}", document.id, document.filename, document.size_bytes)
        return document

    def _validate_extension(self, file: UploadFile) -> None:
        ext = Path(file.filename or "").suffix.lower()
        if ext not in settings.ALLOWED_EXTENSIONS:
            logger.warning("Rejected file type | filename={}", file.filename)
            raise InvalidFileTypeError(
                filename=file.filename or "unknown",
                allowed_extensions=list(settings.ALLOWED_EXTENSIONS),
            )

    async def _read_content(self, file: UploadFile) -> bytes:
        content = await file.read()
        if len(content) > settings.MAX_FILE_SIZE:
            logger.warning("File too large | size={} max={}", len(content), settings.MAX_FILE_SIZE)
            raise FileTooLargeError(
                size_bytes=len(content),
                max_bytes=settings.MAX_FILE_SIZE,
            )
        return content

    def _save_file(self, file: UploadFile, content: bytes) -> Document:
        ext = Path(file.filename or "").suffix.lower()
        document = Document(
            filename=file.filename or "untitled",
            content_type=file.content_type or "application/octet-stream",
            size_bytes=len(content),
        )
        self._upload_dir.mkdir(parents=True, exist_ok=True)
        file_path = self._upload_dir / f"{document.id}{ext}"
        file_path.write_bytes(content)
        return document
