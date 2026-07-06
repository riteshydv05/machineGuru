import asyncio
from collections import defaultdict
from typing import Any, Callable

from loguru import logger


class RateLimiter:
    def __init__(self, max_concurrent: int = 4) -> None:
        self._sem = asyncio.Semaphore(max_concurrent)
        self._max = max_concurrent
        self._active = 0
        self._queued = 0
        self._completed = 0

    async def acquire(self) -> None:
        self._queued += 1
        await self._sem.acquire()
        self._queued -= 1
        self._active += 1

    def release(self) -> None:
        self._active -= 1
        self._completed += 1
        self._sem.release()

    @property
    def stats(self) -> dict:
        return {
            "max_concurrent": self._max,
            "active": self._active,
            "queued": self._queued,
            "completed": self._completed,
        }


llm_limiter = RateLimiter(max_concurrent=2)
embedding_limiter = RateLimiter(max_concurrent=1)
qdrant_limiter = RateLimiter(max_concurrent=8)


class RequestCoalescer:
    def __init__(self) -> None:
        self._pending: dict[str, asyncio.Future] = {}

    async def get_or_compute(
        self,
        key: str,
        factory: Callable[[], Any],
    ) -> Any:
        if key in self._pending:
            logger.debug("Coalescing duplicate request | key={}", key[:40])
            return await self._pending[key]

        future = asyncio.get_event_loop().create_future()
        self._pending[key] = future
        try:
            result = await factory()
            if not future.done():
                future.set_result(result)
            return result
        except Exception as e:
            if not future.done():
                future.set_exception(e)
            raise
        finally:
            self._pending.pop(key, None)


query_coalescer = RequestCoalescer()


class AdaptiveBatcher:
    def __init__(self, max_batch_size: int = 64, max_wait_ms: float = 50.0) -> None:
        self._max_batch = max_batch_size
        self._max_wait = max_wait_ms / 1000.0
        self._queue: list[tuple[Any, asyncio.Future]] = []
        self._lock = asyncio.Lock()
        self._task: asyncio.Task | None = None

    async def submit(self, item: Any) -> Any:
        future = asyncio.get_event_loop().create_future()
        async with self._lock:
            self._queue.append((item, future))
            if len(self._queue) >= self._max_batch:
                if self._task and not self._task.done():
                    self._task.cancel()
                self._task = asyncio.create_task(self._flush())
            elif self._task is None or self._task.done():
                self._task = asyncio.create_task(self._flush())
        return await future

    async def _flush(self) -> None:
        await asyncio.sleep(self._max_wait)
        async with self._lock:
            batch = self._queue[:]
            self._queue.clear()

        if not batch:
            return

        items = [b[0] for b in batch]
        futures = [b[1] for b in batch]
        try:
            raise NotImplementedError("override _process_batch")
        except Exception as e:
            for f in futures:
                if not f.done():
                    f.set_exception(e)

    async def _process_batch(self, items: list) -> list:
        raise NotImplementedError
