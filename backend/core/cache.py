import hashlib
import time
from collections import OrderedDict
from typing import Any

from loguru import logger

from core.config import settings


class LRUCache:
    def __init__(self, capacity: int = 256, ttl_seconds: int = 3600) -> None:
        self._capacity = capacity
        self._ttl = ttl_seconds
        self._cache: OrderedDict[str, tuple[Any, float]] = OrderedDict()
        self._hits = 0
        self._misses = 0

    def get(self, key: str) -> Any | None:
        if key not in self._cache:
            self._misses += 1
            return None

        value, expires_at = self._cache[key]
        if time.monotonic() > expires_at:
            del self._cache[key]
            self._misses += 1
            return None

        self._cache.move_to_end(key)
        self._hits += 1
        return value

    def set(self, key: str, value: Any) -> None:
        while len(self._cache) >= self._capacity:
            self._cache.popitem(last=False)
        self._cache[key] = (value, time.monotonic() + self._ttl)
        self._cache.move_to_end(key)

    def invalidate(self, key: str) -> None:
        self._cache.pop(key, None)

    def clear(self) -> None:
        self._cache.clear()
        self._hits = 0
        self._misses = 0

    @property
    def stats(self) -> dict:
        total = self._hits + self._misses
        return {
            "size": len(self._cache),
            "capacity": self._capacity,
            "hits": self._hits,
            "misses": self._misses,
            "hit_rate": round(self._hits / total, 3) if total else 0.0,
        }

    @staticmethod
    def make_key(*args, **kwargs) -> str:
        raw = str(args) + str(sorted(kwargs.items()))
        return hashlib.sha256(raw.encode()).hexdigest()


class EmbeddingCache(LRUCache):
    def __init__(self) -> None:
        super().__init__(capacity=1024, ttl_seconds=86400)

    def get_embedding(self, text: str) -> list[float] | None:
        key = f"emb:{hashlib.sha256(text.encode()).hexdigest()}"
        return self.get(key)

    def set_embedding(self, text: str, embedding: list[float]) -> None:
        key = f"emb:{hashlib.sha256(text.encode()).hexdigest()}"
        self.set(key, embedding)


class QueryCache(LRUCache):
    def __init__(self) -> None:
        super().__init__(capacity=128, ttl_seconds=300)

    def get_result(self, query_text: str, top_k: int) -> Any | None:
        key = f"q:{hashlib.sha256(query_text.encode()).hexdigest()}:k={top_k}"
        return self.get(key)

    def set_result(self, query_text: str, top_k: int, result: Any) -> None:
        key = f"q:{hashlib.sha256(query_text.encode()).hexdigest()}:k={top_k}"
        self.set(key, result)


embedding_cache = EmbeddingCache()
query_cache = QueryCache()
