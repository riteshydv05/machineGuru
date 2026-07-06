from uuid import uuid4


class MachineGuruError(Exception):
    error_code: str = "INTERNAL_ERROR"
    status_code: int = 500

    def __init__(self, message: str, detail: str | None = None) -> None:
        self.message = message
        self.detail = detail
        self.error_id = str(uuid4())
        super().__init__(self.message)


class InvalidFileTypeError(MachineGuruError):
    error_code: str = "INVALID_FILE_TYPE"
    status_code: int = 400

    def __init__(self, filename: str, allowed_extensions: list[str]) -> None:
        super().__init__(
            message=f"File type not supported: '{filename}'",
            detail=f"Allowed extensions: {', '.join(allowed_extensions)}",
        )


class FileTooLargeError(MachineGuruError):
    error_code: str = "FILE_TOO_LARGE"
    status_code: int = 413

    def __init__(self, size_bytes: int, max_bytes: int) -> None:
        super().__init__(
            message="File exceeds maximum allowed size",
            detail=f"Received {size_bytes} bytes, maximum is {max_bytes} bytes",
        )


class DocumentProcessingError(MachineGuruError):
    error_code: str = "DOCUMENT_PROCESSING_ERROR"
    status_code: int = 422

    def __init__(self, message: str, detail: str | None = None) -> None:
        super().__init__(message=message, detail=detail)


class QueryValidationError(MachineGuruError):
    error_code: str = "QUERY_VALIDATION_ERROR"
    status_code: int = 422

    def __init__(self, message: str = "Invalid query") -> None:
        super().__init__(message=message)


class LlmError(MachineGuruError):
    error_code: str = "LLM_ERROR"
    status_code: int = 503

    def __init__(self, message: str, detail: str | None = None) -> None:
        super().__init__(message=message, detail=detail)


class QdrantError(MachineGuruError):
    error_code: str = "QDRANT_ERROR"
    status_code: int = 503

    def __init__(self, message: str, detail: str | None = None) -> None:
        super().__init__(message=message, detail=detail)


class EmbeddingError(MachineGuruError):
    error_code: str = "EMBEDDING_ERROR"
    status_code: int = 500

    def __init__(self, message: str, detail: str | None = None) -> None:
        super().__init__(message=message, detail=detail)


class NotFoundError(MachineGuruError):
    error_code: str = "NOT_FOUND"
    status_code: int = 404

    def __init__(self, resource: str, identifier: str) -> None:
        super().__init__(
            message=f"{resource} not found: '{identifier}'",
        )
