"""
Infrastructure Layer — Framework & Driver Adapters.

Responsibilities:
  - database:     Qdrant vector store client
  - embedding:    HuggingFace embedding model wrapper
  - llm:          Ollama LLM client
  - document_processing: PyMuPDF parser

Each subpackage will contain a concrete implementation of a port
defined in the domain / use_cases layer.  Swap implementations
here without touching business logic.
"""
