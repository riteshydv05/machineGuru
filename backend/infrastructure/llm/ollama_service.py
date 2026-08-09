"""
LLM service — communicates with the Ollama REST API directly via httpx.

No ollama SDK is used. All calls go to the Ollama /api/generate endpoint.
Model is read from settings.LLM_MODEL (configurable via .env).
Options are tuned for resource-constrained deployments (Jetson Orin).
"""

import json
import time
from collections.abc import AsyncGenerator

import httpx
from loguru import logger

from core.benchmark import measure
from core.concurrency import llm_limiter
from core.config import settings
from core.exceptions import LlmError
from core.memory import memory_track

# Default generation options (tuned for constrained devices)
_DEFAULT_OPTIONS: dict = {
    "num_ctx": settings.NUM_CTX,   # Keep context small — saves ~500 MB RAM
    "num_gpu": 1,                   # 1 GPU device on Jetson Orin
    "use_mmap": True,               # Memory-mapped loading
}


class OllamaService:
    """Call the Ollama REST API directly without the ollama Python SDK."""

    def __init__(
        self,
        base_url: str = settings.OLLAMA_BASE_URL,
        model: str = settings.LLM_MODEL,
    ) -> None:
        self._model = model
        self._base_url = base_url.rstrip("/")
        self._api_url = f"{self._base_url}/api/generate"
        self._generation_count = 0
        self._total_tokens = 0
        self._total_time = 0.0
        self._connectivity_checked = False

        # Shared async HTTP client (connection-pooled)
        self._http = httpx.AsyncClient(timeout=settings.REQUEST_TIMEOUT_SECONDS)

        logger.info(
            "OllamaService initialized | model={} url={}",
            self._model,
            self._api_url,
        )


    # ------------------------------------------------------------------ #
    # Public interface                                                     #
    # ------------------------------------------------------------------ #

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        temperature: float = settings.LLM_TEMPERATURE,
    ) -> str:
        """Non-streaming generation — collect all chunks and return as string."""
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
        """
        Streaming generation via Ollama REST /api/generate.

        Builds a combined prompt from system + user parts, posts to Ollama
        with stream=True, and yields each partial response token.
        """
        # Combine system + user prompts into a single prompt string
        combined_prompt = (
            f"<|system|>\n{system_prompt}\n<|user|>\n{user_prompt}\n<|assistant|>\n"
        )

        # Check Ollama connectivity on first request
        if not self._connectivity_checked:
            await self._check_connectivity()
            self._connectivity_checked = True

        payload = {
            "model": self._model,
            "prompt": combined_prompt,
            "stream": True,
            "options": {
                **_DEFAULT_OPTIONS,
                "temperature": temperature,
                "num_predict": settings.NUM_PREDICT,
                "top_p": 0.9,
                "repeat_penalty": 1.15,
                "top_k": 40,
            },
        }

        logger.debug(
            "LLM generate_stream | model={} temp={} sys_len={} user_len={} ctx={} predict={}",
            self._model,
            temperature,
            len(system_prompt),
            len(user_prompt),
            settings.NUM_CTX,
            settings.NUM_PREDICT,
        )

        async with llm_limiter:
            try:
                start = time.perf_counter()
                token_count = 0
                first_token_time: float | None = None

                async with memory_track("llm_generate"):
                    # Stream NDJSON lines from Ollama
                    async with self._http.stream(
                        "POST", self._api_url, json=payload
                    ) as response:
                        if response.status_code != 200:
                            body = await response.aread()
                            raise LlmError(
                                message="Ollama API returned an error",
                                detail=f"HTTP {response.status_code}: {body.decode()}",
                            )

                        async for line in response.aiter_lines():
                            if not line:
                                continue
                            try:
                                data = json.loads(line)
                            except json.JSONDecodeError:
                                continue

                            content = data.get("response", "")
                            if content:
                                token_count += 1
                                if first_token_time is None:
                                    first_token_time = time.perf_counter() - start
                                yield content

                            # Ollama sends {"done": true} as the final line
                            if data.get("done"):
                                break

                elapsed = time.perf_counter() - start
                self._generation_count += 1
                self._total_tokens += token_count
                self._total_time += elapsed

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

            except LlmError:
                raise
            except httpx.ConnectError as exc:
                logger.error(
                    "Cannot connect to Ollama at {} | error={}",
                    self._api_url,
                    exc,
                )
                self._connectivity_checked = False
                raise LlmError(
                    message=f"Cannot connect to Ollama at {self._base_url}. "
                            f"Make sure Ollama is running ('ollama serve') and "
                            f"OLLAMA_BASE_URL is correct in .env.",
                    detail=str(exc),
                ) from exc
            except Exception as exc:
                logger.error("LLM generation failed | error={}", exc)
                raise LlmError(
                    message="Failed to generate LLM response",
                    detail=str(exc),
                ) from exc

    async def _check_connectivity(self) -> None:
        """Verify Ollama is reachable before first LLM call."""
        try:
            resp = await self._http.get(self._base_url, timeout=5.0)
            if resp.status_code == 200:
                logger.info("Ollama connectivity OK | url={}", self._base_url)
            else:
                logger.warning(
                    "Ollama responded with unexpected status | url={} status={}",
                    self._base_url,
                    resp.status_code,
                )
        except Exception as exc:
            logger.warning(
                "Ollama not reachable at {} — LLM calls will fail | error={}",
                self._base_url,
                exc,
            )

    async def close(self) -> None:
        """Close the underlying HTTP client."""
        await self._http.aclose()

    # ------------------------------------------------------------------ #
    # Stats                                                                #
    # ------------------------------------------------------------------ #

    @property
    def stats(self) -> dict:
        return {
            "model": self._model,
            "generation_count": self._generation_count,
            "total_tokens": self._total_tokens,
            "total_time_seconds": round(self._total_time, 3),
            "avg_tps": round(self._total_tokens / self._total_time, 1) if self._total_time > 0 else 0,
        }
