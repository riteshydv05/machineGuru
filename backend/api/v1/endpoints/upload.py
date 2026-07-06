from fastapi import APIRouter, Depends, UploadFile as FastAPIUploadFile, File

from api.dependencies import get_upload_use_case
from api.v1.schemas.upload import UploadResponse
from use_cases.upload import UploadUseCase

router = APIRouter(tags=["Upload"])


@router.post("/upload", response_model=UploadResponse, status_code=201)
async def upload(
    file: FastAPIUploadFile = File(...),
    use_case: UploadUseCase = Depends(get_upload_use_case),
) -> UploadResponse:
    document = await use_case.execute(file)
    return UploadResponse.model_validate(document.model_dump())
