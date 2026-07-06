from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from api.dependencies import get_document_registry, get_qdrant_repository
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


# ── Endpoints ─────────────────────────────────────────────

@router.get("", response_model=DocumentListResponse)
async def list_documents(
    registry: DocumentRegistry = Depends(get_document_registry),
) -> DocumentListResponse:
    docs = await registry.list_all()
    active = await registry.get_active()
    return DocumentListResponse(
        documents=docs,
        total=len(docs),
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


@router.delete("/{document_id}")
async def delete_document(
    document_id: str,
    registry: DocumentRegistry = Depends(get_document_registry),
    qdrant: QdrantRepository = Depends(get_qdrant_repository),
):
    doc = await registry.get(document_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document '{document_id}' not found")

    # Remove vectors from Qdrant
    await qdrant.delete_by_document(document_id)

    # Remove from registry
    await registry.delete(document_id)

    return {"deleted": True, "document_id": document_id, "filename": doc.filename}
