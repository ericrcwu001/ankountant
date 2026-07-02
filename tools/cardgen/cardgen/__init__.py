"""Ankountant Phase-2a RAG card generator (build-time, offline batch tool).

Runtime is AI-off: this tool only runs at build time to pre-generate cards.
See docs_ankountant/rag/ (design) and 07-implementation-contract.md (this code).
"""

__all__ = ["config", "models", "providers"]
