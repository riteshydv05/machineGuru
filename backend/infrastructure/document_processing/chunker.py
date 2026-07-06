from core.config import settings


class RecursiveTextSplitter:
    def __init__(
        self,
        chunk_size: int | None = None,
        chunk_overlap: int | None = None,
    ) -> None:
        self.chunk_size = chunk_size or settings.CHUNK_SIZE
        self.chunk_overlap = chunk_overlap or settings.CHUNK_OVERLAP
        self._separators = ["\n\n", "\n", ". ", "! ", "? ", "; ", ", ", " ", ""]

    def split_text(self, text: str) -> list[str]:
        if not text or not text.strip():
            return []

        chunks = self._split(text, self._separators)

        if self.chunk_overlap > 0 and len(chunks) > 1:
            chunks = self._apply_overlap(chunks)

        return [c.strip() for c in chunks if c.strip()]

    def _split(self, text: str, separators: list[str]) -> list[str]:
        if len(text) <= self.chunk_size or not separators:
            return [text]

        separator = separators[0]
        parts = text.split(separator) if separator else list(text)
        parts = [p for p in parts if p]

        if len(parts) <= 1:
            return self._split(text, separators[1:])

        chunks: list[str] = []
        buffer = ""

        for part in parts:
            glue = separator if buffer else ""
            candidate = f"{buffer}{glue}{part}"

            if len(candidate) <= self.chunk_size:
                buffer = candidate
            else:
                if buffer:
                    chunks.append(buffer)
                if len(part) > self.chunk_size:
                    chunks.extend(self._split(part, separators[1:]))
                else:
                    buffer = part

        if buffer:
            chunks.append(buffer)

        return chunks

    def _apply_overlap(self, chunks: list[str]) -> list[str]:
        result = [chunks[0]]
        for i in range(1, len(chunks)):
            prev = chunks[i - 1]
            tail = prev[-self.chunk_overlap:] if len(prev) >= self.chunk_overlap else prev
            result.append(tail + chunks[i])
        return result
