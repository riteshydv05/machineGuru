import importlib.util
import pathlib

# Python resolves the package (this directory) before the sibling ingestion.py.
# We load the sibling file explicitly by path and re-export IngestionUseCase.
_spec = importlib.util.spec_from_file_location(
    "use_cases._ingestion_module",
    pathlib.Path(__file__).parent.parent / "ingestion.py",
)
assert _spec and _spec.loader
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)  # type: ignore[union-attr]

IngestionUseCase = _mod.IngestionUseCase
IngestionResult = _mod.IngestionResult

__all__ = ["IngestionUseCase", "IngestionResult"]
