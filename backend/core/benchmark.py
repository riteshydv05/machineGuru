import asyncio
import functools
import gc
import os
import time
import tracemalloc
from contextlib import contextmanager
from typing import Any, Callable

from loguru import logger


def _get_memory_mb() -> float:
    try:
        import psutil
        proc = psutil.Process(os.getpid())
        return proc.memory_info().rss / (1024 * 1024)
    except ImportError:
        return 0.0


def _get_gpu_info() -> dict:
    info: dict = {"available": False, "memory_mb": 0, "util_pct": 0}
    try:
        import pynvml
        pynvml.nvmlInit()
        handle = pynvml.nvmlDeviceGetHandleByIndex(0)
        mem = pynvml.nvmlDeviceGetMemoryInfo(handle)
        util = pynvml.nvmlDeviceGetUtilizationRates(handle)
        info["available"] = True
        info["memory_mb"] = round(mem.used / (1024 * 1024), 1)
        info["util_pct"] = util.gpu
        pynvml.nvmlShutdown()
    except Exception:
        pass
    return info


def _get_cpu_percent() -> float:
    try:
        import psutil
        return psutil.cpu_percent(interval=0.1)
    except ImportError:
        return 0.0


def _format_bytes(b: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if b < 1024:
            return f"{b:.1f}{unit}"
        b /= 1024
    return f"{b:.1f}TB"


class Timer:
    def __init__(self, name: str = "") -> None:
        self.name = name
        self.elapsed = 0.0

    def __enter__(self) -> "Timer":
        self.start = time.perf_counter()
        return self

    def __exit__(self, *args) -> None:
        self.elapsed = time.perf_counter() - self.start


@contextmanager
def measure(name: str, log: bool = True):
    mem_before = _get_memory_mb()
    cpu_before = _get_cpu_percent()
    gpu_before = _get_gpu_info()

    with Timer(name) as timer:
        yield

    mem_after = _get_memory_mb()
    cpu_after = _get_cpu_percent()
    gpu_after = _get_gpu_info()

    delta_mem = mem_after - mem_before
    delta_gpu = gpu_after.get("memory_mb", 0) - gpu_before.get("memory_mb", 0)

    if log:
        logger.info(
            "BENCHMARK | {} | "
            "time={:.3f}s "
            "ram={:+.1f}MB ({:.0f}MB→{:.0f}MB) "
            "cpu={:.0f}%→{:.0f}% "
            "gpu_mem={:+.0f}MB util={}%→{}%",
            name,
            timer.elapsed,
            delta_mem, mem_before, mem_after,
            cpu_before, cpu_after,
            delta_gpu,
            gpu_before.get("util_pct", 0),
            gpu_after.get("util_pct", 0),
        )


def bench(name: str | None = None):
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def async_wrapper(*args, **kwargs) -> Any:
            label = name or f"{func.__module__}.{func.__qualname__}"
            with measure(label):
                return await func(*args, **kwargs)
        return async_wrapper
    return decorator


class ThroughputMeter:
    def __init__(self, window_seconds: float = 60.0) -> None:
        self._window = window_seconds
        self._timestamps: list[float] = []

    def record(self) -> None:
        now = time.monotonic()
        self._timestamps.append(now)
        cutoff = now - self._window
        self._timestamps = [t for t in self._timestamps if t > cutoff]

    @property
    def rps(self) -> float:
        if not self._timestamps:
            return 0.0
        window = self._timestamps[-1] - self._timestamps[0]
        if window <= 0:
            return float(len(self._timestamps))
        return len(self._timestamps) / window

    @property
    def total(self) -> int:
        return len(self._timestamps)


query_throughput = ThroughputMeter()


class MemorySnapshot:
    def __init__(self) -> None:
        self._baseline = _get_memory_mb()

    def snapshot(self, label: str = "") -> float:
        current = _get_memory_mb()
        delta = current - self._baseline
        logger.info("MEMORY{} | current={:.1f}MB delta={:+.1f}MB", f" [{label}]" if label else "", current, delta)
        return current


def force_gc() -> dict:
    gc_old = _get_memory_mb()
    unreachable = gc.collect()
    collected = gc.collect(2)
    gc_new = _get_memory_mb()
    freed = gc_old - gc_new
    if freed > 1:
        logger.info("GC freed {:.1f}MB ({} objects collected)", freed, collected + unreachable)
    return {"freed_mb": round(freed, 1), "objects": collected + unreachable}
