from functools import lru_cache

from core.config import settings
from infrastructure.database import QdrantRepository
from infrastructure.embedding import EmbeddingService
from infrastructure.llm import OllamaService
from use_cases.document_registry import DocumentRegistry
from use_cases.health import HealthUseCase
from use_cases.ingestion import IngestionUseCase
from use_cases.query import QueryUseCase
from use_cases.upload import UploadUseCase


@lru_cache
def get_qdrant_repository() -> QdrantRepository:
    return QdrantRepository(
        host=settings.QDRANT_HOST,
        port=settings.QDRANT_PORT,
        collection_name=settings.QDRANT_COLLECTION,
        vector_size=384,
    )


@lru_cache
def get_document_registry() -> DocumentRegistry:
    return DocumentRegistry(persist_path=f"{settings.UPLOAD_DIR}/document_registry.json")


@lru_cache
def get_health_use_case() -> HealthUseCase:
    return HealthUseCase(qdrant_repository=get_qdrant_repository())


@lru_cache
def get_upload_use_case() -> UploadUseCase:
    return UploadUseCase()


@lru_cache
def get_ingestion_use_case() -> IngestionUseCase:
    return IngestionUseCase(
        qdrant_repository=get_qdrant_repository(),
        document_registry=get_document_registry(),
    )


@lru_cache
def get_ollama_service() -> OllamaService:
    return OllamaService(
        base_url=settings.OLLAMA_BASE_URL,
        model=settings.LLM_MODEL,
    )


@lru_cache
def get_query_use_case() -> QueryUseCase:
    return QueryUseCase(
        embedder=EmbeddingService(),
        qdrant_repository=get_qdrant_repository(),
        llm=get_ollama_service(),
    )
