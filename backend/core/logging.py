import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from loguru import logger

from core.config import settings

_JSON_LOGGING: bool = False
_REQUEST_ID: str | None = None


def set_request_id(request_id: str) -> None:
    global _REQUEST_ID
    _REQUEST_ID = request_id


def get_request_id() -> str | None:
    return _REQUEST_ID


def serialize_record(record: dict[str, Any]) -> str:
    log_entry: dict[str, Any] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": record["level"].name,
        "logger": record["name"],
        "function": record["function"],
        "line": record["line"],
        "message": record["message"],
    }

    if _REQUEST_ID:
        log_entry["request_id"] = _REQUEST_ID

    if record.get("exception"):
        log_entry["exception"] = str(record["exception"])

    return json.dumps(log_entry) + "\n"


def setup_logging() -> None:
    global _JSON_LOGGING
    _JSON_LOGGING = os.environ.get("JSON_LOGGING", "false").lower() == "true"

    logger.remove()

    log_dir = Path(settings.LOG_DIR)
    log_dir.mkdir(exist_ok=True)

    log_level = os.environ.get("LOG_LEVEL", settings.LOG_LEVEL).upper()

    json_mode = _JSON_LOGGING

    if json_mode:
        logger.add(
            serialize_record,
            level=log_level,
        )
        logger.add(
            log_dir / "machine_guru_{time:YYYY-MM-DD}.json",
            level="DEBUG",
            format=serialize_record,
            rotation=f"{settings.LOG_MAX_SIZE_MB} MB",
            retention=f"{settings.LOG_RETENTION_DAYS} days",
            compression="gz",
        )
    else:
        console_format = (
            "<green>{time:YYYY-MM-DD HH:mm:ss.SSS}</green> | "
            "<level>{level: <7}</level> | "
            "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> | "
            "<level>{message}</level>"
        )
        logger.add(
            sys.stdout,
            level="DEBUG" if settings.DEBUG else log_level,
            format=console_format,
            colorize=True,
        )

        logger.add(
            log_dir / "machine_guru_{time:YYYY-MM-DD}.log",
            level="DEBUG",
            format="{time:YYYY-MM-DD HH:mm:ss.SSS} | {level:<7} | {name}:{function}:{line} | {message}",
            rotation=f"{settings.LOG_MAX_SIZE_MB} MB",
            retention=f"{settings.LOG_RETENTION_DAYS} days",
            compression="gz",
        )

    logger.info("Logging configured | debug={} json={} level={}", settings.DEBUG, json_mode, log_level)
