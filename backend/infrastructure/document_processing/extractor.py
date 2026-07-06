from pathlib import Path

import fitz
from docx import Document as DocxDocument


class TextExtractor:
    def extract(self, file_path: str) -> tuple[str, int]:
        pages, _ = self.extract_pages(file_path)
        return "\n".join(pages), len(pages)

    def extract_pages(self, file_path: str) -> tuple[list[str], int]:
        ext = Path(file_path).suffix.lower()
        extractors = {
            ".pdf": self._extract_pdf_pages,
            ".txt": self._extract_txt_pages,
            ".docx": self._extract_docx_pages,
        }
        extractor = extractors.get(ext)
        if extractor is None:
            raise ValueError(f"Unsupported file extension: {ext}")
        return extractor(file_path)

    def _extract_pdf_pages(self, file_path: str) -> tuple[list[str], int]:
        doc = fitz.open(file_path)
        try:
            pages = [page.get_text() for page in doc]
            page_count = len(pages)
        finally:
            doc.close()
        return pages, page_count

    def _extract_txt_pages(self, file_path: str) -> tuple[list[str], int]:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        return [text], 1

    def _extract_docx_pages(self, file_path: str) -> tuple[list[str], int]:
        doc = DocxDocument(file_path)
        text = "\n".join(p.text for p in doc.paragraphs)
        return [text], 1
