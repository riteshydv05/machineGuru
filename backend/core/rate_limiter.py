import time
from collections import defaultdict
from typing import Callable

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from loguru import logger


class TokenBucket:
    def __init__(self, rate: float, burst: int) -> None:
        self._rate = rate
        self._burst = burst
        self._tokens = float(burst)
        self._last = time.monotonic()

    def consume(self) -> bool:
        now = time.monotonic()
        self._tokens = min(self._burst, self._tokens + (now - self._last) * self._rate)
        self._last = now
        if self._tokens >= 1.0:
            self._tokens -= 1.0
            return True
        return False


class RateLimiterMiddleware:
    def __init__(
        self,
        rate: float = 10.0,
        burst: int = 20,
        whitelist: set[str] | None = None,
    ) -> None:
        self._buckets: dict[str, TokenBucket] = defaultdict(lambda: TokenBucket(rate, burst))
        self._whitelist = whitelist or {"/api/v1/health", "/api/v1/stats", "/metrics", "/docs", "/redoc", "/openapi.json"}

    async def __call__(self, request: Request, call_next: Callable) -> JSONResponse:
        if request.method == "OPTIONS":
            return await call_next(request)

        path = request.url.path
        if any(path.startswith(w) for w in self._whitelist):
            return await call_next(request)

        client_ip = request.client.host if request.client else "unknown"
        bucket = self._buckets[client_ip]

        if not bucket.consume():
            logger.warning("Rate limit exceeded | ip={} path={}", client_ip, path)
            return JSONResponse(
                status_code=429,
                content={
                    "error": "rate_limit_exceeded",
                    "message": "Too many requests. Try again later.",
                    "retry_after_seconds": 1,
                },
                headers={"Retry-After": "1"},
            )

        return await call_next(request)
