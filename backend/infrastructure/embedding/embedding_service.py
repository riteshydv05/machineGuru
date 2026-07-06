import asyncio
import time
from typing import Callable

from loguru import logger

from core.benchmark import measure
from core.cache import embedding_cache
from core.concurrency import embedding_limiter
from core.exceptions import EmbeddingError
from core.memory import memory_track
from domain.value_objects.chunk import Chunk
from infrastructure.embedding.model_loader import get_embedding_model


class EmbeddingService:
    def __init__(self, batch_size: int = 64) -> None:
        self._batch_size = batch_size

    async def embed_chunks(
        self,
        chunks: list[Chunk],
    ) -> tuple[list[Chunk], float]:
        if not chunks:
            return chunks, 0.0

        async with memory_track("embed_chunks"):
            await embedding_limiter.acquire()
            try:
                with measure("embed_chunks_batch"):
                    result, elapsed = await self._run_in_executor(
                        self._embed_sync,
                        chunks,
                    )
                embedding_limiter.release()

                cached = sum(1 for c in chunks if c.embedding is not None)
                logger.info(
                    "Embedded {}/{} chunks | dim={} time={:.2f}s batch={} cached={}",
                    len(result) - cached,
                    len(result),
                    self.dimensions,
                    elapsed,
                    self._batch_size,
                    cached,
                )

                return result, elapsed
            except Exception as exc:
                embedding_limiter.release()
                raise

    def _embed_sync(self, chunks: list[Chunk]) -> tuple[list[Chunk], float]:
        model = get_embedding_model()
        start = time.perf_counter()

        uncached_indices: list[int] = []
        uncached_texts: list[str] = []

        for i, chunk in enumerate(chunks):
            cached_emb = embedding_cache.get_embedding(chunk.content)
            if cached_emb is not None:
                chunk.embedding = cached_emb
            else:
                uncached_indices.append(i)
                uncached_texts.append(f"passage: {chunk.content}")

        if uncached_texts:
            try:
                embeddings = model.encode(
                    uncached_texts,
                    batch_size=self._batch_size,
                    normalize_embeddings=True,
                    show_progress_bar=False,
                )
            except Exception as exc:
                logger.error("Embedding generation failed | error={}", exc)
                raise EmbeddingError(
                    message="Failed to generate embeddings",
                    detail=str(exc),
                ) from exc

            for idx, embedding in zip(uncached_indices, embeddings):
                emb_list = embedding.tolist()
                chunks[idx].embedding = emb_list
                embedding_cache.set_embedding(chunks[idx].content, emb_list)

        elapsed = time.perf_counter() - start
        return chunks, elapsed

    async def embed_query(self, text: str) -> list[float]:
        cached = embedding_cache.get_embedding(text)
        if cached is not None:
            logger.debug("Query embedding cache hit")
            return cached

        await embedding_limiter.acquire()
        try:
            embedding = await self._run_in_executor(
                self._embed_query_sync,
                text,
            )
            embedding_limiter.release()
            embedding_cache.set_embedding(text, embedding)
            return embedding
        except Exception:
            embedding_limiter.release()
            raise

    def _embed_query_sync(self, text: str) -> list[float]:
        model = get_embedding_model()
        embedding = model.encode(
            f"query: {text}",
            normalize_embeddings=True,
        )
        return embedding.tolist()

    async def _run_in_executor(
        self,
        func: Callable,
        *args,
    ) -> any:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, func, *args)

    @property
    def dimensions(self) -> int:
        from infrastructure.embedding.model_loader import _model_instance
        return _model_instance.dimensions
