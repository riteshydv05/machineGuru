import os
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


def _resolve_path(raw: str) -> str:
    """
    Resolve a path to absolute.
    Relative paths are resolved from PROJECT_ROOT (two levels up from this file:
    backend/core/config.py → backend/ → project_root/).
    This ensures paths like './storage/uploads' work correctly regardless
    of the working directory the process is started from.
    """
    p = Path(raw)
    if p.is_absolute():
        return str(p)
    # Project root = parent of the backend directory
    project_root = Path(__file__).parent.parent.parent
    return str((project_root / p).resolve())


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", "../.env"),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── Application ──────────────────────────────────────────
    PROJECT_NAME: str = "MachineGuru"
    VERSION: str = "0.2.0"
    DEBUG: bool = False

    # ── Network ──────────────────────────────────────────────
    BACKEND_PORT: int = 8001
    CORS_ORIGINS: list[str] = [
        "http://localhost:5173",
        "http://localhost:5174",
        "http://localhost:3000",
        "http://localhost:80",
    ]

    # ── Ollama ───────────────────────────────────────────────
    OLLAMA_BASE_URL: str = "http://localhost:11434"
    LLM_MODEL: str = "llama3.2:1b"
    VISION_MODEL: str = "llava:7b"
    EMBEDDING_MODEL: str = "intfloat/multilingual-e5-small"

    # LLM generation parameters
    NUM_CTX: int = 8192
    NUM_PREDICT: int = 4096
    LLM_TEMPERATURE: float = 0.1
    LLM_KEEP_ALIVE: str = "10m"

    # Multimodal / Vision
    ENABLE_MULTIMODAL: bool = True

    # Hybrid Retrieval
    BM25_WEIGHT: float = 0.3
    DENSE_WEIGHT: float = 0.7
    SCORE_THRESHOLD: float = 0.15

    # ── Qdrant ───────────────────────────────────────────────
    QDRANT_HOST: str = "localhost"
    QDRANT_PORT: int = 6333
    QDRANT_COLLECTION: str = "machine_guru"

    # ── Storage paths (resolved to absolute in __init__) ─────
    # Accept relative paths from .env; they will be resolved to
    # absolute paths relative to the project root.
    UPLOAD_DIR: str = "./storage/uploads"
    LOG_DIR: str = "./logs"
    CACHE_DIR: str = "./storage/cache"
    EMBEDDINGS_DIR: str = "./storage/embeddings"

    # ── Document Ingestion ───────────────────────────────────
    MAX_FILE_SIZE: int = 50 * 1024 * 1024   # 50 MB
    ALLOWED_EXTENSIONS: set[str] = {".pdf", ".txt", ".docx"}
    CHUNK_SIZE: int = 512
    CHUNK_OVERLAP: int = 64
    TOP_K: int = 5
    BATCH_SIZE: int = 64
    PARALLEL_PAGES: int = 4

    # ── Performance ──────────────────────────────────────────
    CACHE_TTL_QUERY: int = 300
    CACHE_TTL_EMBEDDING: int = 86400
    MAX_CONCURRENT_LLM: int = 2
    MAX_CONCURRENT_EMBEDDING: int = 1
    MAX_CONCURRENT_QDRANT: int = 4
    MEMORY_BUDGET_MB: int = 2048
    IDLE_MODEL_TIMEOUT: int = 300

    # ── Features ─────────────────────────────────────────────
    ENABLE_STREAMING: bool = True
    ENABLE_CACHING: bool = True
    ENABLE_BENCHMARK: bool = True
    ENABLE_MULTIMODAL: bool = True

    # ── Logging ──────────────────────────────────────────────
    JSON_LOGGING: bool = False
    LOG_LEVEL: str = "INFO"
    LOG_RETENTION_DAYS: int = 30
    LOG_MAX_SIZE_MB: int = 10

    # ── Request Handling ─────────────────────────────────────
    ENABLE_REQUEST_LOGGING: bool = True
    REQUEST_TIMEOUT_SECONDS: int = 120

    # ── Metrics ──────────────────────────────────────────────
    METRICS_ENABLED: bool = True

    def model_post_init(self, __context):
        """Resolve relative paths to absolute after model initialisation."""
        object.__setattr__(self, "UPLOAD_DIR", _resolve_path(self.UPLOAD_DIR))
        object.__setattr__(self, "LOG_DIR", _resolve_path(self.LOG_DIR))
        object.__setattr__(self, "CACHE_DIR", _resolve_path(self.CACHE_DIR))
        object.__setattr__(self, "EMBEDDINGS_DIR", _resolve_path(self.EMBEDDINGS_DIR))

    def validate_startup(self) -> list[str]:
        """
        Return a list of configuration warnings/errors.
        Call this at startup to surface misconfiguration early.
        """
        issues = []
        if self.DEBUG:
            issues.append("WARNING: DEBUG=true — disable in production")
        if "localhost" not in self.OLLAMA_BASE_URL and "127.0.0.1" not in self.OLLAMA_BASE_URL:
            pass  # Remote Ollama is valid
        if self.MEMORY_BUDGET_MB < 512:
            issues.append("WARNING: MEMORY_BUDGET_MB is very low (<512 MB)")
        if self.MAX_FILE_SIZE > 200 * 1024 * 1024:
            issues.append("WARNING: MAX_FILE_SIZE >200 MB may exhaust memory on Jetson")
        return issues


settings = Settings()
