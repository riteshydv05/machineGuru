"""
Vision service for image captioning using Ollama's multimodal models.

Generates descriptive captions for extracted images using models like LLaVA.
"""

import asyncio
import base64
import time
from pathlib import Path

from loguru import logger
from ollama import AsyncClient

from core.config import settings
from core.memory import memory_track


class VisionService:
    """Generate image captions using Ollama vision models."""

    def __init__(
        self,
        base_url: str = settings.OLLAMA_BASE_URL,
        model: str = settings.VISION_MODEL,
    ) -> None:
        self._client = AsyncClient(host=base_url)
        self._model = model
        self._caption_count = 0
        self._total_time = 0.0

    async def caption_image(self, image_path: str) -> str:
        """Generate a detailed caption for a single image."""
        path = Path(image_path)
        if not path.exists():
            logger.warning("Image file not found | path={}", image_path)
            return ""

        try:
            async with memory_track("vision_caption"):
                start = time.perf_counter()

                # Read and encode image
                image_data = base64.b64encode(path.read_bytes()).decode("utf-8")

                response = await self._client.chat(
                    model=self._model,
                    messages=[
                        {
                            "role": "user",
                            "content": (
                                "Describe this technical image in detail. "
                                "If it is a diagram, schematic, or flowchart, describe what it shows, "
                                "including labels, connections, components, and any text visible. "
                                "If it is a table, extract the data. "
                                "If it is a warning or safety icon, describe the warning. "
                                "Be specific and technical."
                            ),
                            "images": [image_data],
                        }
                    ],
                    options={
                        "temperature": 0.1,
                        "num_predict": 512,
                    },
                    keep_alive=settings.LLM_KEEP_ALIVE,
                )

                caption = response.get("message", {}).get("content", "")
                elapsed = time.perf_counter() - start

                self._caption_count += 1
                self._total_time += elapsed

                logger.info(
                    "Image captioned | path={} time={:.2f}s chars={} total_captions={}",
                    path.name, elapsed, len(caption), self._caption_count,
                )

                return caption.strip()

        except Exception as exc:
            logger.error("Vision captioning failed | path={} error={}", image_path, exc)
            return ""

    async def caption_images_batch(
        self,
        image_paths: list[str],
        max_concurrent: int = 2,
    ) -> list[str]:
        """Caption multiple images with concurrency control."""
        sem = asyncio.Semaphore(max_concurrent)

        async def _caption_with_limit(path: str) -> str:
            async with sem:
                return await self.caption_image(path)

        tasks = [_caption_with_limit(p) for p in image_paths]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        captions = []
        for result in results:
            if isinstance(result, Exception):
                logger.warning("Batch caption failed | error={}", result)
                captions.append("")
            else:
                captions.append(result)

        return captions

    @property
    def stats(self) -> dict:
        return {
            "model": self._model,
            "caption_count": self._caption_count,
            "total_time_seconds": round(self._total_time, 3),
            "avg_time_per_caption": round(
                self._total_time / self._caption_count, 2
            ) if self._caption_count > 0 else 0,
        }
