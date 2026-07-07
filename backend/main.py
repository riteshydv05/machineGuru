import os
import signal
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from loguru import logger

from api.dependencies import get_document_registry, get_qdrant_repository
from api.v1.router import api_router
from api.v1.schemas.health import ErrorResponse
from core.benchmark import _get_cpu_percent, _get_gpu_info, _get_memory_mb
from core.cache import embedding_cache, query_cache
from core.concurrency import llm_limiter, embedding_limiter, qdrant_limiter
from core.config import settings
from core.exceptions import MachineGuruError
from core.logging import set_request_id, setup_logging
from core.memory import ModelRegistry
from core.rate_limiter import RateLimiterMiddleware as CustomRateLimiter

_SHUTTING_DOWN = False

try:
    from core.metrics import metrics_endpoint, memory_usage, gpu_memory_usage, gpu_utilization
    from core.metrics import concurrent_llm, concurrent_embeddings, concurrent_qdrant, model_loaded
    from core.metrics import request_duration, request_total
    _METRICS_AVAILABLE = True
except ImportError:
    _METRICS_AVAILABLE = False


def handle_sigterm(*args):
    global _SHUTTING_DOWN
    _SHUTTING_DOWN = True
    logger.warning("SIGTERM received — initiating graceful shutdown")


signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)


@asynccontextmanager
async def lifespan(application: FastAPI):
    setup_logging()
    Path(settings.UPLOAD_DIR).mkdir(parents=True, exist_ok=True)
    Path(settings.LOG_DIR).mkdir(parents=True, exist_ok=True)

    qdrant = get_qdrant_repository()
    await qdrant.ensure_collection()

    doc_registry = get_document_registry()
    await doc_registry.load()

    logger.info("Application starting | version={} debug={}", settings.VERSION, settings.DEBUG)
    yield

    unloaded = ModelRegistry.unload_all()
    logger.info("Application shutting down | models_unloaded={} uptime={:.0f}s", unloaded, time.monotonic())


app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    lifespan=lifespan,
    docs_url="/docs" if settings.DEBUG else None,
    redoc_url="/redoc" if settings.DEBUG else None,
    description="Industrial RAG backend — offline, on-device, clean architecture.",
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE", "PUT", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-Request-ID"],
)


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    if _SHUTTING_DOWN:
        return JSONResponse(
            status_code=503,
            content={"error": "shutting_down", "message": "Server is shutting down"},
        )

    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    set_request_id(request_id)
    start = time.perf_counter()
    mem_before = _get_memory_mb()

    try:
        response = await call_next(request)
    except Exception as exc:
        elapsed = time.perf_counter() - start
        if _METRICS_AVAILABLE:
            request_total.labels(method=request.method, endpoint=request.url.path, status="5xx").inc()
            request_duration.labels(method=request.method, endpoint=request.url.path).observe(elapsed)
        raise

    elapsed = time.perf_counter() - start
    mem_after = _get_memory_mb()

    response.headers["X-Request-ID"] = request_id
    response.headers["X-Process-Time"] = f"{elapsed:.3f}"

    if _METRICS_AVAILABLE:
        status_group = f"{response.status_code // 100}xx"
        request_total.labels(method=request.method, endpoint=request.url.path, status=status_group).inc()
        request_duration.labels(method=request.method, endpoint=request.url.path).observe(elapsed)

        memory_usage.labels(type="rss").set(mem_after)
        gpu_info = _get_gpu_info()
        if gpu_info.get("available"):
            gpu_memory_usage.set(gpu_info["memory_mb"])
            gpu_utilization.set(gpu_info["util_pct"])

    if settings.ENABLE_REQUEST_LOGGING:
        log_level = logger.warning if elapsed > 1.0 else logger.info
        log_level(
            "{} {} | status={} time={:.3f}s ram={:+.1f}MB",
            request.method,
            request.url.path,
            response.status_code,
            elapsed,
            mem_after - mem_before,
        )

    set_request_id(None)
    return response


@app.middleware("http")
async def rate_limiter_middleware(request: Request, call_next):
    limiter = CustomRateLimiter()
    return await limiter(request, call_next)


@app.exception_handler(MachineGuruError)
async def machine_guru_error_handler(request: Request, exc: MachineGuruError) -> JSONResponse:
    logger.warning(
        "Handled exception | id={} code={} status={} message={}",
        exc.error_id,
        exc.error_code,
        exc.status_code,
        exc.message,
    )
    return JSONResponse(
        status_code=exc.status_code,
        content=ErrorResponse(
            error_id=exc.error_id,
            error_code=exc.error_code,
            message=exc.message,
            detail=exc.detail if settings.DEBUG else None,
        ).model_dump(),
    )


@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    error_id = str(uuid.uuid4())
    logger.opt(exception=exc).error("Unhandled exception | id={}", error_id)
    return JSONResponse(
        status_code=500,
        content=ErrorResponse(
            error_id=error_id,
            error_code="INTERNAL_ERROR",
            message="An unexpected error occurred",
            detail=str(exc) if settings.DEBUG else None,
        ).model_dump(),
    )


if _METRICS_AVAILABLE and settings.METRICS_ENABLED:
    @app.get("/metrics")
    async def metrics():
        return Response(
            content=metrics_endpoint(),
            media_type="text/plain; version=0.0.4",
            headers={"Cache-Control": "no-cache"},
        )


@app.get("/api/v1/stats")
async def get_stats():
    mem = _get_memory_mb()
    cpu = _get_cpu_percent()
    gpu = _get_gpu_info()
    models = ModelRegistry.memory_report()

    return {
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "memory_mb": round(mem, 1),
        "cpu_percent": cpu,
        "gpu": gpu,
        "models": models,
        "caches": {
            "embedding": embedding_cache.stats,
            "query": query_cache.stats,
        },
        "concurrency": {
            "llm": llm_limiter.stats,
            "embedding": embedding_limiter.stats,
            "qdrant": qdrant_limiter.stats,
        },
        "shutting_down": _SHUTTING_DOWN,
    }


app.include_router(api_router, prefix="/api/v1")
