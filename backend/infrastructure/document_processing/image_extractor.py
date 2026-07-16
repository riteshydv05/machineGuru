"""
Image extraction from PDF documents using PyMuPDF.

Extracts embedded images from each page, saves them to disk,
and optionally runs OCR on images containing text.
"""

import io
from pathlib import Path

import fitz
from loguru import logger
from PIL import Image


class ExtractedImage:
    """Represents an image extracted from a PDF."""
    def __init__(
        self,
        image_path: str,
        page_number: int,
        figure_index: int,
        width: int,
        height: int,
        ocr_text: str = "",
    ):
        self.image_path = image_path
        self.page_number = page_number
        self.figure_index = figure_index
        self.figure_label = f"Figure {page_number}.{figure_index}"
        self.width = width
        self.height = height
        self.ocr_text = ocr_text


class ImageExtractor:
    """Extract images from PDF files."""

    MIN_IMAGE_SIZE = 100     # minimum width/height in pixels
    MIN_IMAGE_AREA = 15000   # minimum area in pixels (filters out tiny icons)

    def __init__(self, output_dir: str = "uploads/images") -> None:
        self._output_dir = Path(output_dir)

    def extract_images(
        self,
        pdf_path: str,
        document_id: str,
    ) -> list[ExtractedImage]:
        """Extract all meaningful images from a PDF."""
        doc_output_dir = self._output_dir / document_id
        doc_output_dir.mkdir(parents=True, exist_ok=True)

        extracted: list[ExtractedImage] = []
        doc = fitz.open(pdf_path)

        try:
            for page_num in range(len(doc)):
                page = doc[page_num]
                image_list = page.get_images(full=True)

                fig_index = 0
                for img_info in image_list:
                    xref = img_info[0]
                    try:
                        base_image = doc.extract_image(xref)
                        if not base_image:
                            continue

                        image_bytes = base_image["image"]
                        width = base_image.get("width", 0)
                        height = base_image.get("height", 0)

                        # Filter out tiny images (icons, bullets, etc.)
                        if width < self.MIN_IMAGE_SIZE or height < self.MIN_IMAGE_SIZE:
                            continue
                        if width * height < self.MIN_IMAGE_AREA:
                            continue

                        fig_index += 1
                        ext = base_image.get("ext", "png")
                        filename = f"page{page_num + 1}_fig{fig_index}.{ext}"
                        image_path = doc_output_dir / filename

                        # Save image
                        image_path.write_bytes(image_bytes)

                        # Try OCR for text-heavy images
                        ocr_text = self._try_ocr(image_bytes)

                        img = ExtractedImage(
                            image_path=str(image_path),
                            page_number=page_num + 1,
                            figure_index=fig_index,
                            width=width,
                            height=height,
                            ocr_text=ocr_text,
                        )
                        extracted.append(img)

                    except Exception as exc:
                        logger.warning(
                            "Failed to extract image | page={} xref={} error={}",
                            page_num + 1, xref, exc,
                        )
                        continue

        finally:
            num_pages = len(doc)
            doc.close()

        logger.info(
            "Extracted {} images from '{}' ({} pages)",
            len(extracted), pdf_path, num_pages,
        )
        return extracted

    def _try_ocr(self, image_bytes: bytes) -> str:
        """Attempt OCR on an image. Returns empty string if OCR not available."""
        try:
            import pytesseract
            image = Image.open(io.BytesIO(image_bytes))
            # Convert to RGB if needed
            if image.mode not in ("RGB", "L"):
                image = image.convert("RGB")
            text = pytesseract.image_to_string(image, timeout=10)
            return text.strip() if text else ""
        except ImportError:
            logger.debug("pytesseract not available — skipping OCR")
            return ""
        except Exception as exc:
            logger.debug("OCR failed | error={}", exc)
            return ""
