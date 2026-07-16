import os
import threading
from typing import Any

import httpx
from loguru import logger

from core.benchmark import measure
from core.config import settings
from core.exceptions import EmbeddingError
from core.memory import ManagedModel, ModelRegistry


class SentenceTransformerModel(ManagedModel):
    """Embedding model using SentenceTransformers (local, GPU-accelerated)."""

    def __init__(self) -> None:
        self._model: Any = None
        self._dim: int = 384
        self._loaded_flag = False

    def load(self) -> None:
        if self._loaded_flag:
            return

        device = settings.DEVICE
        use_fp16 = settings.USE_FP16
        use_flash = settings.USE_FLASH_ATTENTION

        logger.info(
            "Loading embedding model | model={} device={} fp16={} flash_attn={}",
            settings.EMBEDDING_MODEL,
            device,
            use_fp16,
            use_flash,
        )

        with measure("load_embedding_model"):
            try:
                from sentence_transformers import SentenceTransformer

                model_kwargs: dict = {"device": device}

                if device != "cpu":
                    model_kwargs["model_kwargs"] = {}
                    if use_flash:
                        try:
                            import torch
                            if torch.cuda.is_available() and torch.cuda.get_device_capability() >= (8, 0):
                                model_kwargs["model_kwargs"]["attn_implementation"] = "flash_attention_2"
                            else:
                                model_kwargs["model_kwargs"]["attn_implementation"] = "sdpa"
                        except Exception:
                            model_kwargs["model_kwargs"]["attn_implementation"] = "sdpa"

                self._model = SentenceTransformer(
                    settings.EMBEDDING_MODEL,
                    **model_kwargs,
                )

                if device != "cpu" and use_fp16:
                    self._model.half()
                    logger.info("Embedding model converted to FP16")

                self._dim = self._model.get_sentence_embedding_dimension() or 384
                self._loaded_flag = True

                logger.info(
                    "Embedding model ready | model={} dim={} device={}",
                    settings.EMBEDDING_MODEL,
                    self._dim,
                    device,
                )

            except Exception as exc:
                logger.error("Failed to load embedding model | error={}", exc)
                raise EmbeddingError(
                    message="Failed to load embedding model",
                    detail=str(exc),
                ) from exc

    def unload(self) -> None:
        if not self._loaded_flag:
            return
        logger.info("Unloading embedding model")
        import gc
        del self._model
        self._model = None
        self._loaded_flag = False
        if settings.DEVICE != "cpu":
            try:
                import torch
                torch.cuda.empty_cache()
            except Exception:
                pass
        gc.collect()

    @property
    def loaded(self) -> bool:
        return self._loaded_flag

    @property
    def model(self) -> Any:
        self.load()
        ModelRegistry.touch("embedding")
        return self._model

    @property
    def dimensions(self) -> int:
        return self._dim

    def encode(self, texts: list[str] | str, **kwargs) -> Any:
        """Encode text(s) using SentenceTransformer.encode()."""
        return self.model.encode(texts, **kwargs)

    def encode_single(self, text: str) -> list[float]:
        """Encode a single text and return as list of floats."""
        embedding = self.model.encode(
            text,
            normalize_embeddings=True,
        )
        return embedding.tolist()


