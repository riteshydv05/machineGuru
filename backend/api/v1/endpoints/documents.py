from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from api.dependencies import get_document_registry, get_qdrant_repository
from core.config import settings
from infrastructure.database import QdrantRepository
from use_cases.document_registry import DocumentInfo, DocumentRegistry

router = APIRouter(prefix="/documents", tags=["Documents"])


# ── Response schemas ──────────────────────────────────────

class DocumentListResponse(BaseModel):
    documents: list[DocumentInfo]
    total: int
    active_document_id: str | None = None


class ActiveDocumentResponse(BaseModel):
    document: DocumentInfo | None = None


class DeleteResponse(BaseModel):
    deleted: bool
    document_id: str
    filename: str
    vectors_removed: bool = True


# ── Endpoints ─────────────────────────────────────────────

@router.get("", response_model=DocumentListResponse)
async def list_documents(
    registry: DocumentRegistry = Depends(get_document_registry),
    qdrant: QdrantRepository = Depends(get_qdrant_repository),
) -> DocumentListResponse:
    docs = await registry.list_all()
    active = await registry.get_active()

    # Enrich documents with actual embedding counts from Qdrant
    enriched_docs = []
    for doc in docs:
        try:
            embedding_count = await qdrant.count_by_document(doc.document_id)
            doc.embedding_count = embedding_count
        except Exception:
            pass  # Keep existing count if Qdrant fails
        enriched_docs.append(doc)

    return DocumentListResponse(
        documents=enriched_docs,
        total=len(enriched_docs),
        active_document_id=active.document_id if active else None,
    )


@router.get("/active", response_model=ActiveDocumentResponse)
async def get_active_document(
    registry: DocumentRegistry = Depends(get_document_registry),
) -> ActiveDocumentResponse:
    active = await registry.get_active()
    return ActiveDocumentResponse(document=active)


@router.put("/active/{document_id}", response_model=ActiveDocumentResponse)
async def set_active_document(
    document_id: str,
    registry: DocumentRegistry = Depends(get_document_registry),
) -> ActiveDocumentResponse:
    doc = await registry.set_active(document_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document '{document_id}' not found")
    return ActiveDocumentResponse(document=doc)


@router.delete("/{document_id}", response_model=DeleteResponse)
async def delete_document(
    document_id: str,
    registry: DocumentRegistry = Depends(get_document_registry),
    qdrant: QdrantRepository = Depends(get_qdrant_repository),
) -> DeleteResponse:
    doc = await registry.get(document_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document '{document_id}' not found")

    filename = doc.filename

    # Remove vectors from Qdrant
    vectors_removed = True
    try:
        await qdrant.delete_by_document(document_id)
    except Exception:
        vectors_removed = False

    # Remove from registry (also cleans up files from disk)
    await registry.delete(document_id, upload_dir=settings.UPLOAD_DIR)

    return DeleteResponse(
        deleted=True,
        document_id=document_id,
        filename=filename,
        vectors_removed=vectors_removed,
    )
