from fastapi import APIRouter

from api.v1.endpoints import documents, health, ingestion, query, upload

api_router = APIRouter()

api_router.include_router(health.router)
api_router.include_router(upload.router)
api_router.include_router(ingestion.router)
api_router.include_router(query.router)
api_router.include_router(documents.router)
