import json
import re
import time
from collections.abc import AsyncGenerator
from datetime import datetime, timezone

from loguru import logger
from pydantic import BaseModel

from core.benchmark import bench, query_throughput
from core.cache import query_cache
from core.config import settings
from core.concurrency import query_coalescer
from core.exceptions import QueryValidationError
from core.memory import memory_track
from domain.value_objects.query import Query
from infrastructure.database import QdrantRepository
from infrastructure.embedding import EmbeddingService
from infrastructure.llm import OllamaService
from use_cases.hybrid_retriever import HybridRetriever

FALLBACK_ANSWER = "I could not find this information in the uploaded documents."

# ─── Improved Prompt — Production Quality ──────────────────────────────
# Designed for thorough, expert-level technical answers from industrial manuals.

SYSTEM_PROMPT = """You are MachineGuru, a senior industrial maintenance engineer and technical documentation expert.

Your purpose is to help technicians, engineers, and operators by providing thorough, detailed, and actionable answers using ONLY the context provided below.

## How to Answer

1. **Read ALL provided context carefully** before answering. Combine information from multiple sources when they contain complementary details.

2. **Be thorough and detailed:**
   - Write multiple paragraphs when the topic warrants it.
   - Use bullet points or numbered lists for procedures, specifications, or multiple items.
   - Explain technical terms and acronyms when they first appear.
   - Include specific values: error codes, part numbers, torque specifications, voltage ratings, pressure settings, temperature ranges, etc.

3. **Structure your answer clearly:**
   - Start with a direct answer to the question.
   - Follow with supporting details, procedures, or explanations.
   - Include safety warnings or precautions if they appear in the context.
   - Mention maintenance intervals, recommended tools, or required materials if relevant.

4. **Cite sources naturally** using [Source N] format when referencing specific information.

5. **Handle partial information:** If the context contains some but not all relevant information, explain what IS available and note what additional information might be needed.

6. **Only say "I could not find this information in the uploaded documents"** when the context contains absolutely NO relevant information. Even tangentially related content should be presented with appropriate caveats.

## What NOT to Do
- Do NOT give one-sentence answers when more detail is available.
- Do NOT refuse to answer if the context contains even partially relevant information.
- Do NOT make up information that is not in the provided context.
- Do NOT simply list source references without explanation."""

USER_PROMPT_TEMPLATE = """Context from technical documentation:
{context}

---

Question: {question}

Provide a thorough, detailed, expert-level answer based on the context above. Use paragraphs for explanation and bullet points for lists, specifications, or procedures. Include all relevant details such as part numbers, specifications, warnings, and maintenance procedures found in the context:"""

CITATION_RE = re.compile(r'\[Source\s+(\d+)\]')


class SourceReference(BaseModel):
    document_id: str
    filename: str
    page: int | None = None
    chunk_index: int | None = None
    score: float | None = None
    chunk_type: str = "text"
    figure_number: str | None = None
    image_path: str | None = None


class Citation(BaseModel):
    source_index: int
    document_id: str
    filename: str
    page: int | None = None
    chunk_index: int | None = None


class QueryResult(BaseModel):
    answer: str
    sources: list[SourceReference]
    citations: list[Citation] | None = None
    query_text: str
    timestamp: str
    timings: dict | None = None
    debug: dict | None = None
    model: str | None = None