class OllamaEmbeddingModel(ManagedModel):
    """
    Embedding model using Ollama's /api/embeddings endpoint.

    This is a fallback when SentenceTransformers cannot be loaded
    (e.g., missing tzdata, broken pandas, Cloud Lab restrictions).

    Uses the model specified in settings.EMBEDDING_MODEL via Ollama.
    The model must be pulled first: ollama pull <model-name>
    """

    # Default Ollama embedding dimension for common models
    _DEFAULT_DIM = 384

    def __init__(self) -> None:
        self._dim: int = self._DEFAULT_DIM
        self._loaded_flag = False
        self._model_name: str = ""
        self._base_url: str = ""
        self._client: httpx.Client | None = None

    def load(self) -> None:
        if self._loaded_flag:
            return

        self._base_url = settings.OLLAMA_BASE_URL.rstrip("/")
        # For Ollama embeddings, use a simpler model name
        # Convert HuggingFace format to Ollama format if needed
        raw_model = settings.EMBEDDING_MODEL
        if "/" in raw_model:
            # e.g., "intfloat/multilingual-e5-small" -> try as-is first
            self._model_name = raw_model
        else:
            self._model_name = raw_model

        logger.info(
            "Loading Ollama embedding model | model={} url={}",
            self._model_name,
            self._base_url,
        )

        self._client = httpx.Client(timeout=60.0)

        # Probe for dimensions by embedding a test string
        try:
            test_embedding = self._embed_via_ollama("test")
            self._dim = len(test_embedding)
            self._loaded_flag = True
            logger.info(
                "Ollama embedding model ready | model={} dim={}",
                self._model_name,
                self._dim,
            )
        except Exception as exc:
            logger.error(
                "Failed to probe Ollama embeddings | model={} error={}",
                self._model_name,
                exc,
            )
            raise EmbeddingError(
                message=f"Failed to load Ollama embedding model '{self._model_name}'",
                detail=str(exc),
            ) from exc

    def _embed_via_ollama(self, text: str) -> list[float]:
        """Call Ollama /api/embeddings endpoint for a single text."""
        if self._client is None:
            self._client = httpx.Client(timeout=60.0)

        response = self._client.post(
            f"{self._base_url}/api/embeddings",
            json={
                "model": self._model_name,
                "prompt": text,
            },
        )
        response.raise_for_status()
        data = response.json()
        embedding = data.get("embedding", [])
        if not embedding:
            raise EmbeddingError(
                message="Ollama returned empty embedding",
                detail=f"Response: {data}",
            )
        return embedding

    def unload(self) -> None:
        if not self._loaded_flag:
            return
        logger.info("Unloading Ollama embedding model")
        if self._client:
            self._client.close()
            self._client = None
        self._loaded_flag = False

    @property
    def loaded(self) -> bool:
        return self._loaded_flag

    @property
    def model(self) -> Any:
        """Returns self — the OllamaEmbeddingModel IS the model interface."""
        self.load()
        ModelRegistry.touch("embedding")
        return self

    @property
    def dimensions(self) -> int:
        return self._dim

    def encode(
        self,
        texts: list[str] | str,
        batch_size: int = 64,
        normalize_embeddings: bool = True,
        show_progress_bar: bool = False,
        **kwargs,
    ) -> Any:
        """
        Encode texts using Ollama, matching SentenceTransformer.encode() API.
        Returns a list of numpy-like arrays (actually lists) or a single array.
        """
        import numpy as np

        if isinstance(texts, str):
            embedding = self._embed_via_ollama(texts)
            arr = np.array(embedding, dtype=np.float32)
            if normalize_embeddings:
                norm = np.linalg.norm(arr)
                if norm > 0:
                    arr = arr / norm
            return arr

        results = []
        for text in texts:
            embedding = self._embed_via_ollama(text)
            arr = np.array(embedding, dtype=np.float32)
            if normalize_embeddings:
                norm = np.linalg.norm(arr)
                if norm > 0:
                    arr = arr / norm
            results.append(arr)

        return np.array(results)

    def encode_single(self, text: str) -> list[float]:
        """Encode a single text and return as list of floats."""
        embedding = self._embed_via_ollama(text)
        # Normalize
        import numpy as np
        arr = np.array(embedding, dtype=np.float32)
        norm = np.linalg.norm(arr)
        if norm > 0:
            arr = arr / norm
        return arr.tolist()


# ── Model Selection ──────────────────────────────────────────
# Choose embedding backend based on USE_OLLAMA_EMBEDDINGS setting
_model_lock = threading.Lock()
_model: Any = None

if settings.USE_OLLAMA_EMBEDDINGS:
    logger.info("Embedding backend: Ollama (USE_OLLAMA_EMBEDDINGS=true)")
    _model_instance = OllamaEmbeddingModel()
else:
    logger.info("Embedding backend: SentenceTransformers (USE_OLLAMA_EMBEDDINGS=false)")
    _model_instance = SentenceTransformerModel()

ModelRegistry.register("embedding", _model_instance)


def get_embedding_model() -> Any:
    """
    Get the active embedding model instance.

    Returns either a SentenceTransformerModel or OllamaEmbeddingModel,
    both of which support .encode() and .encode_single() methods.
    """
    return _model_instance.model
