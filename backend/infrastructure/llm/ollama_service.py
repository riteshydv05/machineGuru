import asyncio
import time
from collections.abc import AsyncGenerator

from loguru import logger
from ollama import AsyncClient

from core.benchmark import measure
from core.concurrency import llm_limiter
from core.config import settings
from core.exceptions import LlmError
from core.memory import memory_track


class OllamaService:
    def __init__(
        self,
        base_url: str = settings.OLLAMA_BASE_URL,
        model: str = settings.LLM_MODEL,
    ) -> None:
        self._client = AsyncClient(host=base_url)
        self._model = model
        self._generation_count = 0
        self._total_tokens = 0
        self._total_time = 0.0

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        temperature: float = settings.LLM_TEMPERATURE,
    ) -> str:
        chunks: list[str] = []
        async for chunk in self.generate_stream(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            temperature=temperature,
        ):
            chunks.append(chunk)
        return "".join(chunks)

    async def generate_stream(
        self,
        system_prompt: str,
        user_prompt: str,
        temperature: float = settings.LLM_TEMPERATURE,
    ) -> AsyncGenerator[str, None]:
        logger.debug(
            "LLM generate_stream | model={} temp={} sys_len={} user_len={} ctx={} predict={}",
            self._model,
            temperature,
            len(system_prompt),
            len(user_prompt),
            settings.NUM_CTX,
            settings.NUM_PREDICT,
        )

        await llm_limiter.acquire()
        try:
            start = time.perf_counter()
            token_count = 0
            first_token_time: float | None = None

            async with memory_track("llm_generate"):
                stream = await self._client.chat(
                    model=self._model,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                    options={
                        "temperature": temperature,
                        "num_predict": settings.NUM_PREDICT,
                        "top_p": 0.9,
                        "repeat_penalty": 1.15,
                        "top_k": 40,
                        "num_ctx": settings.NUM_CTX,
                    },
                    stream=True,
                    keep_alive=settings.LLM_KEEP_ALIVE,
                )

                async for part in stream:
                    content = part.get("message", {}).get("content", "")
                    if content:
                        token_count += 1
                        if first_token_time is None:
                            first_token_time = time.perf_counter() - start
                        yield content

            elapsed = time.perf_counter() - start
            self._generation_count += 1
            self._total_tokens += token_count
            self._total_time += elapsed

            llm_limiter.release()

            logger.info(
                "LLM stream complete | model={} tokens={} time={:.2f}s "
                "first_token={:.2f}s tps={:.0f} total_calls={} total_tokens={}",
                self._model,
                token_count,
                elapsed,
                first_token_time or 0.0,
                token_count / elapsed if elapsed > 0 else 0,
                self._generation_count,
                self._total_tokens,
            )

            if elapsed > 10.0:
                logger.warning(
                    "Slow LLM generation detected | model={} time={:.2f}s tokens={}",
                    self._model,
                    elapsed,
                    token_count,
                )

        except Exception as exc:
            llm_limiter.release()
            logger.error("LLM generation failed | error={}", exc)
            raise LlmError(
                message="Failed to generate LLM response",
                detail=str(exc),
            ) from exc

    @property
    def stats(self) -> dict:
        return {
            "model": self._model,
            "generation_count": self._generation_count,
            "total_tokens": self._total_tokens,
            "total_time_seconds": round(self._total_time, 3),
            "avg_tps": round(self._total_tokens / self._total_time, 1) if self._total_time > 0 else 0,
        }
