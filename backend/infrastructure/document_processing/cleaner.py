import re
import unicodedata


class TextCleaner:
    def clean(self, text: str) -> str:
        if not text:
            return ""

        text = unicodedata.normalize("NFKC", text)
        text = re.sub(r"\r\n", "\n", text)
        text = re.sub(r"\r", "\n", text)
        text = re.sub(r"\x00", "", text)
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        text = re.sub(r"[\u200b-\u200f\u2028-\u202f\ufeff]", "", text)
        text = text.strip()

        return text
