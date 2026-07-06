import gc
import time
from abc import ABC, abstractmethod
from contextlib import asynccontextmanager, contextmanager
from typing import Any

from loguru import logger

from core.benchmark import _get_memory_mb, force_gc


MEMORY_BUDGET_MB = 2048
WARN_THRESHOLD_MB = 1536
CRITICAL_THRESHOLD_MB = 1792


class ManagedModel(ABC):
    @abstractmethod
    def unload(self) -> None:
        ...

    @abstractmethod
    def load(self) -> None:
        ...

    @property
    @abstractmethod
    def loaded(self) -> bool:
        ...


class ModelRegistry:
    _models: dict[str, ManagedModel] = {}
    _last_used: dict[str, float] = {}
    _idle_timeout: float = 300.0

    @classmethod
    def register(cls, name: str, model: ManagedModel) -> None:
        cls._models[name] = model
        logger.info("Model registered | name={}", name)

    @classmethod
    def touch(cls, name: str) -> None:
        cls._last_used[name] = time.monotonic()

    @classmethod
    def unload_idle(cls) -> int:
        unloaded = 0
        now = time.monotonic()
        for name, model in cls._models.items():
            last = cls._last_used.get(name, 0)
            if model.loaded and (now - last) > cls._idle_timeout:
                logger.info("Unloading idle model | name={} idle={:.0f}s", name, now - last)
                model.unload()
                unloaded += 1
        return unloaded

    @classmethod
    def unload_all(cls) -> int:
        count = 0
        for name, model in cls._models.items():
            if model.loaded:
                model.unload()
                count += 1
        return count

    @classmethod
    def memory_report(cls) -> dict:
        return {
            name: {
                "loaded": m.loaded,
                "idle_seconds": round(time.monotonic() - cls._last_used.get(name, 0), 1),
            }
            for name, m in cls._models.items()
        }


class MemoryManager:
    def __init__(self, budget_mb: int = MEMORY_BUDGET_MB) -> None:
        self._budget = budget_mb
        self._last_check = 0.0

    def check(self) -> dict:
        now = time.monotonic()
        if now - self._last_check < 5.0:
            return {"action": "skipped"}

        self._last_check = now
        current = _get_memory_mb()
        report: dict = {"current_mb": current, "budget_mb": self._budget}

        if current > CRITICAL_THRESHOLD_MB:
            unloaded = ModelRegistry.unload_all()
            freed = force_gc()
            report["action"] = "critical"
            report["models_unloaded"] = unloaded
            report.update(freed)
            logger.warning(
                "Memory critical! {:.0f}MB / {}MB — unloaded {} models, freed {:.1f}MB",
                current, self._budget, unloaded, freed.get("freed_mb", 0),
            )
        elif current > WARN_THRESHOLD_MB:
            unloaded = ModelRegistry.unload_idle()
            freed = force_gc()
            report["action"] = "warning"
            report["models_unloaded"] = unloaded
            report.update(freed)
            logger.info(
                "Memory pressure: {:.0f}MB / {}MB — unloaded {} idle models",
                current, self._budget, unloaded,
            )
        else:
            report["action"] = "ok"

        return report


memory_manager = MemoryManager()


@contextmanager
def memory_track_sync(label: str = ""):
    before = _get_memory_mb()
    try:
        yield
    finally:
        after = _get_memory_mb()
        delta = after - before
        if abs(delta) > 5:
            logger.debug("Memory delta [{}] {:+.1f}MB ({:.0f}→{:.0f})", label, delta, before, after)
        memory_manager.check()


@asynccontextmanager
async def memory_track(label: str = ""):
    """Async-safe version — use with `async with memory_track(...):`"""
    before = _get_memory_mb()
    try:
        yield
    finally:
        after = _get_memory_mb()
        delta = after - before
        if abs(delta) > 5:
            logger.debug("Memory delta [{}] {:+.1f}MB ({:.0f}→{:.0f})", label, delta, before, after)
        memory_manager.check()
