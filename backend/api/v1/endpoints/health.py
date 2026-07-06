from fastapi import APIRouter, Depends

from api.dependencies import get_health_use_case
from api.v1.schemas.health import HealthResponse
from use_cases.health import HealthUseCase

router = APIRouter(tags=["Health"])


@router.get("/health", response_model=HealthResponse)
async def health(
    use_case: HealthUseCase = Depends(get_health_use_case),
) -> HealthResponse:
    result = await use_case.execute()
    return HealthResponse.model_validate(result.model_dump())
