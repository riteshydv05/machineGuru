import asyncio
import time
from pathlib import Path

from fastapi import UploadFile
from loguru import logger
from pydantic import BaseModel
from qdrant_client.http.models import PointStruct

from core.benchmark import measure
from core.config import settings
from core.exceptions import FileTooLargeError, InvalidFileTypeError
from core.memory import memory_track
from domain.entities.document import Document
from domain.value_objects.chunk import Chunk
from infrastructure.database import QdrantRepository
from infrastructure.document_processing import RecursiveTextSplitter, TextCleaner, TextExtractor
from infrastructure.embedding import EmbeddingService
from use_cases.document_registry import DocumentInfo, DocumentRegistry


class IngestionResult(BaseModel):
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


class IngestionUseCase:
    def __init__(
        self,
        qdrant_repository: QdrantRepository,
        document_registry: DocumentRegistry,
        parallel_pages: int = 4,
    ) -> None:
        self._upload_dir = Path(settings.UPLOAD_DIR)
        self._extractor = TextExtractor()
        self._cleaner = TextCleaner()
        self._chunker = RecursiveTextSplitter(
            chunk_size=settings.CHUNK_SIZE,
            chunk_overlap=settings.CHUNK_OVERLAP,
        )
        self._embedder = EmbeddingService()
        self._qdrant = qdrant_repository
        self._registry = document_registry
        self._parallel_pages = parallel_pages

    async def execute(self, file: UploadFile) -> IngestionResult:
        start = time.perf_counter()

        async with memory_track("ingest"):
            ext = self._validate_file(file)
            content = await self._read_content(file)
            document, file_path = self._save_file(file, content, ext)

            pages, page_count = self._extractor.extract_pages(str(file_path))
            logger.info("Extracted {} pages from '{}'", page_count, document.filename)

            with measure("chunk_pages"):
                chunk_objects = await self._chunk_pages_parallel(
                    pages, document.id,
                )

            embedded_chunks, embed_time = await self._embedder.embed_chunks(chunk_objects)

            await self._store_vectors(embedded_chunks, document)

            elapsed = time.perf_counter() - start
            avg_len = round(sum(len(c.content) for c in embedded_chunks) / len(embedded_chunks), 2) if embedded_chunks else 0.0

            # Register document in the registry and set as active
            doc_info = DocumentInfo(
                document_id=document.id,
                filename=document.filename,
                uploaded_at=document.uploaded_at.isoformat(),
                page_count=page_count,
                chunk_count=len(embedded_chunks),
                size_bytes=document.size_bytes,
                status="indexed",
            )
            await self._registry.register(doc_info)
            await self._registry.set_active(document.id)

            logger.info(
                "Ingestion complete | id={} file={} pages={} chunks={} embed_time={:.2f}s total={:.2f}s",
                document.id,
                document.filename,
                page_count,
                len(embedded_chunks),
                embed_time,
                elapsed,
            )

            return IngestionResult(
                document_id=document.id,
                filename=document.filename,
                content_type=document.content_type,
                size_bytes=document.size_bytes,
                page_count=page_count,
                chunk_count=len(embedded_chunks),
                average_chunk_length=avg_len,
                embedding_dimensions=self._embedder.dimensions,
                qdrant_stored=True,
                processing_time_seconds=round(elapsed, 3),
            )

    async def _chunk_pages_parallel(
        self,
        pages: list[str],
        document_id: str,
    ) -> list[Chunk]:
        loop = asyncio.get_running_loop()

        def process_page(args: tuple[int, str]) -> list[Chunk]:
            page_num, page_text = args
            cleaned = self._cleaner.clean(page_text)
            text_chunks = self._chunker.split_text(cleaned)
            return [
                Chunk(document_id=document_id, index=0, page=page_num, content=t)
                for t in text_chunks
            ]

        tasks = [
            loop.run_in_executor(None, process_page, (i + 1, page))
            for i, page in enumerate(pages)
        ]

        sem = asyncio.Semaphore(self._parallel_pages)
        async def limited(task):
            async with sem:
                return await task

        results = await asyncio.gather(*[limited(t) for t in tasks])

        all_chunks: list[Chunk] = []
        for page_chunks in results:
            for chunk in page_chunks:
                chunk.index = len(all_chunks)
                all_chunks.append(chunk)

        return all_chunks

    async def _store_vectors(self, chunks: list[Chunk], document: Document) -> None:
        if not chunks:
            logger.warning("No vectors to store")
            return

        points = [
            PointStruct(
                id=chunk.id,
                vector=chunk.embedding,
                payload={
                    "chunk": chunk.content,
                    "document_name": document.filename,
                    "document_id": document.id,
                    "chunk_index": chunk.index,
                    "page": chunk.page,
                    "metadata": chunk.metadata,
                },
            )
            for chunk in chunks
            if chunk.embedding is not None
        ]

        if not points:
            logger.warning("No vectors to store — all chunks missing embeddings")
            return

        BATCH_SIZE = 256
        for i in range(0, len(points), BATCH_SIZE):
            batch = points[i:i + BATCH_SIZE]
            await self._qdrant.upsert(batch)
            logger.debug("Stored batch {}/{} vectors", min(i + BATCH_SIZE, len(points)), len(points))

        logger.info("Stored {} vectors in Qdrant collection '{}'", len(points), settings.QDRANT_COLLECTION)

    def _validate_file(self, file: UploadFile) -> str:
        ext = Path(file.filename or "").suffix.lower()
        if ext not in settings.ALLOWED_EXTENSIONS:
            raise InvalidFileTypeError(
                filename=file.filename or "unknown",
                allowed_extensions=list(settings.ALLOWED_EXTENSIONS),
            )
        return ext

    async def _read_content(self, file: UploadFile) -> bytes:
        content = await file.read()
        if len(content) > settings.MAX_FILE_SIZE:
            raise FileTooLargeError(
                size_bytes=len(content),
                max_bytes=settings.MAX_FILE_SIZE,
            )
        return content

    def _save_file(self, file: UploadFile, content: bytes, ext: str) -> tuple[Document, Path]:
        document = Document(
            filename=file.filename or "untitled",
            content_type=file.content_type or "application/octet-stream",
            size_bytes=len(content),
        )
        self._upload_dir.mkdir(parents=True, exist_ok=True)
        file_path = self._upload_dir / f"{document.id}{ext}"
        file_path.write_bytes(content)
        return document, file_path
