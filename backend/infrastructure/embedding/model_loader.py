import os
import threading
from typing import Any

from loguru import logger

from core.benchmark import measure
from core.config import settings
from core.exceptions import EmbeddingError
from core.memory import ManagedModel, ModelRegistry

_USE_FP16 = os.environ.get("USE_FP16", "0") == "1"
_DEVICE = os.environ.get("DEVICE", "cpu")
_USE_FLASH_ATTENTION = os.environ.get("USE_FLASH_ATTENTION", "0") == "1"

_model: Any = None
_model_lock = threading.Lock()


class SentenceTransformerModel(ManagedModel):
    def __init__(self) -> None:
        self._model: Any = None
        self._dim: int = 384
        self._loaded_flag = False

    def load(self) -> None:
        global _model
        if self._loaded_flag:
            return

        logger.info(
            "Loading embedding model | model={} device={} fp16={} flash_attn={}",
            settings.EMBEDDING_MODEL,
            _DEVICE,
            _USE_FP16,
            _USE_FLASH_ATTENTION,
        )

        with measure("load_embedding_model"):
            try:
                from sentence_transformers import SentenceTransformer

                model_kwargs: dict = {"device": _DEVICE}

                if _DEVICE != "cpu":
                    model_kwargs["model_kwargs"] = {}
                    if _USE_FLASH_ATTENTION:
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

                if _DEVICE != "cpu" and _USE_FP16:
                    self._model.half()
                    logger.info("Embedding model converted to FP16")

                self._dim = self._model.get_sentence_embedding_dimension() or 384
                self._loaded_flag = True
                _model = self._model

                logger.info(
                    "Embedding model ready | model={} dim={} device={}",
                    settings.EMBEDDING_MODEL,
                    self._dim,
                    _DEVICE,
                )

            except Exception as exc:
                logger.error("Failed to load embedding model | error={}", exc)
                raise EmbeddingError(
                    message="Failed to load embedding model",
                    detail=str(exc),
                ) from exc

    def unload(self) -> None:
        global _model
        if not self._loaded_flag:
            return
        logger.info("Unloading embedding model")
        import gc
        del self._model
        self._model = None
        _model = None
        self._loaded_flag = False
        if _DEVICE != "cpu":
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


_model_instance = SentenceTransformerModel()
ModelRegistry.register("embedding", _model_instance)


def get_embedding_model() -> Any:
    return _model_instance.model