class QueryUseCase:
    def __init__(
        self,
        embedder: EmbeddingService,
        qdrant_repository: QdrantRepository,
        llm: OllamaService,
    ) -> None:
        self._embedder = embedder
        self._qdrant = qdrant_repository
        self._llm = llm
        self._hybrid = HybridRetriever(embedder, qdrant_repository)

    @bench("query")
    async def execute(self, query: Query) -> QueryResult:
        self._validate(query)
        query_throughput.record()

        cached = query_cache.get_result(query.text, query.top_k)
        if cached:
            logger.info("Query cache hit | text='{}'", query.text[:80])
            return QueryResult.model_validate(cached)

        async def _do_execute() -> QueryResult:
            async with memory_track("query_execute"):
                timings: dict[str, float] = {}
                t0 = time.perf_counter()

                logger.info("Query received | text='{}' top_k={} doc_filter={}", query.text[:80], query.top_k, query.document_id)

                # Stage 1: Embed query
                t = time.perf_counter()
                query_vector = await self._embedder.embed_query(query.text)
                timings["embedding_ms"] = round((time.perf_counter() - t) * 1000, 1)

                # Stage 2: Hybrid search (Dense + BM25)
                t = time.perf_counter()
                results, retrieval_timings = await self._hybrid.retrieve(
                    query_text=query.text,
                    query_vector=query_vector,
                    top_k=query.top_k,
                    document_id=query.document_id,
                    page_filter=query.page_filter,
                    chunk_type_filter=query.chunk_type_filter,
                )
                timings["qdrant_search_ms"] = round((time.perf_counter() - t) * 1000, 1)
                timings.update(retrieval_timings)

                # Deduplicate and filter low-relevance chunks
                results = self._deduplicate_results(results)
                results = self._filter_low_relevance(results)
                timings["chunks_after_dedup"] = len(results)

                sources = [
                    SourceReference(
                        document_id=result.payload.get("document_id", ""),
                        filename=result.payload.get("document_name", ""),
                        page=result.payload.get("page"),
                        chunk_index=result.payload.get("chunk_index"),
                        score=result.score,
                        chunk_type=result.payload.get("chunk_type", "text"),
                        figure_number=result.payload.get("figure_number"),
                        image_path=result.payload.get("image_path"),
                    )
                    for result in results
                ]

                # Stage 3: Build context + prompt
                t = time.perf_counter()
                context = self._build_context(results)
                user_prompt = USER_PROMPT_TEMPLATE.format(context=context, question=query.text)
                timings["prompt_build_ms"] = round((time.perf_counter() - t) * 1000, 1)

                # Token count estimates
                timings["prompt_token_count"] = len(user_prompt) // 4
                timings["context_token_count"] = len(context) // 4
                timings["system_prompt_token_count"] = len(SYSTEM_PROMPT) // 4

                # Log full prompt for debugging
                self._log_prompt_debug(query.text, results, user_prompt)

                # Stage 4: LLM generation
                t = time.perf_counter()
                answer = await self._generate_answer(query.text, results)
                timings["llm_generation_ms"] = round((time.perf_counter() - t) * 1000, 1)

                timings["total_ms"] = round((time.perf_counter() - t0) * 1000, 1)
                timings["chunks_retrieved"] = len(results)
                timings["context_chars"] = len(context)

                # Slow query warning
                if timings["llm_generation_ms"] > 10000:
                    logger.warning(
                        "Slow LLM generation | time={}ms model={}",
                        timings["llm_generation_ms"],
                        self._llm._model,
                    )

                logger.info(
                    "Query complete | embed={}ms qdrant={}ms llm={}ms total={}ms chunks={} context={}chars",
                    timings["embedding_ms"],
                    timings["qdrant_search_ms"],
                    timings["llm_generation_ms"],
                    timings["total_ms"],
                    timings["chunks_retrieved"],
                    timings["context_chars"],
                )

                # Log the raw answer
                logger.info("RAW LLM ANSWER:\n{}", answer)

                citations = self._parse_citations(answer, sources)

                # Build debug info if enabled
                debug_info = None
                if settings.DEBUG:
                    debug_info = self._build_debug(query.text, results, user_prompt, answer, timings)

                return QueryResult(
                    answer=answer,
                    sources=sources,
                    citations=citations,
                    query_text=query.text,
                    timestamp=datetime.now(timezone.utc).isoformat(),
                    timings=timings,
                    debug=debug_info,
                    model=self._llm._model,
                )

        result = await query_coalescer.get_or_compute(
            f"query:{query.text}:k={query.top_k}",
            _do_execute,
        )

        query_cache.set_result(query.text, query.top_k, result.model_dump())
        return result

    async def execute_stream(
        self,
        query: Query,
    ) -> AsyncGenerator[str, None]:
        self._validate(query)
        query_throughput.record()

        async with memory_track("query_stream"):
            timings: dict[str, float] = {}
            t0 = time.perf_counter()

            logger.info("Query stream | text='{}' top_k={} doc_filter={}", query.text[:80], query.top_k, query.document_id)

            # Stage 1: Embed query
            t = time.perf_counter()
            query_vector = await self._embedder.embed_query(query.text)
            timings["embedding_ms"] = round((time.perf_counter() - t) * 1000, 1)

            # Stage 2: Hybrid search (Dense + BM25)
            t = time.perf_counter()
            results, retrieval_timings = await self._hybrid.retrieve(
                query_text=query.text,
                query_vector=query_vector,
                top_k=query.top_k,
                document_id=query.document_id,
                page_filter=query.page_filter,
                chunk_type_filter=query.chunk_type_filter,
            )
            timings["qdrant_search_ms"] = round((time.perf_counter() - t) * 1000, 1)
            timings.update(retrieval_timings)

            # Deduplicate and filter
            results = self._deduplicate_results(results)
            results = self._filter_low_relevance(results)

            sources = [
                SourceReference(
                    document_id=result.payload.get("document_id", ""),
                    filename=result.payload.get("document_name", ""),
                    page=result.payload.get("page"),
                    chunk_index=result.payload.get("chunk_index"),
                    score=result.score,
                    chunk_type=result.payload.get("chunk_type", "text"),
                    figure_number=result.payload.get("figure_number"),
                    image_path=result.payload.get("image_path"),
                )
                for result in results
            ]

            yield json.dumps({"type": "sources", "sources": [s.model_dump() for s in sources]}) + "\n"

            if not results:
                yield json.dumps({"type": "token", "text": FALLBACK_ANSWER}) + "\n"
                timings["total_ms"] = round((time.perf_counter() - t0) * 1000, 1)
                timings["chunks_retrieved"] = 0
                yield json.dumps({"type": "done", "citations": None, "timings": timings, "model": self._llm._model}) + "\n"
                return

            # Stage 3: Prompt construction
            t = time.perf_counter()
            context = self._build_context(results)
            user_prompt = USER_PROMPT_TEMPLATE.format(context=context, question=query.text)
            timings["prompt_build_ms"] = round((time.perf_counter() - t) * 1000, 1)
            timings["context_chars"] = len(context)
            timings["prompt_token_count"] = len(user_prompt) // 4
            timings["context_token_count"] = len(context) // 4

            # Log full prompt
            self._log_prompt_debug(query.text, results, user_prompt)

            # Stage 4: LLM generation (streaming)
            t = time.perf_counter()
            answer_parts: list[str] = []
            first_token_sent = False
            async for token in self._llm.generate_stream(
                system_prompt=SYSTEM_PROMPT,
                user_prompt=user_prompt,
                temperature=settings.LLM_TEMPERATURE,
            ):
                if not first_token_sent:
                    timings["first_token_ms"] = round((time.perf_counter() - t) * 1000, 1)
                    first_token_sent = True
                answer_parts.append(token)
                yield json.dumps({"type": "token", "text": token}) + "\n"

            timings["llm_generation_ms"] = round((time.perf_counter() - t) * 1000, 1)
            timings["total_ms"] = round((time.perf_counter() - t0) * 1000, 1)
            timings["chunks_retrieved"] = len(results)

            # Slow query warning
            if timings["llm_generation_ms"] > 10000:
                logger.warning(
                    "Slow LLM generation | time={}ms model={}",
                    timings["llm_generation_ms"],
                    self._llm._model,
                )

            answer = "".join(answer_parts)
            logger.info("RAW STREAM ANSWER:\n{}", answer)

            logger.info(
                "Query stream complete | embed={}ms qdrant={}ms prompt={}ms first_token={}ms llm={}ms total={}ms chunks={} ctx={}chars",
                timings["embedding_ms"],
                timings["qdrant_search_ms"],
                timings.get("prompt_build_ms", "?"),
                timings.get("first_token_ms", "?"),
                timings["llm_generation_ms"],
                timings["total_ms"],
                timings["chunks_retrieved"],
                timings["context_chars"],
            )

            citations = self._parse_citations(answer, sources)

            yield json.dumps({
                "type": "done",
                "citations": [c.model_dump() for c in citations] if citations else None,
                "timings": timings,
                "model": self._llm._model,
            }) + "\n"

    async def _generate_answer(
        self,
        question: str,
        results: list,
    ) -> str:
        if not results:
            logger.info("No context retrieved — returning fallback answer")
            return FALLBACK_ANSWER

        context = self._build_context(results)

        user_prompt = USER_PROMPT_TEMPLATE.format(
            context=context,
            question=question,
        )

        answer = await self._llm.generate(
            system_prompt=SYSTEM_PROMPT,
            user_prompt=user_prompt,
            temperature=settings.LLM_TEMPERATURE,
        )

        return answer

    def _build_context(self, results: list) -> str:
        """Build context string from retrieved chunks with metadata."""
        parts: list[str] = []
        for i, result in enumerate(results, 1):
            doc_name = result.payload.get("document_name", "Unknown")
            chunk_text = result.payload.get("chunk", "")
            page = result.payload.get("page", "?")
            score = result.score
            chunk_type = result.payload.get("chunk_type", "text")

            # Clean up chunk text — normalize whitespace from OCR artifacts
            cleaned = self._clean_chunk_text(chunk_text)

            # Build source header based on chunk type
            if chunk_type == "image":
                figure_num = result.payload.get("figure_number", "?")
                header = f"[Source {i}] (Document: {doc_name}, Page: {page}, Figure: {figure_num}, Type: Image Caption, Relevance: {score:.0%})"
            elif chunk_type == "table":
                header = f"[Source {i}] (Document: {doc_name}, Page: {page}, Type: Table, Relevance: {score:.0%})"
            else:
                header = f"[Source {i}] (Document: {doc_name}, Page: {page}, Relevance: {score:.0%})"

            parts.append(f"{header}\n{cleaned}")
        return "\n\n".join(parts)

    def _clean_chunk_text(self, text: str) -> str:
        """Clean OCR artifacts and normalize whitespace in chunk text."""
        # Replace multiple newlines with single newline
        text = re.sub(r'\n{3,}', '\n\n', text)
        # Replace lines that are just whitespace
        text = re.sub(r'\n\s*\n', '\n\n', text)
        # Fix broken words across lines (word-\nword -> word-word)
        text = re.sub(r'-\n(\w)', r'-\1', text)
        # Collapse multiple spaces
        text = re.sub(r' {2,}', ' ', text)
        return text.strip()

    def _deduplicate_results(self, results: list) -> list:
        """Remove duplicate chunks (same text content)."""
        seen_texts: set[str] = set()
        unique: list = []
        for result in results:
            chunk_text = result.payload.get("chunk", "")
            # Normalize for comparison
            normalized = chunk_text.strip().lower()[:200]
            if normalized not in seen_texts:
                seen_texts.add(normalized)
                unique.append(result)
        if len(unique) < len(results):
            logger.info(
                "Deduplicated chunks | before={} after={} removed={}",
                len(results), len(unique), len(results) - len(unique),
            )
        return unique

    def _filter_low_relevance(self, results: list) -> list:
        """Filter out chunks below minimum relevance threshold."""
        threshold = settings.SCORE_THRESHOLD
        filtered = [r for r in results if r.score >= threshold]
        if len(filtered) < len(results):
            logger.info(
                "Filtered low-relevance chunks | before={} after={} threshold={}",
                len(results), len(filtered), threshold,
            )
        # Always keep at least 1 result if any were returned
        if not filtered and results:
            filtered = [results[0]]
        return filtered

    def _log_prompt_debug(self, question: str, results: list, user_prompt: str) -> None:
        """Log the full prompt details for debugging."""
        logger.info("=" * 60)
        logger.info("RAG PIPELINE DEBUG")
        logger.info("=" * 60)
        logger.info("QUESTION: {}", question)
        logger.info("RETRIEVED {} CHUNKS:", len(results))
        for i, r in enumerate(results, 1):
            chunk_text = r.payload.get("chunk", "")
            logger.info(
                "  [Source {}] score={:.4f} page={} doc={} type={} text_preview='{}'",
                i, r.score,
                r.payload.get("page", "?"),
                r.payload.get("document_name", "?")[:40],
                r.payload.get("chunk_type", "text"),
                chunk_text[:100].replace("\n", " "),
            )
        logger.info("SYSTEM PROMPT ({} chars):\n{}", len(SYSTEM_PROMPT), SYSTEM_PROMPT[:300])
        logger.info("USER PROMPT ({} chars):\n{}", len(user_prompt), user_prompt[:500])
        logger.info("=" * 60)

    def _build_debug(
        self, question: str, results: list, user_prompt: str, answer: str, timings: dict
    ) -> dict:
        """Build debug info dict returned when DEBUG=True."""
        return {
            "question": question,
            "system_prompt": SYSTEM_PROMPT,
            "user_prompt": user_prompt,
            "raw_answer": answer,
            "model": self._llm._model,
            "retrieved_chunks": [
                {
                    "source_index": i + 1,
                    "score": r.score,
                    "page": r.payload.get("page"),
                    "chunk_index": r.payload.get("chunk_index"),
                    "document": r.payload.get("document_name", ""),
                    "chunk_type": r.payload.get("chunk_type", "text"),
                    "text_preview": r.payload.get("chunk", "")[:300],
                }
                for i, r in enumerate(results)
            ],
            "timings": timings,
        }

    def _parse_citations(
        self,
        answer: str,
        sources: list[SourceReference],
    ) -> list[Citation] | None:
        matches = CITATION_RE.findall(answer)
        if not matches:
            return None

        seen: set[int] = set()
        citations: list[Citation] = []
        for m in matches:
            idx = int(m) - 1
            if idx in seen or idx < 0 or idx >= len(sources):
                continue
            seen.add(idx)
            src = sources[idx]
            citations.append(
                Citation(
                    source_index=idx,
                    document_id=src.document_id,
                    filename=src.filename,
                    page=src.page,
                    chunk_index=src.chunk_index,
                )
            )
        return citations if citations else None

    def _validate(self, query: Query) -> None:
        if not query.text.strip():
            raise QueryValidationError("Query text must not be empty")
        if len(query.text) > 4096:
            raise QueryValidationError("Query text must not exceed 4096 characters")
