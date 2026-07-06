from fastapi import APIRouter, Depends, File, UploadFile as FastAPIUploadFile

from api.dependencies import get_ingestion_use_case
from api.v1.schemas.ingestion import IngestionResponse
from use_cases.ingestion import IngestionUseCase

router = APIRouter(tags=["Ingestion"])


@router.post("/ingest", response_model=IngestionResponse, status_code=201)
async def ingest(
    file: FastAPIUploadFile = File(...),
    use_case: IngestionUseCase = Depends(get_ingestion_use_case),
) -> IngestionResponse:
    result = await use_case.execute(file)
    return IngestionResponse.model_validate(result.model_dump())
