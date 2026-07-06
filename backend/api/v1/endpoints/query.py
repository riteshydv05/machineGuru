from fastapi import APIRouter, Depends
from sse_starlette import EventSourceResponse

from api.dependencies import get_query_use_case
from api.v1.schemas.query import QueryRequest, QueryResponse
from domain.value_objects.query import Query as QueryDomain
from use_cases.query import QueryUseCase

router = APIRouter(tags=["Query"])


@router.post("/query", response_model=QueryResponse)
async def query(
    request: QueryRequest,
    use_case: QueryUseCase = Depends(get_query_use_case),
) -> QueryResponse:
    domain_query = QueryDomain(
        text=request.text,
        top_k=request.top_k,
        document_id=request.document_id,
    )
    result = await use_case.execute(domain_query)
    return QueryResponse.model_validate(result.model_dump())


@router.post("/query/stream")
async def query_stream(
    request: QueryRequest,
    use_case: QueryUseCase = Depends(get_query_use_case),
) -> EventSourceResponse:
    domain_query = QueryDomain(
        text=request.text,
        top_k=request.top_k,
        document_id=request.document_id,
    )

    async def event_generator():
        async for line in use_case.execute_stream(domain_query):
            yield {"event": "message", "data": line.rstrip("\n")}

    return EventSourceResponse(event_generator())
