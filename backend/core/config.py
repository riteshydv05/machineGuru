from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",   # ignore unknown env vars (e.g. DEVICE, USE_FP16)
    )

    PROJECT_NAME: str = "MachineGuru"
    VERSION: str = "0.1.0"
    DEBUG: bool = True

    CORS_ORIGINS: list[str] = ["http://localhost:5173"]

    OLLAMA_BASE_URL: str = "http://localhost:11434"
    LLM_MODEL: str = "llama3.2:1b"
    EMBEDDING_MODEL: str = "intfloat/multilingual-e5-small"

    QDRANT_HOST: str = "localhost"
    QDRANT_PORT: int = 6333
    QDRANT_COLLECTION: str = "machine_knowledge"

    UPLOAD_DIR: str = "uploads"
    MAX_FILE_SIZE: int = 50 * 1024 * 1024
    ALLOWED_EXTENSIONS: set[str] = {".pdf", ".txt", ".docx"}
    CHUNK_SIZE: int = 512
    CHUNK_OVERLAP: int = 150
    TOP_K: int = 8

    BATCH_SIZE: int = 64
    PARALLEL_PAGES: int = 4
    CACHE_TTL_QUERY: int = 300
    CACHE_TTL_EMBEDDING: int = 86400
    MAX_CONCURRENT_LLM: int = 2
    MAX_CONCURRENT_EMBEDDING: int = 1
    MEMORY_BUDGET_MB: int = 2048
    IDLE_MODEL_TIMEOUT: int = 300

    ENABLE_STREAMING: bool = True
    ENABLE_CACHING: bool = True
    ENABLE_BENCHMARK: bool = True

    JSON_LOGGING: bool = False
    LOG_LEVEL: str = "INFO"
    LOG_RETENTION_DAYS: int = 30
    LOG_MAX_SIZE_MB: int = 10
    LOG_DIR: str = "logs"

    ENABLE_REQUEST_LOGGING: bool = True
    REQUEST_TIMEOUT_SECONDS: int = 120

    METRICS_ENABLED: bool = True


settings = Settings()
